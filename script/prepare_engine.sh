#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x .venv/bin/python ]]; then
  python3 -m venv .venv
fi
.venv/bin/pip install --disable-pip-version-check -r engine/requirements-build.lock > build/engine-dependencies.log 2>&1
vertex_data=()
if [[ -f Config/vertex-desktop.json ]]; then
  vertex_data+=(--add-data "$PWD/Config/vertex-desktop.json:.")
fi
PYINSTALLER_CONFIG_DIR="$PWD/build/pyinstaller-cache" .venv/bin/python -m PyInstaller --noconfirm --clean --onedir --name vidistudio-engine --distpath build/engine --workpath build/pyinstaller --specpath build --add-data "$PWD/engine/ai-defaults.json:." --add-data "$PWD/engine/sarvam-voices.json:." ${vertex_data[@]+"${vertex_data[@]}"} --collect-all keyring --collect-all google_crc32c --collect-all google.genai --collect-submodules sarvamai --copy-metadata sarvamai --collect-all yt_dlp --collect-all yt_dlp_ejs --collect-all piper --collect-all onnxruntime engine/vidistudio_engine.py > build/engine-build.log 2>&1
.venv/bin/python script/bundle_media.py build/engine/vidistudio-engine/media

touch build/engine/vidistudio-engine/.complete
