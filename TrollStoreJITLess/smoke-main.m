#import <Foundation/Foundation.h>
extern BOOL LCTSSignPath(NSString *, NSError **);
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *path = [NSString stringWithUTF8String:argv[1]];
        NSError *error = nil;
        if (!LCTSSignPath(path, &error)) {
            NSLog(@"Signer smoke test failed: %@", error);
            return 1;
        }
        return 0;
    }
}
