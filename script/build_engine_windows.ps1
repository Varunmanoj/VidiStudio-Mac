$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
py -3 -m venv .venv-windows
if ($LASTEXITCODE -ne 0) { throw 'Python setup failed' }
& .venv-windows\Scripts\python.exe -m pip install -r engine\requirements.txt pyinstaller
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
& .venv-windows\Scripts\python.exe -m PyInstaller --noconfirm --onedir --name vidistudio-engine --distpath dist\windows --workpath build\windows --specpath build --add-data "$PWD/engine/ai-defaults.json;." --collect-all google.genai engine\vidistudio_engine.py
if ($LASTEXITCODE -ne 0) { throw 'Engine packaging failed' }
Write-Host 'Engine built in dist/windows/vidistudio-engine. Supply FFmpeg/FFprobe on PATH or in its media folder with required DLLs and licenses.'
