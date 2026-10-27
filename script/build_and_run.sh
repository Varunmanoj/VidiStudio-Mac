#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MODE="${1:-run}"
if [[ -n "${VIDISTUDIO_CONFIGURATION:-}" ]]; then
  CONFIGURATION="$VIDISTUDIO_CONFIGURATION"
elif [[ "$MODE" == "--debug" ]]; then
  CONFIGURATION="Debug"
else
  CONFIGURATION="Release"
fi
INSTALL_DIR="${VIDISTUDIO_INSTALL_DIR:-/Applications}"
INSTALL_APP="$INSTALL_DIR/VidiStudio.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
mkdir -p build
touch build/.metadata_never_index
pkill -x VidiStudio >/dev/null 2>&1 || true
python3 script/sync_version.py --sync
python3 script/check_menu_parity.py --allow-missing
if [[ ! -f build/engine/vidistudio-engine/.complete ]] || [[ -n "$(find engine -type f ! -path "*/__pycache__/*" -newer build/engine/vidistudio-engine/.complete -print -quit 2>/dev/null)" ]]; then
  ./script/prepare_engine.sh
fi
xcodebuild -project VidiStudio.xcodeproj -scheme VidiStudio -configuration "$CONFIGURATION" -derivedDataPath build/DerivedData.noindex CODE_SIGNING_ALLOWED=NO build > build/xcode-build.log 2>&1 || { tail -60 build/xcode-build.log; exit 1; }
APP="$PWD/build/DerivedData.noindex/Build/Products/$CONFIGURATION/VidiStudio.app"
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
if [[ "$MODE" == "--build-only" ]]; then
  # Packaging needs the signed product, but it must not appear as a second app.
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  echo "$APP"
  exit 0
fi
if [[ ! -d "$INSTALL_DIR" || ! -w "$INSTALL_DIR" ]]; then
  echo "Cannot install into $INSTALL_DIR. Set VIDISTUDIO_INSTALL_DIR to a writable applications folder." >&2
  exit 1
fi
# Replace the previous install so LaunchServices, Spotlight, and the Dock show
# exactly one app. Stage the new signed bundle first so a failed copy never
# destroys the working installation.
STAGING="$INSTALL_DIR/.VidiStudio.app.staging.$$"
rm -rf "$INSTALL_DIR"/.VidiStudio.app.staging.* 2>/dev/null || true
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING"
codesign --verify --deep --strict "$STAGING" >> build/codesign.log 2>&1
rm -rf "$INSTALL_APP"
mv "$STAGING" "$INSTALL_APP"
"$LSREGISTER" -f "$INSTALL_APP" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
# Remove the build product so a second VidiStudio.app cannot be found or launched.
rm -rf "$APP"
echo "Installed $INSTALL_APP"
case "$MODE" in
  --debug) lldb -- "$INSTALL_APP/Contents/MacOS/VidiStudio" ;;
  --verify) open -n "$INSTALL_APP"; sleep 2; pgrep -x VidiStudio ;;
  --logs|--telemetry) open -n "$INSTALL_APP"; /usr/bin/log stream --info --predicate 'process == "VidiStudio"' ;;
  run) open -n "$INSTALL_APP" ;;
  *) echo 'Usage: script/build_and_run.sh [--build-only|--verify|--debug|--logs|--telemetry]'; exit 2 ;;
esac
