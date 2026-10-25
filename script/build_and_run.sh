#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MODE="${1:-run}"
CONFIGURATION="${VIDISTUDIO_CONFIGURATION:-Debug}"
mkdir -p build
touch build/.metadata_never_index
pkill -x VidiStudio >/dev/null 2>&1 || true
python3 script/sync_version.py --sync
python3 script/check_menu_parity.py --allow-missing
if [[ ! -f build/engine/vidistudio-engine/.complete ]] || [[ -n "$(find engine -type f ! -path "*/__pycache__/*" -newer build/engine/vidistudio-engine/.complete -print -quit 2>/dev/null)" ]]; then
  ./script/prepare_engine.sh
fi
xcodebuild -project VidiStudio.xcodeproj -scheme VidiStudio -configuration "$CONFIGURATION" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build > build/xcode-build.log 2>&1 || { tail -60 build/xcode-build.log; exit 1; }
APP="$PWD/build/DerivedData/Build/Products/$CONFIGURATION/VidiStudio.app"
python3 script/verify_help.py "$APP"

SHARE_EXTENSION="$APP/Contents/PlugIns/VidiStudioShareExtension.appex"
FINDER_EXTENSION="$APP/Contents/PlugIns/VidiStudioFinderExtension.appex"
if [[ ! -d "$SHARE_EXTENSION" ]]; then
  echo "Missing embedded VidiStudio Share extension: $SHARE_EXTENSION" >&2
  exit 1
fi
if [[ ! -d "$FINDER_EXTENSION" ]]; then
  echo "Missing embedded VidiStudio Finder extension: $FINDER_EXTENSION" >&2
  exit 1
fi
# TCC ties Documents/Desktop access to the app's signing identity. Ad hoc signing
# changes that identity whenever the executable changes, so permissions are lost
# on each rebuild. Use the same Apple Development identity as the Xcode target.
SIGNING_IDENTITY="${VIDISTUDIO_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  mapfile_output="$(security find-identity -p codesigning -v | sed -nE 's/^[[:space:]]*[0-9]+\) ([[:xdigit:]]+) "Apple Development:.*"$/\1/p')"
  if [[ "$mapfile_output" == *$'\n'* || -z "$mapfile_output" ]]; then
    echo 'Expected exactly one Apple Development signing identity. Set VIDISTUDIO_SIGNING_IDENTITY to its certificate SHA-1.' >&2
    exit 1
  fi
  SIGNING_IDENTITY="$mapfile_output"
fi
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP" > build/codesign.log 2>&1
codesign --force --sign "$SIGNING_IDENTITY" --entitlements Config/VidiStudioShareExtension.entitlements "$SHARE_EXTENSION" >> build/codesign.log 2>&1
codesign --force --sign "$SIGNING_IDENTITY" --entitlements Config/VidiStudioFinderExtension.entitlements "$FINDER_EXTENSION" >> build/codesign.log 2>&1
codesign --force --sign "$SIGNING_IDENTITY" "$APP" >> build/codesign.log 2>&1
codesign --verify --deep --strict "$APP" >> build/codesign.log 2>&1
case "$MODE" in
  --build-only) echo "$APP" ;;
  --debug) lldb -- "$APP/Contents/MacOS/VidiStudio" ;;
  --verify) open -n "$APP"; sleep 2; pgrep -x VidiStudio ;;
  --logs|--telemetry) open -n "$APP"; /usr/bin/log stream --info --predicate 'process == "VidiStudio"' ;;
  run) open -n "$APP" ;;
  *) echo 'Usage: script/build_and_run.sh [--build-only|--verify|--debug|--logs|--telemetry]'; exit 2 ;;
esac
