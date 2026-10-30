import importlib.util
import os
from pathlib import Path
import unittest


class DesktopMenuParity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        checker = root / 'script/check_menu_parity.py'
        if not checker.is_file():
            raise unittest.SkipTest('Cross-platform menu checks require the combined workspace.')
        spec = importlib.util.spec_from_file_location('desktop_menu_parity', checker)
        cls.checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.checker)
        cls.mac = (root / 'VidiStudio Mac/VidiStudio/KeyboardShortcuts.swift').read_text(encoding='utf-8')
        cls.app = (root / 'VidiStudio Mac/VidiStudio/VidiStudioApp.swift').read_text(encoding='utf-8')
        windows_root = Path(os.environ.get('VIDISTUDIO_WINDOWS_ROOT', root / 'Vidi-Studio-Windows'))
        cls.windows = (windows_root / 'Vidi Studio Windows/MainWindow.Menus.cs').read_text(encoding='utf-8')

    def test_remove_from_list_context_action_matches_on_both_desktops(self):
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        browser = (root/'VidiStudio Mac/VidiStudio/ProjectBrowserPage.swift').read_text()
        grid = (root/'VidiStudio Mac/VidiStudio/ProjectGridView.swift').read_text()
        commands = (root/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Commands.cs').read_text()
        self.checker.compare_project_list_context_actions(browser, grid, commands)
        for sources in ((browser.replace('Remove from List', 'Remove'), grid, commands),
                        (browser, grid.replace('Remove from List', 'Remove'), commands),
                        (browser, grid, commands.replace('commandId: "remove-from-list"', 'commandId: "remove"'))):
            with self.assertRaises(ValueError):
                self.checker.compare_project_list_context_actions(*sources)

    def test_remove_from_list_file_menu_uses_gallery_selection(self):
        self.assertIn('browser?.run("remove-from-list")', self.mac)
        self.assertIn('.disabled(browser?.canRemoveFromList != true)', self.mac)
        self.assertIn('Command("remove-from-list")', self.windows)
        self.assertIn('if (id == "remove-from-list") return SelectedBrowserProject() != null;', self.windows)
        self.assertIn('if (SelectedBrowserProject() is { } listedProject) RemoveProjectFromList(listedProject);', self.windows)
        self.assertIn('if (desktopEditorVisible || GalleryPanel.Visibility != Visibility.Visible) return null;', self.windows)
        for source, replacement in ((self.mac, self.mac.replace('browser?.run("remove-from-list")', 'browser?.run("other")')),
                                    (self.windows, self.windows.replace('Command("remove-from-list")', 'Separator()'))):
            with self.assertRaises(ValueError):
                self.checker.compare_sources(replacement if source is self.mac else self.mac, self.app,
                                             replacement if source is self.windows else self.windows)

    def test_editor_project_browser_navigation_and_icon_buttons_match(self):
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        sidebar = (root/'VidiStudio Mac/VidiStudio/EditorProjectBrowser.swift').read_text()
        editor = (root/'VidiStudio Mac/VidiStudio/ContentView.swift').read_text()
        windows = (root/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Commands.cs').read_text()
        xaml = (root/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.xaml').read_text()
        self.checker.compare_editor_project_navigation(sidebar, editor, windows, xaml)
        with self.assertRaises(ValueError):
            self.checker.compare_editor_project_navigation(sidebar.replace('open-project-here', 'missing'), editor, windows, xaml)
        with self.assertRaises(ValueError):
            self.checker.compare_editor_project_navigation(sidebar, editor, windows.replace('Open in New Window', 'Open'), xaml)

    def test_management_actions_follow_selected_or_open_project(self):
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        editor = (root/'VidiStudio Mac/VidiStudio/ContentView.swift').read_text()
        xaml = (root/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.xaml').read_text()
        self.assertIn('.accessibilityIdentifier("rename-project-title")', editor)
        self.assertIn('editorModel: studio', editor)
        self.assertIn('x:Name="RenameProjectTitleButton"', xaml)
        self.assertIn('AutomationProperties.Name="Rename project"', xaml)
        for action in ('rename-project', 'trash-project', 'show-in-finder', 'open-configuration'):
            self.assertIn(f'browser?.run("{action}")', self.mac)
            self.assertIn(f'.disabled(browser?.canRun("{action}") != true)', self.mac)
        self.assertIn('ProjectManagementTarget() => desktopEditorVisible ? Model.Project : SelectedGalleryProject()', self.windows)
        self.assertIn('return CanManageProject(id);', self.windows)

    def test_actual_menus_and_shortcuts_match(self):
        self.assertGreater(self.checker.compare_sources(self.mac, self.app, self.windows), 30)

    def test_summary_heading_shortcuts_take_priority_over_project_layout(self):
        self.assertIn('.disabled(browser?.grid == nil || editor?.summaryEditing == true)', self.mac)
        self.assertIn('if (id is "project-list" or "project-grid") return !(Section.SelectedIndex == 1 && summaryEditMode);', self.windows)
        self.assertIn('}, () => CanRunDesktopCommand(id));', self.windows)

    def test_project_management_order_guards_and_handlers_match(self):
        nodes = self.checker.swift_group(self.mac, 'CommandMenu("Project")', self.checker.shortcut_rows(self.mac))
        self.assertEqual(nodes[-3:], ['-', 'rename-project', 'trash-project'])
        for action in ('rename-project', 'trash-project'):
            self.assertIn(f'Command("{action}")', self.windows)
            self.assertIn(f'case "{action}":', self.windows)
            self.assertIn(f'.disabled(browser?.canRun("{action}") != true)', self.mac)
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        content = (root / 'VidiStudio Mac/VidiStudio/ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('case "rename-project": renameProject()', content)
        self.assertIn('case "trash-project": trashProject()', content)
        self.assertIn('case "trash-project": return true;', self.windows)
        self.assertIn('case "rename-project": return !p.IntegrityPlaceholder', self.windows)

    def test_missing_project_management_actions_are_detected(self):
        for action in ('rename-project', 'trash-project'):
            with self.subTest(action=action), self.assertRaisesRegex(ValueError, 'hierarchy/order'):
                self.checker.compare_sources(self.mac, self.app, self.windows.replace(f'Command("{action}")', 'Separator()', 1))

    def test_native_project_recycling_labels_are_explicitly_checked(self):
        changed = self.windows.replace('"Move Project to Recycle Bin…"', '"Permanently Delete Project…"')
        with self.assertRaisesRegex(ValueError, 'native menu label'):
            self.checker.compare_sources(self.mac, self.app, changed)
        changed_mac = self.mac.replace('"Move Project to Bin…"', '"Permanently Delete Project…"')
        with self.assertRaisesRegex(ValueError, 'native menu label'):
            self.checker.compare_sources(changed_mac, self.app, self.windows)

    def test_missing_menu_item_is_detected(self):
        changed = self.windows.replace('Command("review-narration-issues"), ', '', 1)
        self.assertNotEqual(changed, self.windows)
        with self.assertRaisesRegex(ValueError, 'hierarchy/order'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_unified_all_audio_entry_and_guard(self):
        self.assertNotIn('regenerate-all-narration', self.mac)
        self.assertNotIn('regenerate-all-narration', self.windows)
        self.assertIn('return hasNarrationAudio ? "Regenerate All AD Audio…" : "Generate All AD Audio"', self.mac)
        self.assertIn('case "synthesize-tts":', self.mac)
        self.assertIn('case "synthesize-tts": return tts && p.Cues.Count > 0;', self.windows)
        self.assertIn('hasNarrationAudio && hasChangedNarration', self.mac)
        self.assertIn('p.CanGenerateMissingOrChangedAudio', self.windows)
        changed = self.windows.replace('Command("synthesize-tts"), ', '', 1)
        with self.assertRaisesRegex(ValueError, 'hierarchy/order'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_missing_narration_voice_review_is_detected(self):
        changed = self.windows.replace('Command("review-narration-voices"), ', '', 1)
        self.assertNotEqual(changed, self.windows)
        with self.assertRaisesRegex(ValueError, 'hierarchy/order'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_narration_voice_review_is_wired_to_existing_dialog(self):
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        content = (root / 'VidiStudio Mac/VidiStudio/ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('case "review-narration-voices": studio.narrationVoiceReport = studio.narrationVoiceUsageReport(for: project)', content)
        self.assertIn('Button("Review Narration Voices…"', self.mac)
        self.assertIn('"review-narration-voices": return true', self.mac)
        self.assertIn('Command("review-narration-issues"), Command("review-narration-voices")', self.windows)
        self.assertIn('await ShowNarrationVoicesAsync(voiceReport)', self.windows)

    def test_moved_or_renamed_submenu_is_detected(self):
        changed = self.windows.replace('Submenu("Narration",', 'Submenu("Narration Tools",', 1)
        with self.assertRaisesRegex(ValueError, 'hierarchy/order'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_narration_groups_match_inspector(self):
        rows = self.checker.shortcut_rows(self.mac)
        groups = self.checker.swift_group(self.mac, 'Menu("Narration",', rows)
        self.assertEqual(groups, [
            ('AD Segment Generation', ['generate-ad-cues', '-', 'delete-descriptions']),
            ('Narration Audio', ['synthesize-tts', 'synthesize-changed',
                                 'review-narration-issues', 'review-narration-voices', '-', 'delete-narration']),
        ])
        changed = self.windows.replace('Submenu("Narration Audio",', 'Submenu("Audio",', 1)
        with self.assertRaisesRegex(ValueError, 'hierarchy/order'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_shortcut_conflict_is_detected(self):
        changed = self.windows.replace('["narration"] = (VirtualKey.D,', '["narration"] = (VirtualKey.V,', 1)
        with self.assertRaisesRegex(ValueError, 'Conflicting Windows shortcut'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_summary_sentence_and_paragraph_navigation_is_present(self):
        for action in ("summary-previous-sentence", "summary-next-sentence",
                       "summary-previous-paragraph", "summary-next-paragraph"):
            self.assertIn(f'.init(id: "{action}"', self.mac)
            self.assertIn(f'Command("{action}")', self.windows)
            self.assertIn(f'case "{action}":', self.windows)
        changed = self.windows.replace('Command("summary-next-sentence"),', '', 1)
        self.assertNotEqual(changed, self.windows)
        with self.assertRaisesRegex(ValueError, 'hierarchy/order'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_wrong_label_is_detected(self):
        changed = self.windows.replace('"summary-pause" => "Pause Summary Reading"', '"summary-pause" => "Pause Video"', 1)
        with self.assertRaisesRegex(ValueError, 'menu label'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_unwired_action_is_detected(self):
        changed = self.windows.replace('case "summary-read-selection":', 'case "unused-action":', 1)
        with self.assertRaisesRegex(ValueError, 'no handler'):
            self.checker.compare_sources(self.mac, self.app, changed)


if __name__ == '__main__':
    unittest.main()
