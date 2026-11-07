"""Dialogue-free generation contracts and exact-default upgrades across both desktops."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT if (ROOT / 'VidiStudio').exists() else ROOT.parent / 'VidiStudio Mac'
WINDOWS = ROOT if (ROOT / 'Vidi Studio Windows').exists() else ROOT.parent / 'Vidi-Studio-Windows'
sys.path.insert(0, str(ROOT / 'engine'))
import vidistudio_engine as e


def defaults():
    return json.loads((ROOT / 'engine/ai-defaults.json').read_text())


def legacy_settings():
    cfg = defaults()
    return {'models': {'summary': 'custom-model'}, 'prompts': {
        stage: {field: values[0] for field, values in fields.items()}
        for stage, fields in cfg['legacyPromptDefaults'].items()}}


class DialogueFreePrompts(unittest.TestCase):
    def test_requests_use_visual_exception_for_both_sources_and_stages(self):
        cfg = defaults()
        for source in ('upload', 'youtube'):
            for has_audio in (False, True):
                for stage, key, response in (
                    ('generate-summary', 'summary', '# Visual story\n\nA bird follows a fox.'),
                    ('generate-ad-cues', 'audio_descriptions', '{"audioDescriptions":[{"start":2,"end":6,"text":"A bird follows a fox."}]}'),
                ):
                    with self.subTest(source=source, audio=has_audio, stage=stage), tempfile.TemporaryDirectory() as folder:
                        project = dict(sourceType=source, source='video.mp4', youtubeURL='https://youtu.be/abcdefghijk',
                            duration=20, hasAudio=has_audio, transcriptGenerated=True, transcript=[], summary='Visual story', cues=[])
                        e.validate_analysis_prerequisites(stage, Path(folder), project)
                        client = Mock()
                        client.interactions.create.return_value = {'output_text': response}
                        with patch.object(e, 'config', return_value=cfg), \
                             patch.object(e, 'client_and_model', return_value=(client, 'video-model')), \
                             patch.object(e, 'reusable_video', return_value=SimpleNamespace(uri='files/video', mime_type='video/mp4')), \
                             patch.object(e, 'ensure_supported_local_video'), patch.object(e, 'emit'):
                            e._ai_video_once(Path(folder), project, stage)
                        request = client.interactions.create.call_args.kwargs
                        prompt = request['input'][1]['text']
                        system = request['system_instruction']
                        self.assertEqual(request['input'][0]['uri'], project['youtubeURL'] if source == 'youtube' else 'files/video')
                        self.assertIn(cfg['prompts'][key]['system_instruction'], system)
                        for phrase in ('dialogue-free', 'silent videos', 'music videos', 'sung lyrics'):
                            self.assertIn(phrase, system.lower())
                        self.assertNotIn('Use this transcript as required context', prompt)
                        self.assertNotIn('{transcript_json}', prompt)
                        self.assertNotIn('silent gaps only', prompt)
                        self.assertIn('[]', prompt)
                        self.assertIn('Detect the primary language from the video itself', system)
                        self.assertEqual(project['transcript'], [])
                        if stage == 'generate-summary':
                            self.assertEqual(project['summary'], response)
                        else:
                            self.assertIn('"dialogueFreeRanges": [{"start": 0.0, "end": 20.0}]', prompt)
                            self.assertEqual(project['cues'][0]['text'], 'A bird follows a fox.')
                        client.close.assert_called_once()

    def test_music_exception_keeps_transcript_and_overlap_validation(self):
        project = dict(duration=20, transcript=[dict(start=4, end=9, text='Sung words')], summary='Performance')
        context = e.parity.description_context(project)
        self.assertIn('"dialogueFreeRanges": [{"start": 0.0, "end": 4.0}, {"start": 9.0, "end": 20.0}]', context)
        self.assertIn('Do not narrate over speech or sung lyrics', context)
        with self.assertRaises(ValueError):
            e.validate_cues([dict(id='ad', start=3, end=5, text='A performer dances.')], 20, project['transcript'])

    def test_config_upgrades_only_exact_former_defaults_per_field(self):
        cfg = defaults()
        cases = [legacy_settings(), {'prompts': {}}, {'prompts': {'summary': {'system_instruction': 'Custom system'}}}]
        mixed = legacy_settings()
        mixed['prompts']['summary']['user_prompt'] = 'Custom summary with {transcript_json}'
        mixed['prompts']['audio_descriptions']['system_instruction'] = ''
        cases.append(mixed)
        for saved in cases:
            with self.subTest(saved=saved), tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'config.json'
                raw = json.dumps(saved)
                path.write_text(raw)
                with patch.dict(os.environ, {'VIDISTUDIO_CONFIG': str(path)}):
                    resolved = e.config()
                for stage in ('summary', 'audio_descriptions'):
                    for field, current in cfg['prompts'][stage].items():
                        original = saved.get('prompts', {}).get(stage, {}).get(field, current)
                        expected = current if original in cfg['legacyPromptDefaults'][stage][field] else original
                        self.assertEqual(resolved['prompts'][stage][field], expected)
                self.assertEqual(path.read_text(), raw)
                self.assertEqual(resolved['models']['summary'], saved.get('models', {}).get('summary', cfg['models']['summary']))


class NativePromptMigration(unittest.TestCase):
    def fixtures(self, folder):
        cfg = defaults()
        saved = legacy_settings()
        saved['prompts']['summary']['user_prompt'] = 'Custom summary'
        saved['prompts']['audio_descriptions']['system_instruction'] = ''
        saved['prompts']['transcript'] = {'user_prompt': 'Custom transcript'}
        expected = copy.deepcopy(saved)
        for stage, fields in cfg['legacyPromptDefaults'].items():
            for field, previous in fields.items():
                if expected['prompts'][stage][field] in previous:
                    expected['prompts'][stage][field] = cfg['prompts'][stage][field]
        for name, data in [('defaults', cfg), ('saved', saved)]:
            (folder / (name + '.json')).write_text(json.dumps(data))
        return expected

    @unittest.skipUnless(shutil.which('swift'), 'Swift runtime unavailable')
    def test_mac_production_migration_preserves_custom_fields_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            expected = self.fixtures(folder)
            harness = (MAC / 'VidiStudio/PromptDefaults.swift').read_text() + '''
let cfg = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
let first = PromptDefaults.upgrading(saved, defaults: cfg)
let second = PromptDefaults.upgrading(first, defaults: cfg)
print(String(data: try JSONSerialization.data(withJSONObject: second, options: [.sortedKeys]), encoding: .utf8)!)
'''
            (folder / 'main.swift').write_text(harness)
            result = subprocess.run(['swift', str(folder / 'main.swift'), str(folder / 'defaults.json'), str(folder / 'saved.json')], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), expected)

    @unittest.skipUnless(shutil.which('dotnet'), '.NET SDK unavailable')
    def test_windows_production_migration_preserves_custom_fields_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            expected = self.fixtures(folder)
            shutil.copy(WINDOWS / 'Vidi Studio Windows/Services/PromptDefaults.cs', folder)
            (folder / 'Program.cs').write_text('''using System; using System.IO; using System.Text.Json.Nodes;
using Vidi_Studio_Windows.Services;
var cfg = JsonNode.Parse(File.ReadAllText(args[0]))!.AsObject();
var saved = JsonNode.Parse(File.ReadAllText(args[1]))!.AsObject();
PromptDefaults.Upgrade(saved, cfg); PromptDefaults.Upgrade(saved, cfg);
Console.WriteLine(saved.ToJsonString());
''')
            version = subprocess.check_output(['dotnet', '--version'], text=True).split('.')[0]
            (folder / 'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net'+version+'.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup></Project>')
            result = subprocess.run(['dotnet', 'run', '--project', str(folder / 'Check.csproj'), '--', str(folder / 'defaults.json'), str(folder / 'saved.json')], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(result.stdout[result.stdout.index('{'):]), expected)


if __name__ == '__main__':
    unittest.main()
