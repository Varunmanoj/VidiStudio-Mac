#!/usr/bin/env python3
"""Stage the shared WebExtension for Safari or build both Chromium store ZIPs."""
import argparse
import json
import re
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "BrowserExtension"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    destinations = parser.add_mutually_exclusive_group()
    destinations.add_argument("--safari-resources", type=Path)
    destinations.add_argument("--local-resources", type=Path)
    destinations.add_argument("--windows-payload", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/browser-extensions")
    args = parser.parse_args()
    files = {name: (SOURCE / name).read_bytes() for name in (
        "background.js", "youtube.js", "open.html", "open.css", "open.js",
        "icons/16.png", "icons/32.png", "icons/48.png", "icons/128.png")}
    manifest = json.loads((SOURCE / "manifest.json").read_text())
    if args.local_resources or args.windows_payload:
        manifest["permissions"].append("alarms")
        manifest["background"] = {"service_worker": "local-worker.js"}
        files["local-worker.js"] = (SOURCE / "local-worker.js").read_bytes()
    files["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    if args.windows_payload:
        output = args.windows_payload
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=output.parent) as directory:
            archive_path = Path(directory) / "payload.zip"
            with ZipFile(archive_path, "w") as archive:
                for name, data in files.items():
                    # Identical resources produce identical embedded bytes on Mac and Windows.
                    archive.writestr(ZipInfo(name), data, compress_type=ZIP_DEFLATED)
            if not output.exists() or output.read_bytes() != archive_path.read_bytes():
                archive_path.replace(output)
        return
    resources = args.local_resources or args.safari_resources
    if resources:
        for name, data in files.items():
            target = resources / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists() or target.read_bytes() != data:
                target.write_bytes(data)
    else:
        args.output.mkdir(parents=True, exist_ok=True)
        names = [f"Describe-with-Vidi-Studio-{browser}.zip" for browser in ("Chrome", "Edge")]
        with tempfile.TemporaryDirectory(dir=args.output) as directory:
            stage = Path(directory)
            for name in names:
                with ZipFile(stage / name, "w", compression=ZIP_DEFLATED) as archive:
                    for resource, data in files.items():
                        archive.writestr(ZipInfo(resource), data, compress_type=ZIP_DEFLATED)
                with ZipFile(stage / name) as archive:
                    if archive.testzip() or json.loads(archive.read("manifest.json")) != manifest:
                        raise ValueError(f"Invalid staged browser package: {name}")
            for name in names:
                destination = args.output / name
                if not destination.exists() or destination.read_bytes() != (stage / name).read_bytes():
                    (stage / name).replace(destination)
                print(args.output / name)
        # Remove only archives named by earlier versions of this packager.
        previous = re.compile(r"(?:Open-in-VidiStudio|Describe-with-Vidi-Studio)-(?:Chrome|Edge)-[0-9]+(?:\.[0-9]+){2,3}\.zip")
        for path in args.output.iterdir():
            if path.is_file() and previous.fullmatch(path.name):
                path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
