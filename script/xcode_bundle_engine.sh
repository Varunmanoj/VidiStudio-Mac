#!/usr/bin/env bash
set -euo pipefail
cd "$SRCROOT"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p build
if [[ ! -f build/engine/vidistudio-engine/.complete ]] || [[ -n "$(find engine -type f ! -path "*/__pycache__/*" -newer build/engine/vidistudio-engine/.complete -print -quit 2>/dev/null)" ]]; then
  ./script/prepare_engine.sh
fi
rm -rf "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Engine"
mkdir -p "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Engine"
ditto build/engine/vidistudio-engine "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Engine"
python3 script/build_help.py
ditto build/help/VidiStudio.help "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/VidiStudio.help"
