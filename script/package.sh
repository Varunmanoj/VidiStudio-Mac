#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --build-only
mkdir -p dist
APP="$PWD/build/DerivedData/Build/Products/Release/VidiStudio.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" dist/VidiStudio-macOS-arm64.zip
STAGE="$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto "$APP" "$STAGE/VidiStudio.app"
ln -s /Applications "$STAGE/Applications"
cp README.md "$STAGE/Read Me.md"
hdiutil create -volname VidiStudio -srcfolder "$STAGE" -ov -format UDZO dist/VidiStudio-macOS-arm64.dmg
printf 'Created local-install ZIP and DMG in %s/dist\n' "$PWD"
