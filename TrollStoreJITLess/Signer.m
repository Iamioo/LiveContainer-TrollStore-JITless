// SPDX-License-Identifier: AGPL-3.0-only
// Adapter for opa334/TrollStore's fastPathSign and ChOma (see README.md).
#import <Foundation/Foundation.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdio.h>
#include "FAT.h"
#include "MachO.h"
#include "Host.h"
#include "FileStream.h"
#include "codesign.h"
#include "coretrust_bug.h"

static BOOL fail(NSError **error, NSString *path, NSInteger code, NSString *reason) {
    if (error) *error = [NSError errorWithDomain:@"LCTrollStoreSigner" code:code
        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %@ (%ld)", path.lastPathComponent, reason, (long)code]}];
    return NO;
}

static BOOL signFile(NSString *path, NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *attributes = [fm attributesOfItemAtPath:path error:error];
    if (!attributes) return NO;
    // Never follow links supplied inside an imported bundle.
    if (![attributes[NSFileType] isEqual:NSFileTypeRegular]) return YES;
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!file) return fail(error, path, 1, @"Cannot read file");
    NSData *magicData = [file readDataOfLength:4];
    [file closeFile];
    uint32_t magic = 0;
    if (magicData.length != sizeof(magic)) return YES;
    [magicData getBytes:&magic length:sizeof(magic)];
    if (magic != MH_MAGIC && magic != MH_CIGAM && magic != MH_MAGIC_64 && magic != MH_CIGAM_64 &&
        magic != FAT_MAGIC && magic != FAT_CIGAM && magic != FAT_MAGIC_64 && magic != FAT_CIGAM_64) return YES;

    FAT *fat = fat_init_from_path(path.fileSystemRepresentation);
    if (!fat) return fail(error, path, 2, @"Invalid Mach-O file");
    MachO *slice = fat_find_preferred_slice(fat);
    if (!slice) {
        fat_free(fat);
        return fail(error, path, 3, @"No compatible ARM64 slice");
    }
    uint32_t type = macho_get_filetype(slice);
    if (type != MH_EXECUTE && type != MH_DYLIB && type != MH_BUNDLE) {
        fat_free(fat);
        return YES;
    }

    // A new inode avoids reusing the kernel's cached signature for the old file.
    // Work beside the original so the final rename stays on the same filesystem.
    NSString *template = [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:@".lcts-XXXXXX"];
    char *temporaryPath = strdup(template.fileSystemRepresentation);
    int fd = mkstemp(temporaryPath);
    if (fd < 0) {
        int savedError = errno;
        free(temporaryPath);
        return fail(error, path, savedError, [NSString stringWithFormat:@"Cannot create signing file: %s", strerror(savedError)]);
    }
    NSString *temporary = [NSString stringWithUTF8String:temporaryPath];
    free(temporaryPath);
    MemoryStream *output = file_stream_init_from_file_descriptor(fd, 0, 0,
        FILE_STREAM_FLAG_WRITABLE | FILE_STREAM_FLAG_AUTO_EXPAND);
    close(fd);
    int result = -1;
    NSString *stage = @"copy ARM64 slice";
    if (output) {
        MemoryStream *input = macho_get_stream(slice);
        result = memory_stream_copy_data(input, 0, output, 0, memory_stream_get_size(input));
        memory_stream_free(output);
    }
    fat_free(fat);
    if (result == 0) {
        stage = @"ad-hoc signing";
        result = codesign_sign_adhoc(temporary.fileSystemRepresentation, false, @{});
    }
    if (result == 0) {
        stage = @"CoreTrust signing";
        result = apply_coretrust_bypass(temporary.fileSystemRepresentation);
    }
    if (result != 0) {
        [fm removeItemAtPath:temporary error:nil];
        return fail(error, path, result, [NSString stringWithFormat:@"%@ failed; original file preserved. Path: %@", stage, path]);
    }
    mode_t mode = [attributes[NSFilePosixPermissions] unsignedShortValue];
    if (chmod(temporary.fileSystemRepresentation, mode) != 0 ||
        rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        int savedError = errno;
        [fm removeItemAtPath:temporary error:nil];
        return fail(error, path, savedError, @"Cannot replace signed file");
    }
    return YES;
}

__attribute__((visibility("default")))
BOOL LCTSSignPath(NSString *path, NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *attributes = [fm attributesOfItemAtPath:path error:error];
    if (!attributes) return NO;
    if (![attributes[NSFileType] isEqual:NSFileTypeDirectory]) return signFile(path, error);
    // Collect first: newly created signing files must not enter the enumeration.
    __block NSError *walkError = nil;
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:path]
        includingPropertiesForKeys:nil options:0 errorHandler:^BOOL(NSURL *url, NSError *failure) {
            walkError = failure;
            return NO;
        }];
    NSArray<NSURL *> *files = enumerator.allObjects;
    if (walkError || !enumerator) {
        if (error) *error = walkError;
        return NO;
    }
    for (NSURL *file in files) {
        @autoreleasepool {
            if (!signFile(file.path, error)) return NO;
        }
    }
    return YES;
}
