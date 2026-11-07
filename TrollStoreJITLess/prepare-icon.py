"""Fit the supplied icon to Apple's required icon dimensions before actool."""
import json
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
source = root / "TrollStoreJITLess/NextcloudIcon.png"
for catalog in (root / "Resources/Assets.xcassets").glob("AppIcon*.appiconset"):
    definition = json.loads((catalog / "Contents.json").read_text())
    for entry in definition["images"]:
        subprocess.run(["sips", "-z", "1024", "1024", str(source), "--out", str(catalog / entry["filename"])], check=True)
for filename, size in [("AppIconGrey60x60@2x.png", 120), ("AppIconGrey76x76@2x~ipad.png", 152)]:
    subprocess.run(["sips", "-z", str(size), str(size), str(source), "--out", str(root / "Resources" / filename)], check=True)
