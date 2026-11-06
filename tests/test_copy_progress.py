'''Copy/translation progress and production native section-state behavior.'''
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
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT if (ROOT / 'VidiStudio').exists() else ROOT.parent / 'VidiStudio Mac'
WINDOWS = ROOT if (ROOT / 'Vidi Studio Windows').exists() else ROOT.parent / 'Vidi-Studio-Windows'
sys.path.insert(0, str(ROOT / 'engine'))
import language_results as lr


def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


class TransferEvents(unittest.TestCase):
    def run_operation(self, command, fail=False):
        self.events = []
        p = dict(id='progress', schemaVersion=2, duration=100,
                 transcript=[dict(id=str(i), start=i, end=i + 0.5, text='Hello') for i in range(45)],
                 summary='Hello', cues=[])
        lr.migrate(p)
        original = copy.deepcopy(p)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            request = root / 'request.json'
            request.write_text(json.dumps(dict(sourceLanguage='auto', targetLanguage='hi', kinds=['transcript', 'summary'])))
            def emit(message, **values): self.events.append((message, values))
            def save(root, value):
                self.assertFalse(any(v.get('contentTransferProgress') == 1 for _, v in self.events))
                (root / 'project.json').write_text(json.dumps(value))
            def generate(**kwargs):
                if fail: raise ConnectionError('offline')
                rows = json.loads(kwargs['contents'])
                return SimpleNamespace(text=json.dumps(dict(translations=[dict(index=v['index'], text='नमस्ते') for v in rows])))
            core = SimpleNamespace(local=lambda root, path: root / path, emit=emit, save=save,
                cleanup_project_storage=lambda *args: None, client_and_model=lambda *args: (SimpleNamespace(models=SimpleNamespace(generate_content=generate), close=lambda: None), 'test'),
                is_retryable_ai_error=lambda error: False)
            args = SimpleNamespace(command=command, input=request, language=None)
            if fail:
                with self.assertRaises(ConnectionError): lr.run(args, root, p, core, lambda *args: self.fail('dispatch'))
                self.assertEqual(p, original)
            else:
                lr.run(args, root, p, core, lambda *args: self.fail('dispatch'))
                self.assertTrue((root / 'project.json').is_file())
        return [v['contentTransferProgress'] for _, v in self.events if 'contentTransferProgress' in v]

    def test_copy_reports_start_save_and_completion_after_commit(self):
        fractions = self.run_operation('copy-results')
        self.assertEqual(fractions, [0, .95, 1])

    def test_translation_reports_real_batch_progress_and_finishes_after_save(self):
        fractions = self.run_operation('translate-results')
        self.assertEqual(fractions, sorted(fractions))
        self.assertEqual((fractions[0], fractions[-1]), (0, 1))
        self.assertTrue(any(.05 < f < .9 for f in fractions))
        self.assertIn(.95, fractions)
        completed = [v['translationCompleted'] for _, v in self.events if 'translationCompleted' in v]
        self.assertEqual(completed[-1], 46)

    def test_cli_copy_progress_contract_and_saved_result(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'project.json').write_text(json.dumps(dict(schemaVersion=2, id='cli', name='Progress', source='', duration=1,
                width=0, height=0, hasAudio=False, createdAt=1, updatedAt=1, transcript=[], summary='Original', cues=[], exports=[], thumbnails=[])))
            (root / 'config.json').write_text('{}')
            request = root / 'request.json'
            request.write_text(json.dumps(dict(sourceLanguage='auto', targetLanguage='hi', kinds=['summary'])))
            prefix = [os.environ['VIDISTUDIO_TEST_ENGINE']] if os.environ.get('VIDISTUDIO_TEST_ENGINE') else [sys.executable, str(ROOT / 'engine/vidistudio_engine.py')]
            env = dict(os.environ, VIDISTUDIO_CONFIG=str(root / 'config.json')); env.pop('VIDISTUDIO_API_KEY', None)
            result = subprocess.run([*prefix, 'copy-results', '--project', str(root), '--input', str(request)], capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            events = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual([e['contentTransferProgress'] for e in events if 'contentTransferProgress' in e], [0, .95, 1])
            saved = json.loads((root / 'project.json').read_text())
            self.assertTrue(any(r['language'] == 'hi' and r['payload']['summary'] == 'Original' for r in saved['languageResults']))

    def test_failed_translation_does_not_report_completion_or_change_results(self):
        fractions = self.run_operation('translate-results', fail=True)
        self.assertTrue(fractions)
        self.assertLess(max(fractions), 1)


class NativeTransferState(unittest.TestCase):
    def test_mac_production_plan_marks_all_selected_sections_and_resets(self):
        if sys.platform != 'darwin': self.skipTest('macOS Swift SDK required')
        source = (MAC / 'VidiStudio/StudioModel.swift').read_text()
        plan = method(source, 'private static func analysisSections(')
        state = method(source, 'func sectionProcessingState(')
        harness = '\n'.join(['import Foundation',
            'enum SectionProcessingState: Equatable { case idle, active, queued }',
            'final class Harness { var busy = true; var exportActivity: Bool?; var processingPlan: [String] = []; var processingSection: String?; var contentTransferCommand: String?',
            plan, state,
            'func plan(_ command: String, _ args: [String]) -> [String] { Self.analysisSections(for: command, extra: args) }', '}',
            '''@main struct Main { static func main() throws {
                let h = Harness(); let file = CommandLine.arguments[1]
                try Data(#"{"kinds":["descriptions","summary","transcript"]}"#.utf8).write(to: URL(fileURLWithPath: file))
                h.processingPlan = h.plan("translate-results", ["--input", file]); h.contentTransferCommand = "translate-results"
                precondition(h.processingPlan == ["transcript", "summary", "descriptions"])
                for key in h.processingPlan { precondition(h.sectionProcessingState(for: [key]) == .active) }
                precondition(h.sectionProcessingState(for: ["transcript", "descriptions"]) == .active)
                h.busy = false; precondition(h.sectionProcessingState(for: ["summary"]) == .idle); h.busy = true
                h.exportActivity = true; precondition(h.sectionProcessingState(for: ["summary"]) == .idle); h.exportActivity = nil
                h.contentTransferCommand = "copy-results"; h.processingPlan = ["summary"]
                precondition(h.sectionProcessingState(for: ["summary"]) == .active)
                precondition(h.sectionProcessingState(for: ["transcript"]) == .idle)
                h.contentTransferCommand = nil; h.processingPlan = ["transcript", "summary"]; h.processingSection = "transcript"
                precondition(h.sectionProcessingState(for: ["summary"]) == .queued)
                h.processingPlan = []; precondition(h.sectionProcessingState(for: ["summary"]) == .idle)
                precondition(h.plan("copy-results", []).isEmpty)
                try Data("invalid".utf8).write(to: URL(fileURLWithPath: file))
                precondition(h.plan("translate-results", ["--input", file]).isEmpty)
                print("PASS native Mac transfer state")
            }}'''])
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory); file = folder / 'Main.swift'; file.write_text(harness)
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(file), '-module-cache-path', str(folder / 'modules'), '-o', str(folder / 'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(folder / 'check'), str(folder / 'request.json')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_windows_production_plan_and_section_state_match(self):
        if not shutil.which('dotnet'): self.skipTest('.NET SDK required')
        source = (WINDOWS / 'Vidi Studio Windows/ViewModels/StudioViewModel.cs').read_text()
        plan = method(source, 'private static List<string> AnalysisPlan(')
        state = method(source, 'public SectionProcessingState StateFor(')
        harness = '\n'.join(['using System; using System.IO; using System.Linq; using System.Collections.Generic;',
            'enum SectionProcessingState { Idle, Processing, Queued }',
            'class Program { public bool Busy = true; public bool IsExporting; public bool IsAnalyzing => Busy && !IsExporting && processingPlan.Count > 0; public string? ContentTransferCommand; private string? processingSection; private List<string> processingPlan = new();', plan, state,
            '''static void Check(bool value) { if (!value) throw new Exception("Native section-state mismatch"); }
            static void Main(string[] args) {
                var h = new Program(); File.WriteAllText(args[0], "{\\"kinds\\":[\\"descriptions\\",\\"summary\\",\\"transcript\\"]}");
                h.processingPlan = AnalysisPlan("translate-results", new[]{"--input",args[0]}); h.ContentTransferCommand = "translate-results";
                Check(h.processingPlan.SequenceEqual(new[]{"transcript","summary","descriptions"}));
                foreach (var key in h.processingPlan) Check(h.StateFor(new[]{key}) == SectionProcessingState.Processing);
                h.Busy = false; Check(h.StateFor(new[]{"summary"}) == SectionProcessingState.Idle); h.Busy = true;
                h.IsExporting = true; Check(h.StateFor(new[]{"summary"}) == SectionProcessingState.Idle); h.IsExporting = false;
                h.ContentTransferCommand = "copy-results"; h.processingPlan = new(){"summary"};
                Check(h.StateFor(new[]{"summary"}) == SectionProcessingState.Processing); Check(h.StateFor(new[]{"transcript"}) == SectionProcessingState.Idle);
                h.ContentTransferCommand = null; h.processingPlan = new(){"transcript","summary"}; h.processingSection = "transcript";
                Check(h.StateFor(new[]{"summary"}) == SectionProcessingState.Queued);
                Check(AnalysisPlan("copy-results", Array.Empty<string>()).Count == 0);
                File.WriteAllText(args[0], "invalid"); Check(AnalysisPlan("translate-results", new[]{"--input",args[0]}).Count == 0);
                Console.WriteLine("PASS native Windows transfer state");
            }}'''])
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory); (folder / 'Program.cs').write_text(harness)
            version = subprocess.check_output(['dotnet', '--version'], text=True).split('.')[0]
            (folder / 'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net'+version+'.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup></Project>')
            result = subprocess.run(['dotnet', 'run', '--project', str(folder / 'Check.csproj'), '--', str(folder / 'request.json')], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
