"""Package an Xcode archive for TrollStore; run on macOS with Xcode."""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def prepare_entitlements(bundle, executable, host):
    # Recover Xcode's expanded entitlements when present; otherwise expand the
    # source plist ourselves because this archive was built without codesigning.
    source = ROOT / "entitlements.xml" if host else ROOT / "LiveProcess/LiveProcess.entitlements"
    values = plistlib.loads(source.read_bytes())
    bundle_id = plistlib.loads((bundle / "Info.plist").read_bytes())["CFBundleIdentifier"]
    replacements = {
        "$(DEVELOPMENT_TEAM)": "AAAAA11111",
        "$(PRODUCT_BUNDLE_IDENTIFIER)": bundle_id,
        "$(AppIdentifierPrefix)": "AAAAA11111.",
        "$(APP_GROUP_SIDESTORE)": "group.com.SideStore.SideStore",
        "$(APP_GROUP_ALTSTORE)": "group.com.rileytestut.AltStore",
    }

    def expand(item):
        if isinstance(item, str):
            for key, replacement in replacements.items():
                item = item.replace(key, replacement)
            if "$(" in item:
                raise ValueError(f"Unexpanded entitlement: {item}")
        elif isinstance(item, list):
            item = [expand(value) for value in item]
        elif isinstance(item, dict):
            item = {key: expand(value) for key, value in item.items()}
        return item

    values = expand(values)
    # Retain the data container. No dynamic-codesigning or debugger entitlement.
    values["com.apple.private.security.no-sandbox"] = True
    values["com.apple.private.security.storage.AppDataContainers"] = True
    values["get-task-allow"] = True
    with tempfile.NamedTemporaryFile(suffix=".plist") as temporary:
        temporary.write(plistlib.dumps(values))
        temporary.flush()
        subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements", temporary.name,
                        "--generate-entitlement-der", str(executable)], check=True)


def main():
    source = pathlib.Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="lc-trollstore-") as temporary:
        payload = pathlib.Path(temporary) / "Payload"
        app = payload / "LiveContainer.app"
        shutil.copytree(source, app, symlinks=True)
        # Keep the first version focused on single-app launching on iOS 16.
        shutil.rmtree(app / "PlugIns", ignore_errors=True)
        support = app / "Frameworks/SideStoreSupport.framework"
        if support.exists():
            shutil.rmtree(support)
        info_path = app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["LCTrollStoreJITLess"] = True
        info["CFBundleDisplayName"] = "LiveContainer TS"
        info["MinimumOSVersion"] = "16.0"
        info_path.write_bytes(plistlib.dumps(info))
        subprocess.run(["bash", str(ROOT / "TrollStoreJITLess/build-signer.sh"),
                        str(app / "Frameworks")], cwd=ROOT, check=True)
        # TrollStore will apply its CoreTrust signature to all these binaries.
        # The host's ad-hoc signature supplies entitlements for it to preserve.
        subprocess.run(["codesign", "--force", "--sign", "-",
                        str(app / "Frameworks/LCTrollStoreSigner.dylib")], check=True)
        prepare_entitlements(app, app / info["CFBundleExecutable"], True)
        output = ROOT / "LiveContainer-TrollStore-JITless.tipa"
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(payload.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(payload.parent))
        print(output)


if __name__ == "__main__":
    main()
