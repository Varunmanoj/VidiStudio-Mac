#!/usr/bin/env python3
"""Synchronize and manage application versions across macOS (VidiStudio Mac)
and Windows (Vidi-Studio-Windows) desktop applications.

Usage:
  python3 script/sync_version.py --status
  python3 script/sync_version.py --check
  python3 script/sync_version.py --sync
  python3 script/sync_version.py --bump [patch|minor|major]
  python3 script/sync_version.py --set 1.0.62 [--build 63]
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Optional, Tuple


def find_roots(
    start: Optional[Path] = None,
    mac_override: Optional[Path] = None,
    windows_override: Optional[Path] = None,
) -> Tuple[Optional[Path], Optional[Path]]:
    """Discover the Mac and Windows repository roots."""
    if mac_override and mac_override.is_dir():
        mac_root = mac_override.resolve()
    else:
        mac_root = None

    if windows_override and windows_override.is_dir():
        windows_root = windows_override.resolve()
    else:
        windows_root = None

    if mac_root and windows_root:
        return mac_root, windows_root

    start_dir = (start or Path.cwd()).resolve()
    script_dir = Path(__file__).resolve().parent

    candidates = [
        start_dir,
        start_dir.parent,
        script_dir,
        script_dir.parent,
        script_dir.parent.parent if len(script_dir.parents) > 1 else script_dir,
    ]
    if len(start_dir.parents) > 1:
        candidates.append(start_dir.parent.parent)

    # Search for macOS root (contains VidiStudio.xcodeproj/project.pbxproj)
    if not mac_root:
        for base in candidates:
            for check in [base, base / "VidiStudio Mac", base / "VidiStudio"]:
                if (check / "VidiStudio.xcodeproj" / "project.pbxproj").is_file():
                    mac_root = check.resolve()
                    break
            if mac_root:
                break

    # Search for Windows root (contains Vidi Studio Windows/Vidi Studio Windows.csproj)
    if not windows_root:
        for base in candidates:
            for check in [base, base / "Vidi-Studio-Windows", base / "VidiStudio Windows"]:
                if (check / "Vidi Studio Windows" / "Vidi Studio Windows.csproj").is_file():
                    windows_root = check.resolve()
                    break
            if windows_root:
                break

    return mac_root, windows_root


def get_mac_version(mac_root: Path) -> Tuple[Optional[str], Optional[str]]:
    """Return (marketing_version, build_number) for macOS."""
    pbxproj = mac_root / "VidiStudio.xcodeproj" / "project.pbxproj"
    if not pbxproj.is_file():
        return None, None
    text = pbxproj.read_text(encoding="utf-8")
    versions = set(re.findall(r"MARKETING_VERSION\s*=\s*([^;]+);", text))
    builds = set(re.findall(r"CURRENT_PROJECT_VERSION\s*=\s*([^;]+);", text))
    version = next(iter(versions)) if versions else None
    build = next(iter(builds)) if builds else None
    return version, build


def get_windows_version(windows_root: Path) -> Tuple[Optional[str], Optional[str]]:
    """Return (csproj_version, package_appx_version) for Windows."""
    csproj = windows_root / "Vidi Studio Windows" / "Vidi Studio Windows.csproj"
    manifest = windows_root / "Vidi Studio Windows" / "Package.appxmanifest"

    csproj_ver = None
    appx_ver = None

    if csproj.is_file():
        text = csproj.read_text(encoding="utf-8")
        m = re.search(r"<Version>([^<]+)</Version>", text)
        if m:
            csproj_ver = m.group(1).strip()

    if manifest.is_file():
        text = manifest.read_text(encoding="utf-8")
        m = re.search(r'<Identity\b[\s\S]*?\bVersion="([^"]+)"', text)
        if m:
            appx_ver = m.group(1).strip()

    return csproj_ver, appx_ver


def parse_semver(v_str: str) -> Tuple[int, ...]:
    """Parse a version string into a tuple of integers."""
    nums = re.findall(r"\d+", str(v_str).strip())
    return tuple(int(n) for n in nums)


def normalize_triplet(v_str: str) -> Tuple[int, int, int]:
    """Extract (major, minor, patch) from any version string."""
    nums = parse_semver(v_str)
    padded = list(nums) + [0] * (3 - len(nums))
    return (padded[0], padded[1], padded[2])


def format_triplet(triplet: Tuple[int, int, int]) -> str:
    return f"{triplet[0]}.{triplet[1]}.{triplet[2]}"


def bump_triplet(triplet: Tuple[int, int, int], part: str = "patch") -> Tuple[int, int, int]:
    maj, min_, patch = triplet
    if part == "major":
        return (maj + 1, 0, 0)
    elif part == "minor":
        return (maj, min_ + 1, 0)
    else:  # patch
        return (maj, min_, patch + 1)


def write_mac_version(mac_root: Path, new_version: str, new_build: str) -> None:
    """Update MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.pbxproj."""
    pbxproj = mac_root / "VidiStudio.xcodeproj" / "project.pbxproj"
    content = pbxproj.read_text(encoding="utf-8")
    updated = re.sub(r"(MARKETING_VERSION\s*=\s*)[^;]+;", rf"\g<1>{new_version};", content)
    updated = re.sub(r"(CURRENT_PROJECT_VERSION\s*=\s*)[^;]+;", rf"\g<1>{new_build};", updated)
    if updated != content:
        pbxproj.write_text(updated, encoding="utf-8")


def write_windows_version(windows_root: Path, new_version: str) -> None:
    """Update <Version> in .csproj and Version in Package.appxmanifest."""
    csproj = windows_root / "Vidi Studio Windows" / "Vidi Studio Windows.csproj"
    manifest = windows_root / "Vidi Studio Windows" / "Package.appxmanifest"

    appx_ver = f"{new_version}.0" if len(new_version.split(".")) == 3 else new_version

    if csproj.is_file():
        c_text = csproj.read_text(encoding="utf-8")
        c_updated = re.sub(r"(<Version>)[^<]+(</Version>)", rf"\g<1>{new_version}\g<2>", c_text)
        if c_updated != c_text:
            csproj.write_text(c_updated, encoding="utf-8")

    if manifest.is_file():
        m_text = manifest.read_text(encoding="utf-8")
        m_updated = re.sub(r'(<Identity\b[\s\S]*?\bVersion=")[^"]+(")', rf"\g<1>{appx_ver}\g<2>", m_text)
        if m_updated != m_text:
            manifest.write_text(m_updated, encoding="utf-8")


def derive_build_number(triplet: Tuple[int, int, int], existing_build: Optional[str] = None) -> str:
    """Derive an integer Xcode build number."""
    if existing_build and existing_build.isdigit():
        return existing_build
    # Build number is patch + 1 by default convention in this repo (e.g. 1.0.62 -> 63)
    return str(triplet[2] + 1)


def sync_versions(mac_root: Optional[Path], windows_root: Optional[Path]) -> bool:
    """Synchronize versions to the highest found version across platforms.
    Returns True if already in sync or successfully synced.
    """
    if not mac_root and not windows_root:
        sys.stderr.write("Error: Neither macOS nor Windows repository was found.\n")
        return False

    mac_ver, mac_build = get_mac_version(mac_root) if mac_root else (None, None)
    win_csproj, win_appx = get_windows_version(windows_root) if windows_root else (None, None)

    if mac_root and not windows_root:
        print(f"macOS repository only: version is {mac_ver} (build {mac_build}).")
        return True

    if windows_root and not mac_root:
        print(f"Windows repository only: version is {win_csproj} (Package: {win_appx}).")
        return True

    mac_trip = normalize_triplet(mac_ver) if mac_ver else (0, 0, 0)
    win_trip = normalize_triplet(win_csproj) if win_csproj else (0, 0, 0)

    if mac_trip == win_trip and (win_appx == f"{format_triplet(win_trip)}.0"):
        print(f"macOS and Windows versions are in sync: {format_triplet(mac_trip)} (Mac build {mac_build}, Win package {win_appx}).")
        return True

    # Drift detected: pick the higher version
    if mac_trip >= win_trip:
        target_triplet = mac_trip
        target_ver = format_triplet(mac_trip)
        target_build = mac_build or derive_build_number(target_triplet)
    else:
        target_triplet = win_trip
        target_ver = format_triplet(win_trip)
        target_build = derive_build_number(target_triplet, mac_build)

    print(f"Version drift detected: macOS={mac_ver} (build {mac_build}), Windows={win_csproj} (Package {win_appx})")
    print(f"Synchronizing both platforms to target version {target_ver} (build {target_build})...")

    if mac_root:
        write_mac_version(mac_root, target_ver, target_build)
    if windows_root:
        write_windows_version(windows_root, target_ver)

    print(f"Successfully synchronized macOS and Windows to version {target_ver}.")
    return True


def bump_version(
    mac_root: Optional[Path],
    windows_root: Optional[Path],
    part: str = "patch",
    explicit_build: Optional[str] = None,
) -> bool:
    """Bump the version across both platforms."""
    mac_ver, mac_build = get_mac_version(mac_root) if mac_root else (None, None)
    win_csproj, _ = get_windows_version(windows_root) if windows_root else (None, None)

    mac_trip = normalize_triplet(mac_ver) if mac_ver else (0, 0, 0)
    win_trip = normalize_triplet(win_csproj) if win_csproj else (0, 0, 0)

    base_trip = max(mac_trip, win_trip)
    new_trip = bump_triplet(base_trip, part)
    new_ver = format_triplet(new_trip)

    if explicit_build:
        new_build = explicit_build
    elif mac_build and mac_build.isdigit():
        new_build = str(int(mac_build) + 1)
    else:
        new_build = derive_build_number(new_trip)

    print(f"Bumping {part} version: {format_triplet(base_trip)} -> {new_ver} (build {new_build}) across platforms.")

    if mac_root:
        write_mac_version(mac_root, new_ver, new_build)
        print(f"  Updated macOS: MARKETING_VERSION={new_ver}, CURRENT_PROJECT_VERSION={new_build}")
    if windows_root:
        write_windows_version(windows_root, new_ver)
        print(f"  Updated Windows: Version={new_ver}, Package Version={new_ver}.0")

    return True


def set_version(
    mac_root: Optional[Path],
    windows_root: Optional[Path],
    target_version: str,
    explicit_build: Optional[str] = None,
) -> bool:
    """Set both platforms to an explicit version string."""
    trip = normalize_triplet(target_version)
    new_ver = format_triplet(trip)
    new_build = explicit_build or derive_build_number(trip)

    print(f"Setting app version to {new_ver} (build {new_build}) across platforms.")
    if mac_root:
        write_mac_version(mac_root, new_ver, new_build)
        print(f"  Updated macOS: MARKETING_VERSION={new_ver}, CURRENT_PROJECT_VERSION={new_build}")
    if windows_root:
        write_windows_version(windows_root, new_ver)
        print(f"  Updated Windows: Version={new_ver}, Package Version={new_ver}.0")
    return True


def check_status(mac_root: Optional[Path], windows_root: Optional[Path], strict: bool = False) -> int:
    """Check and display version status."""
    mac_ver, mac_build = get_mac_version(mac_root) if mac_root else (None, None)
    win_csproj, win_appx = get_windows_version(windows_root) if windows_root else (None, None)

    print("App Version Status:")
    if mac_root:
        print(f"  macOS (project.pbxproj):     {mac_ver} (build {mac_build}) at {mac_root}")
    else:
        print("  macOS:                        Not found")

    if windows_root:
        print(f"  Windows (.csproj):           {win_csproj} at {windows_root}")
        print(f"  Windows (Package.manifest):  {win_appx}")
    else:
        print("  Windows:                      Not found")

    if not mac_root or not windows_root:
        if strict:
            print("ERROR: Both platforms must be present for strict verification.")
            return 1
        return 0

    mac_trip = normalize_triplet(mac_ver) if mac_ver else (0, 0, 0)
    win_trip = normalize_triplet(win_csproj) if win_csproj else (0, 0, 0)

    if mac_trip == win_trip and win_appx == f"{format_triplet(win_trip)}.0":
        print(f"  Result: In sync ({format_triplet(mac_trip)}).")
        return 0
    else:
        print(f"  Result: DRIFT DETECTED between macOS ({mac_ver}) and Windows ({win_csproj}).")
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Synchronize app version across macOS and Windows.")
    parser.add_argument("--mac-root", type=Path, help="Explicit path to VidiStudio Mac repository root")
    parser.add_argument("--windows-root", type=Path, help="Explicit path to Vidi-Studio-Windows repository root")
    parser.add_argument("--status", action="store_true", help="Print current version status (default)")
    parser.add_argument("--check", action="store_true", help="Check if versions are strictly in sync (exits 1 if drift)")
    parser.add_argument("--sync", action="store_true", help="Synchronize versions to the newer version across platforms")
    parser.add_argument("--bump", choices=["patch", "minor", "major"], nargs="?", const="patch", help="Bump version component (default: patch)")
    parser.add_argument("--set", type=str, help="Explicitly set version (e.g. 1.0.62)")
    parser.add_argument("--build", type=str, help="Explicit build number (used with --set or --bump)")
    parser.add_argument("--strict", action="store_true", help="Fail --check if either platform is missing")

    args = parser.parse_args()
    mac_root, windows_root = find_roots(mac_override=args.mac_root, windows_override=args.windows_root)

    if args.set:
        return 0 if set_version(mac_root, windows_root, args.set, args.build) else 1
    elif args.bump:
        return 0 if bump_version(mac_root, windows_root, args.bump, args.build) else 1
    elif args.sync:
        return 0 if sync_versions(mac_root, windows_root) else 1
    elif args.check:
        return check_status(mac_root, windows_root, strict=args.strict)
    else:
        # Default action: status
        return check_status(mac_root, windows_root, strict=False)


if __name__ == "__main__":
    sys.exit(main())
