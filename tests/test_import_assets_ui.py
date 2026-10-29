import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI = (ROOT / 'VidiStudio' / 'ContentView.swift').read_text(encoding='utf-8')
MODEL = (ROOT / 'VidiStudio' / 'StudioModel.swift').read_text(encoding='utf-8')
IMPORT = (ROOT / 'VidiStudio' / 'ImportAssetsView.swift').read_text(encoding='utf-8')
EXPORT = (ROOT / 'VidiStudio' / 'ExportOptionsMenu.swift').read_text(encoding='utf-8')
MARKDOWN = (ROOT / 'VidiStudio' / 'MarkdownSummaryEditor.swift').read_text(encoding='utf-8')
MENU = (ROOT / 'VidiStudio' / 'KeyboardShortcuts.swift').read_text(encoding='utf-8')


class ImportAssetsUI(unittest.TestCase):
    def test_shared_import_menu_and_editor_entry_points(self):
        self.assertIn('Button("Import Existing Assets…", systemImage: "square.and.arrow.down") { editor?.run("import-assets") }', MENU)
        self.assertIn('case "import-assets": showingImportAssets = true', UI)
        self.assertIn('ImportExistingAssetsView(studio: studio, project: project)', UI)

    def test_import_flow_and_combine_use_engine_commands(self):
        for command in ('import-transcript', 'import-ad-transcript', 'import-summary', 'import-ad-audio', 'combine-imported-audio'):
            self.assertIn(command, MODEL)
        self.assertIn('func importAssets(', MODEL)
        self.assertIn('func combineImportedAudio(', MODEL)
        self.assertIn('func importSegmentNarration(', MODEL)
        self.assertIn('importReports.append(report)', MODEL)

    def test_import_shortcuts_are_defined_and_documented(self):
        self.assertIn('keyboardShortcut("i", modifiers: [.command, .option])', MENU)
        self.assertIn('keyboardShortcut("m", modifiers: [.command, .option])', MENU)
        self.assertIn('keyboardShortcut("d", modifiers: [.command, .option])', MENU)
        self.assertIn('keyboardShortcut("i", modifiers: [.command, .option, .shift])', MENU)
        self.assertIn('("Import Transcript", "Command + Option + I")', (ROOT / 'script' / 'build_help.py').read_text(encoding='utf-8'))

    def test_section_add_menu_offers_manual_or_import(self):
        self.assertIn('enum ImportScope', IMPORT)
        self.assertIn('Import Transcript…', UI)
        self.assertIn('Import Summary…', UI)
        self.assertIn('Import Descriptions…', UI)
        self.assertIn('Write Summary', UI)
        self.assertIn('Add Audio Description Segment', UI)
        self.assertIn('Menu("Import"', MENU)
        self.assertIn('case "import-transcript": importScope = .transcript', UI)

    def test_all_text_formats_are_validated_before_import_and_after(self):
        self.assertIn('func importedTimingRows', IMPORT)
        self.assertIn('private func timingWarnings', IMPORT)
        self.assertIn('Button("Import Anyway"', IMPORT)
        self.assertIn('Button("Review Timing…"', IMPORT)
        self.assertIn('Edit Transcript Timings…', IMPORT)
        self.assertIn('TranscriptTimingEditorView', IMPORT)
        self.assertIn('--timing-input', MODEL)

    def test_import_sheet_has_modes_timing_and_replacement(self):
        combined = MODEL + IMPORT
        self.assertIn('AD narration only', combined)
        self.assertIn('Dialogue + AD combined', combined)
        self.assertIn('AD narration audio only', combined)
        self.assertIn('Full AD mix', combined)
        self.assertIn('TXTImportTimingView', IMPORT)
        self.assertIn('Distribute Evenly', IMPORT)
        self.assertIn('Auto-time with Gemini', IMPORT)
        self.assertIn('Replace existing assets?', IMPORT)
        self.assertIn('ImportReportSheet', IMPORT)
        self.assertIn('Review Descriptions', IMPORT)
        self.assertIn('Review Transcript', IMPORT)

    def test_provenance_overlap_and_summary_editor_ui(self):
        for label in ('Imported', 'Imported · modified'):
            self.assertIn(label, MODEL)
        self.assertIn('descriptionTimingIssueCount', MODEL)
        self.assertIn('Description timing needs attention', UI)
        self.assertIn('Label("Overlap"', UI)
        self.assertIn('SummaryMarkdownEditorView', UI)
        self.assertIn('SummaryMarkdownEditorView', MARKDOWN)
        self.assertIn('MarkdownTransformer', MARKDOWN)
        self.assertIn('Command-Option-Shift-P', MARKDOWN)
        self.assertIn('summaryEditing', MENU)

    def test_per_segment_narration_import_and_ad_overview_sources(self):
        self.assertIn('Import Narration Audio…', UI)
        self.assertIn('chooseNarrationAudio', UI)
        self.assertIn('Narration sources', (ROOT / 'VidiStudio' / 'ADOverviewView.swift').read_text(encoding='utf-8'))
        self.assertIn('importedNarrationText', MODEL)
        self.assertIn('hasMixedSources', MODEL)

    def test_markdown_reading_view_tables_tasks_and_narration_warnings(self):
        renderer = (ROOT / 'VidiStudio' / 'MarkdownSummaryView.swift').read_text(encoding='utf-8')
        integrity = (ROOT / 'VidiStudio' / 'ProjectIntegrity.swift').read_text(encoding='utf-8')
        self.assertIn('isTableStart', renderer)
        self.assertIn('taskItem', renderer)
        self.assertIn('Markdown table', renderer)
        self.assertIn('Imported Assets', integrity)
        self.assertIn('importedPaths', integrity)
        self.assertIn('warnings', MODEL)
        self.assertIn('Warnings do not count as narration errors', (ROOT / 'VidiStudio' / 'ADOverviewView.swift').read_text(encoding='utf-8'))
        readback = (ROOT / 'VidiStudio' / 'SummaryReadback.swift').read_text(encoding='utf-8')
        self.assertIn('normalizedForReading', readback)
        self.assertIn('☐', readback)
        self.assertIn('Review Import Report…', (ROOT / 'VidiStudio' / 'ProjectIntegrityView.swift').read_text(encoding='utf-8'))

    def test_ai_quota_pause_and_key_free_project_creation(self):
        self.assertIn('struct AIServiceIssue', MODEL)
        self.assertIn('aiServiceIssue = aiIssue', MODEL)
        self.assertIn('hasValidApiKey: Bool { hasApiKey && apiKeyVerified != false && !isAIProcessingBlocked }', MODEL)
        self.assertIn('AIServiceIssueBanner', (ROOT / 'VidiStudio' / 'AIServiceIssueBanner.swift').read_text(encoding='utf-8'))
        self.assertIn('isCreatingProject = true', MODEL)
        self.assertNotIn('requestGeminiSettings', MODEL)
        self.assertIn('aiProcessingBlocked', (ROOT / 'VidiStudio' / 'ProjectBrowserPage.swift').read_text(encoding='utf-8'))

    def test_export_source_picker_and_two_track_defaults(self):
        self.assertIn('enum ADSourceChoice', EXPORT)
        self.assertIn('importedSelectableVideo', EXPORT)
        self.assertIn('importedMixedVideo', EXPORT)
        self.assertIn('importedDescribedAudio', EXPORT)
        self.assertIn('Audio Description source', EXPORT)
        self.assertIn('Closed Audio Description creates Original Audio and English - Audio Description tracks', EXPORT)


if __name__ == '__main__':
    unittest.main()
