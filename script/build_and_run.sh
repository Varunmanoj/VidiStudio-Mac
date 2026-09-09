#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MODE="${1:-run}"
CONFIGURATION="${VIDISTUDIO_CONFIGURATION:-Debug}"
mkdir -p build
pkill -x VidiStudio >/dev/null 2>&1 || true
if [[ ! -f build/engine/vidistudio-engine/.complete ]] || [[ -n "$(find engine -type f ! -path "*/__pycache__/*" -newer build/engine/vidistudio-engine/.complete -print -quit 2>/dev/null)" ]]; then
  ./script/prepare_engine.sh
fi
xcodebuild -project VidiStudio.xcodeproj -scheme VidiStudio -configuration "$CONFIGURATION" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build > build/xcode-build.log 2>&1 || { tail -60 build/xcode-build.log; exit 1; }
APP="$PWD/build/DerivedData/Build/Products/$CONFIGURATION/VidiStudio.app"
python3 script/verify_help.py "$APP"

codesign --force --deep --sign - "$APP" > build/codesign.log 2>&1
case "$MODE" in
  --build-only) echo "$APP" ;;
  --debug) lldb -- "$APP/Contents/MacOS/VidiStudio" ;;
  --verify) open -n "$APP"; sleep 2; pgrep -x VidiStudio ;;
  --logs|--telemetry) open -n "$APP"; /usr/bin/log stream --info --predicate 'process == "VidiStudio"' ;;
  run) open -n "$APP" ;;
  *) echo 'Usage: script/build_and_run.sh [--build-only|--verify|--debug|--logs|--telemetry]'; exit 2 ;;
esac
