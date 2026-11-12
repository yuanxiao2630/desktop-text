#!/usr/bin/env python3
"""Build the macOS application using Apple's locally installed toolchain."""

import argparse
import platform
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.0.0"


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("arm64", "x86_64", "universal"),
                        default=platform.machine(), help="Defaults to the current Mac.")
    parser.add_argument("--output", type=Path, default=ROOT / "dist",
                        help="Output directory for the application and ZIP archive.")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Requires macOS and the Xcode command line tools.")
    if args.arch not in ("arm64", "x86_64", "universal"):
        parser.error("Unsupported Mac architecture.")
    for tool in ("xcrun", "codesign", "iconutil", "ditto"):
        if not shutil.which(tool):
            parser.error(f"Missing tool: {tool}. Install the Xcode command line tools.")

    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    cache = ROOT / ".build"
    cache.mkdir(exist_ok=True)
    app = output / "桌面文字.app"
    resources = app / "Contents/Resources"
    binary = app / "Contents/MacOS/DesktopText"
    resources.mkdir(parents=True, exist_ok=True)
    binary.parent.mkdir(parents=True, exist_ok=True)
    info = {
        "CFBundleName": "桌面文字",
        "CFBundleDisplayName": "桌面文字",
        "CFBundleIdentifier": "local.desktoptext.mac",
        "CFBundleExecutable": "DesktopText",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": VERSION,
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "14.0",
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
        "NSPrincipalClass": "NSApplication",
        "CFBundleIconFile": "AppIcon",
        "CFBundleDevelopmentRegion": "zh_CN",
        "CFBundleLocalizations": ["zh_CN", "en"],
    }
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    architectures = ("arm64", "x86_64") if args.arch == "universal" else (args.arch,)
    binaries = []
    for architecture in architectures:
        part = cache / f"DesktopText-{architecture}"
        run("xcrun", "swiftc", "-swift-version", "5", "-O",
            "-target", f"{architecture}-apple-macosx14.0",
            "-framework", "AppKit", "-framework", "ServiceManagement",
            ROOT / "src/main.swift", "-o", part)
        binaries.append(part)
    if len(binaries) == 2:
        run("xcrun", "lipo", "-create", *binaries, "-output", binary)
    else:
        shutil.copy2(binaries[0], binary)

    iconset = cache / "AppIcon.iconset"
    run("xcrun", "swift", ROOT / "src/icon.swift", iconset)
    run("iconutil", "-c", "icns", iconset, "-o", resources / "AppIcon.icns")
    run("codesign", "--force", "--sign", "-", app)
    run("codesign", "--verify", "--deep", "--strict", app)
    archive = output / "桌面文字.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
    print(f"Application: {app}")
    print(f"Archive: {archive}")
    print(f"Architecture: {args.arch}")


if __name__ == "__main__":
    main()
