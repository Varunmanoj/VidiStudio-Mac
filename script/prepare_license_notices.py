"""Put build-specific license details beside the bundled engine."""

import json
import shutil
import subprocess
import sys
from pathlib import Path


engine = Path(sys.argv[1])
licenses = engine / "licenses"
media = engine / "media"
licenses.mkdir(exist_ok=True)


def ffmpeg_output(name, option):
    return subprocess.check_output([str(media / name), option], text=True, stderr=subprocess.STDOUT)


version_output = ffmpeg_output("ffmpeg", "-version")
probe_version = ffmpeg_output("ffprobe", "-version")
license_output = ffmpeg_output("ffmpeg", "-L")
probe_license = ffmpeg_output("ffprobe", "-L")
version = version_output.splitlines()[0].split(" Copyright", 1)[0].replace("ffmpeg version ", "")
configuration = next(line.strip().removeprefix("configuration: ") for line in version_output.splitlines() if "configuration:" in line)
if "--enable-nonfree" in configuration:
    raise SystemExit("Bundled FFmpeg uses --enable-nonfree and cannot be redistributed")
if "GNU General Public License" not in license_output or "version 3" not in license_output:
    raise SystemExit("Expected FFmpeg GPL v3 license was not reported by the bundled executable")
if "GNU General Public License" not in probe_license or "version 3" not in probe_license:
    raise SystemExit("Expected FFprobe GPL v3 license was not reported by the bundled executable")
if probe_version.splitlines()[0].split(" Copyright", 1)[0].replace("ffprobe version ", "") != version:
    raise SystemExit("Bundled FFmpeg and FFprobe versions do not match")

ffmpeg_directories = sorted(licenses.glob("ffmpeg-full-*"))
if len(ffmpeg_directories) != 1:
    raise SystemExit("Expected exactly one bundled FFmpeg license directory")
gpl = ffmpeg_directories[0] / "COPYING.GPLv3"
if not gpl.is_file():
    raise SystemExit("Bundled FFmpeg GPL v3 text is missing")
(licenses / "FFmpeg-COPYING.GPLv3").unlink(missing_ok=True)
shutil.copy2(gpl, licenses / "FFmpeg-GPLv3.txt")

font_license = Path("VidiStudio/Fonts/MaterialSymbols-LICENSE.txt")
shutil.copy2(font_license, licenses / font_license.name)

# PyInstaller puts some distribution metadata in _internal and some in its
# archive. Copy the available package notices from the locked build environment.
for site_packages in Path(".venv/lib").glob("python*/site-packages"):
    for distribution in site_packages.glob("*.dist-info"):
        notice_files = [item for item in distribution.rglob("*")
                        if item.is_file() and item.name.upper().startswith(("LICENSE", "COPYING", "NOTICE"))]
        if not notice_files:
            continue
        destination = licenses / "python" / distribution.name
        for item in notice_files:
            target = destination / item.relative_to(distribution)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, target)

(licenses / "media-license-summary.json").write_text(
    json.dumps({"version": version, "license": "GNU GPL version 3 or later"}, indent=2) + "\n"
)

lines = [
    "VidiStudio third-party license index",
    "",
    f"Bundled FFmpeg and FFprobe: {version}",
    "License reported by both executables: GNU GPL version 3 or later.",
    "Full license text: FFmpeg-GPLv3.txt",
    "FFmpeg licensing information: https://ffmpeg.org/legal.html",
    "",
    "FFmpeg configuration:",
    configuration,
    "",
    "The directories below contain the license, copyright, and notice files copied",
    "from the installed packages used to build this app. Open the folder in Finder",
    "to read the individual files.",
    "",
]
for directory in sorted(item for item in licenses.iterdir() if item.is_dir()):
    notice_files = sorted(item.relative_to(directory).as_posix() for item in directory.rglob("*") if item.is_file())
    lines.append(f"{directory.name}: {', '.join(notice_files) if notice_files else 'No notice file found in installed formula'}")
lines.extend(["", "Material Symbols font: MaterialSymbols-LICENSE.txt", ""])
(licenses / "THIRD-PARTY-LICENSES.txt").write_text("\n".join(lines))
