"""Validate coexistence, metadata and host permissions in the actual TIPA."""
import pathlib
import plistlib
import struct
import sys
import zipfile

with zipfile.ZipFile(pathlib.Path(sys.argv[1])) as archive:
    assert archive.testzip() is None
    root = "Payload/LiveContainer.app/"
    info = plistlib.loads(archive.read(root + "Info.plist"))
    expected = {"CFBundleDisplayName": "Nextcloud", "CFBundleName": "Nextcloud",
                "CFBundleIdentifier": "it.twsweb.Nextcloud", "CFBundleVersion": "0",
                "CFBundleShortVersionString": "7.0.7", "MinimumOSVersion": "15.0",
                "LCTrollStoreJITLess": True, "UIFileSharingEnabled": True,
                "LSSupportsOpeningDocumentsInPlace": True}
    for key, value in expected.items():
        assert info[key] == value, (key, info.get(key))
    assert info["CFBundleExecutable"] == "LiveContainer"
    assert info["CFBundleURLTypes"][0]["CFBundleURLSchemes"] == ["nextcloudlc"]
    assert root + "Frameworks/LCTrollStoreSigner.dylib" in archive.namelist()
    assert not any(name.startswith(root + "PlugIns/") for name in archive.namelist())
    data = archive.read(root + "LiveContainer")
    assert struct.unpack_from("<I", data)[0] == 0xfeedfacf
    position = 32
    entitlements = None
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, position)
        if command == 0x1d:
            start, length = struct.unpack_from("<II", data, position + 8)
            signature = data[start:start + length]
            for index in range(struct.unpack_from(">I", signature, 8)[0]):
                slot, offset = struct.unpack_from(">II", signature, 12 + 8 * index)
                if slot == 5:
                    blob_length = struct.unpack_from(">I", signature, offset + 4)[0]
                    entitlements = plistlib.loads(signature[offset + 8:offset + blob_length])
        position += size
    assert entitlements is not None
    assert entitlements["application-identifier"] == "AAAAA11111.it.twsweb.Nextcloud"
    assert entitlements["com.apple.private.security.container-required"] == "it.twsweb.Nextcloud"
    assert entitlements["com.apple.security.application-groups"] == ["group.it.twsweb.Nextcloud"]
    assert entitlements["get-task-allow"] is True
    assert len(entitlements["keychain-access-groups"]) == 128
    assert all("it.twsweb.Nextcloud.shared" in value for value in entitlements["keychain-access-groups"])
    for key in ["dynamic-codesigning", "com.apple.private.cs.debugger", "com.apple.private.skip-library-validation"]:
        assert key not in entitlements
    print("PASS: Nextcloud metadata, independent identity, Files access, container and signing entitlements")
