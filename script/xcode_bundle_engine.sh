#!/usr/bin/env bash
set -euo pipefail
cd "$SRCROOT"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p build
python3 script/sync_version.py --sync
python3 script/check_menu_parity.py --allow-missing
python3 script/check_desktop_ui_parity.py --allow-missing
python3 -m unittest tests.test_desktop_ui_parity
if [[ ! -f build/engine/vidistudio-engine/.complete ]] || [[ -n "$(find engine -type f ! -path "*/__pycache__/*" -newer build/engine/vidistudio-engine/.complete -print -quit 2>/dev/null)" ]]; then
  ./script/prepare_engine.sh
fi
rm -rf "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Engine"
mkdir -p "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Engine"
ditto build/engine/vidistudio-engine "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Engine"
python3 script/prepare_license_notices.py "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Engine"
python3 script/check_macos_compatibility.py "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Engine"
ditto "$SRCROOT/VidiStudio/Assets/piper-voices.json" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/piper-voices.json"
python3 script/package_browser_extension.py --local-resources "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/BrowserExtension"
python3 script/build_help.py
ditto build/help/VidiStudio.help "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/VidiStudio.help"

if [[ -f "$SRCROOT/Config/youtube-release.json" ]]; then
  python3 - "$SRCROOT/Config/youtube-release.json" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/youtube-config.json" <<'PYCONFIG'
import json
import sys
from pathlib import Path

api_key = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig")).get("apiKey", "")
Path(sys.argv[2]).write_text(json.dumps({"apiKey": api_key}), encoding="utf-8")
PYCONFIG
else
  rm -f "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/youtube-config.json"
fi
