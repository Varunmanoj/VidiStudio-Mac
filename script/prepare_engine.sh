#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x .venv/bin/python ]]; then
  python3 -m venv .venv
fi
.venv/bin/pip install --disable-pip-version-check -r engine/requirements-build.lock > build/engine-dependencies.log 2>&1
PYINSTALLER_CONFIG_DIR="$PWD/build/pyinstaller-cache" .venv/bin/python -m PyInstaller --noconfirm --clean --onedir --name vidistudio-engine --distpath build/engine --workpath build/pyinstaller --specpath build --add-data "$PWD/engine/ai-defaults.json:." --collect-all google.genai --collect-all yt_dlp --collect-all yt_dlp_ejs --collect-all piper --collect-all onnxruntime engine/vidistudio_engine.py > build/engine-build.log 2>&1
.venv/bin/python script/bundle_media.py build/engine/vidistudio-engine/media

touch build/engine/vidistudio-engine/.complete
