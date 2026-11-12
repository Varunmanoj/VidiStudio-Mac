"""Exercise production completion policies with success/failure/cancellation fixtures."""
from pathlib import Path
import hashlib
import itertools
import subprocess
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[1]
WIN = ROOT.parent / 'Vidi-Studio-Windows/Vidi Studio Windows'
swift_source = (ROOT/'VidiStudio/ExportCompletionSound.swift').read_text()
cs_source = (WIN/'Services/ExportCompletionSound.cs').read_text()
swift_policy = swift_source[swift_source.index('    static func shouldPlay'):swift_source.index('    func complete')]
cs_policy = cs_source[cs_source.index('    public static bool ShouldPlay'):cs_source.index('    public static void Complete')]
swift = 'import Foundation\nstruct Cue {\n' + swift_policy + '}\n'
cs = ''
commands = ['export-subtitles', 'export-audio', 'export-batch', 'export-final-video', 'export-hls', 'export-youtube-original-audio', 'combine-imported-audio', 'import-video', 'synthesize-tts', 'save-segments']
for command in commands:
    for enabled, succeeded, cancelled, output in itertools.product([False, True], repeat=4):
        expected = enabled and succeeded and not cancelled and output and command in commands[:7]
        args = ', '.join(str(x).lower() for x in [enabled, succeeded, cancelled, output])
        named = ', '.join(f'{k}: {str(v).lower()}' for k,v in zip(['enabled','succeeded','cancelled','hasOutput'],[enabled,succeeded,cancelled,output]))
        swift += f'precondition(Cue.shouldPlay(command: "{command}", {named}) == {str(expected).lower()})\n'
        cs += f'if (Cue.ShouldPlay("{command}", {args}) != {str(expected).lower()}) throw new Exception("Completion policy mismatch");\n'
cs = 'using System;\n' + cs + '\nstatic class Cue {\n' + cs_policy + '}\n'
with tempfile.TemporaryDirectory(prefix='vidistudio-export-sound-') as folder:
    path = Path(folder)
    (path/'main.swift').write_text(swift)
    subprocess.run(['xcrun','swiftc',str(path/'main.swift'),'-o',str(path/'swift-check')],check=True)
    subprocess.run([str(path/'swift-check')],check=True)
    (path/'Program.cs').write_text(cs)
    (path/'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><OutputType>Exe</OutputType></PropertyGroup></Project>')
    subprocess.run(['dotnet','run','--project',str(path/'Check.csproj'),'-v:q'],check=True)
assets = [ROOT/'VidiStudio/Sounds/descend.wav', WIN/'Assets/Sounds/descend.wav']
assert len({hashlib.sha256(p.read_bytes()).hexdigest() for p in assets}) == 1
with wave.open(str(assets[0])) as audio:
    assert audio.getnframes() > 0
    print(f'PASS: both production policies, 160 cases each; identical bundled WAV ({audio.getnframes()/audio.getframerate():.3f}s)')

# Real AVAudioPlayer delegate/lifecycle regression in a disposable resource bundle.
import shutil
with tempfile.TemporaryDirectory(prefix='vidistudio-preview-') as folder:
    bundle = Path(folder)/'SoundPreviewCheck.app/Contents'
    binary = bundle/'MacOS/SoundPreviewCheck'
    binary.parent.mkdir(parents=True)
    (bundle/'Resources').mkdir()
    for asset in (ROOT/'VidiStudio/Sounds').glob('*.wav'):
        shutil.copyfile(asset, bundle/'Resources'/asset.name)
    subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','6',
                    '-target','arm64-apple-macos26.0', str(ROOT/'VidiStudio/SettingsSoundPreview.swift'),
                    str(ROOT/'tests/sound_preview_harness.swift'),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
