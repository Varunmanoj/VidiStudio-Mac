#!/usr/bin/env python3
"""Run shared browser/desktop URL fixtures and the native macOS Share resolver."""
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WINDOWS = ROOT.parent / "Vidi-Studio-Windows"
FIXTURES = ROOT / "tests/browser_share_urls.json"


def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)


if __name__ == "__main__":
    run("node", "--test", "tests/browser_share.test.cjs")
    with tempfile.TemporaryDirectory() as tmp:
        shared = "Shared/VidiStudioShareLink.swift"
        for name, sources, args in [
            ("url", [shared, "tests/share_link_harness.swift"], [FIXTURES]),
            ("provider", [shared, "VidiStudioShareExtension/ShareViewController.swift", "tests/share_item_harness.swift"], []),
        ]:
            binary = Path(tmp) / name
            run("xcrun", "swiftc", "-module-cache-path", ROOT / "build/browser-share-modules", *sources, "-o", binary)
            run(binary, *args)
    run("dotnet", "run", "--project", WINDOWS / "tests/browser_share", "--", FIXTURES)
