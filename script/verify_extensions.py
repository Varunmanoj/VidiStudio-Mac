#!/usr/bin/env python3
"""Validate the app and both extensions before replacement and after registration."""

import argparse
import plistlib
import re
import subprocess
from pathlib import Path


EXTENSIONS = {
    "VidiStudioShareExtension": ("ShareExtension", "com.apple.share-services"),
    "VidiStudioFinderExtension": ("FinderExtension", "com.apple.FinderSync"),
}
APP_ID = "Varunmanojkumar.VidiStudio"


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f"{' '.join(args)}: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout + result.stderr


def info(bundle):
    return plistlib.loads((bundle / "Contents/Info.plist").read_bytes())


def version(metadata):
    return metadata["CFBundleShortVersionString"], metadata["CFBundleVersion"]


def signing(bundle):
    details = run("codesign", "--display", "--verbose=4", "--requirements", "-", str(bundle))
    team = re.search(r"^TeamIdentifier=(\S+)$", details, re.M)
    requirement = re.search(r"^designated => (.+)$", details, re.M)
    if not team or team[1] == "not" or "Signature=adhoc" in details or not requirement:
        raise ValueError(f"{bundle.name}: requires a stable certificate signature, not ad hoc signing")
    return team[1], requirement[1]


def validate_metadata(app):
    metadata = info(app)
    if metadata["CFBundleIdentifier"] != APP_ID:
        raise ValueError("Unexpected app bundle identifier")
    bundles = [app]
    for name, (suffix, point) in EXTENSIONS.items():
        bundle = app / "Contents/PlugIns" / f"{name}.appex"
        extension = info(bundle)
        if extension["CFBundleIdentifier"] != f"{APP_ID}.{suffix}":
            raise ValueError(f"{name}: unexpected bundle identifier")
        if version(extension) != version(metadata):
            raise ValueError(f"{name}: version/build {version(extension)} differs from app {version(metadata)}")
        if extension["NSExtension"]["NSExtensionPointIdentifier"] != point:
            raise ValueError(f"{name}: unexpected extension point")
        bundles.append(bundle)
    return bundles


def verify(app, previous=None, registered=False):
    bundles = validate_metadata(app)
    run("codesign", "--verify", "--deep", "--strict", str(app))
    team, _ = signing(app)
    project = Path(__file__).resolve().parents[1] / "VidiStudio.xcodeproj/project.pbxproj"
    expected_teams = set(re.findall(r"DEVELOPMENT_TEAM\s*=\s*([^;]+);", project.read_text()))
    if expected_teams != {team}:
        raise ValueError(f"Signing team {team} differs from project teams {expected_teams}")
    for bundle in bundles:
        bundle_team, _ = signing(bundle)
        if bundle_team != team:
            raise ValueError(f"{bundle.name}: signing team differs from app")
        if bundle != app:
            entitlements = subprocess.run(
                ["codesign", "--display", "--entitlements", "-", "--xml", str(bundle)],
                capture_output=True, check=True,
            )
            actual = plistlib.loads(entitlements.stdout)
            expected = plistlib.loads((project.parent.parent / "Config" / f"{bundle.stem}.entitlements").read_bytes())
            if actual != expected:
                raise ValueError(f"{bundle.name}: signed entitlements differ from canonical configuration")
        if previous and previous.exists():
            old = previous / bundle.relative_to(app)
            if not old.exists():
                raise ValueError(f"Previous installation is missing {old.name}; inspect before replacing")
            _, old_requirement = signing(old)
            # Evaluate the old requirement against the new code, rather than compare
            # changing executable hashes. This is the identity macOS recognizes.
            run("codesign", "--verify", "--strict", "-R", "=" + old_requirement, str(bundle))
        if registered and bundle != app:
            identifier = info(bundle)["CFBundleIdentifier"]
            listing = run("pluginkit", "-m", "-A", "-D", "-vv", "-i", identifier)
            paths = re.findall(r"^\s*Path = (.+)$", listing, re.M)
            if paths != [str(bundle)] or not re.search(
                re.escape(identifier) + r"\(" + re.escape(version(info(app))[0]) + r"\)", listing
            ):
                raise ValueError(f"{identifier}: expected one registered current extension at {bundle}; got {listing}")
        print(f"Verified {bundle.name}: {version(info(bundle))}, team {bundle_team}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--registered", action="store_true")
    args = parser.parse_args()
    try:
        verify(args.app.resolve(), args.previous, args.registered)
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Extension verification failed: {error}\n")


if __name__ == "__main__":
    main()
