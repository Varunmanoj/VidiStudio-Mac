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

    def test_clear_segment_view_actions_hide_when_inactive(self):
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        content = (root/'VidiStudio Mac/VidiStudio/ContentView.swift').read_text()
        xaml = (root/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.xaml').read_text()
        self.checker.compare_clear_segment_view_actions(content, self.mac, self.windows, xaml)
        for sources in (
            (content.replace('if filterableTab && segmentFilter.isActive', 'if filterableTab'), self.mac, self.windows, xaml),
            (content, self.mac, self.windows.replace('segmentSort != "start" ? Visibility.Visible : Visibility.Collapsed', 'true ? Visibility.Visible : Visibility.Collapsed'), xaml),
            (content, self.mac.replace('editor?.run("clear-segment-filter")', ''), self.windows, xaml),
        ):
            with self.assertRaises(ValueError): self.checker.compare_clear_segment_view_actions(*sources)

    def test_range_filter_dialog_menus_and_language_scope(self):
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        mac = (root/'VidiStudio Mac/VidiStudio/SegmentRangeFilterControls.swift').read_text() + (root/'VidiStudio Mac/VidiStudio/SegmentRangeFilter.swift').read_text()
        windows = (root/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.SegmentRangeFilter.cs').read_text()
        context = (root/'VidiStudio Mac/VidiStudio/ContentView.swift').read_text()
        win_context = (root/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.SegmentFilter.cs').read_text()
        self.checker.compare_segment_range_controls(mac, windows, context, win_context)
        for sources in (
            (mac.replace('filter-segment-number-menu', ''), windows, context, win_context),
            (mac, windows.replace('mode.ContextFlyout = modeMenu', ''), context, win_context),
            (mac, windows, context, win_context.replace('result.Language == project.SelectedLanguage', 'true')),
            (mac, windows, context.replace('.disabled(rangeError != nil)', ''), win_context),
        ):
            with self.assertRaises(ValueError): self.checker.compare_segment_range_controls(*sources)

    def test_timing_validation_dialog_and_sound_menu_guards(self):
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        mac = (root / 'VidiStudio Mac/VidiStudio/ContentView.swift').read_text()
        settings = (root / 'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text()
        windows = (root / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.xaml.cs').read_text()
        win_settings = (root / 'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.cs').read_text()
        self.checker.compare_timing_validation_controls(mac, settings, windows, win_settings)
        for sources in (
            (mac.replace('show-validation-issue-menu', 'missing-menu'), settings, windows, win_settings),
            (mac, settings, windows.replace('showIssue.ContextFlyout = issueMenu', ''), win_settings),
            (mac, settings.replace('timing-validation-sound-menu', ''), windows, win_settings),
            (mac, settings, windows.replace('errors.Count > 0 ? Visibility.Visible : Visibility.Collapsed', 'Visibility.Visible'), win_settings),
        ):
            with self.assertRaises(ValueError): self.checker.compare_timing_validation_controls(*sources)

    def test_piper_settings_sample_menu_and_download_guard(self):
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        mac = (root / 'VidiStudio Mac/VidiStudio/PiperVoiceCatalog.swift').read_text()
        windows = (root / 'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Voices.cs').read_text()
        self.checker.compare_piper_settings_samples(mac, windows)
        for changed_mac, changed_windows in (
            (mac.replace('Button("Play Sample") { playSample() }', ''), windows),
            (mac.replace('.disabled(selectedVoice == nil)', ''), windows),
            (mac, windows.replace('piperPlaySampleMenuItem.IsEnabled = CanPlayPiperSample', 'piperPlaySampleMenuItem.IsEnabled = true')),
            (mac, windows.replace('Text = "Stop Sample", Tag = "piper-settings-stop-sample"', 'Text = "Stop"')),
        ):
            with self.assertRaises(ValueError):
                self.checker.compare_piper_settings_samples(changed_mac, changed_windows)

    def test_library_filter_and_selected_project_contracts(self):
        for mac, windows in (
            (self.mac.replace('allProjects.languageFilter.wrappedValue = language.id', 'allProjects.languageFilter.wrappedValue = "auto"'), self.windows),
            (self.mac, self.windows.replace('IsChecked = Model.LanguageFilter == language.Id', 'IsChecked = false')),
            (self.mac, self.windows.replace('if (SelectedGalleryProject() is not { } selected) return false;', 'if (Model.Project == null) return false;')),
            (self.mac, self.windows.replace('case "delete-project": if (ProjectManagementTarget()', 'case "delete-project": if (Model.Project')),
        ):
            with self.assertRaises(ValueError): self.checker.compare_sources(mac, self.app, windows)

    def test_thumbnail_visibility_command_cannot_be_omitted(self):
        self.checker.compare_sources(self.mac, self.app, self.windows)
        for mac, windows in (
            (self.mac.replace('editor?.run("toggle-thumbnail-images")', 'editor?.run("missing-thumbnails")'), self.windows),
            (self.mac, self.windows.replace('Command("toggle-thumbnail-images"),', '', 1)),
        ):
            with self.assertRaises(ValueError):
                self.checker.compare_sources(mac, self.app, windows)
        for title in ('Show Thumbnail Images', 'Hide Thumbnail Images'):
            self.assertIn(title, self.mac)
            self.assertIn(title, self.windows)

    def test_summary_zoom_commands_cannot_be_omitted(self):
        self.checker.compare_sources(self.mac, self.app, self.windows)
        for command in ('summary-zoom-in', 'summary-zoom-out', 'summary-zoom-reset'):
            with self.assertRaises(ValueError):
                self.checker.compare_sources(self.mac, self.app, self.windows.replace('Command("' + command + '")', 'Command("missing")', 1))

    def test_summary_zoom_requires_reader_and_matching_limits(self):
        for mac, windows in (
            (self.mac.replace('summaryActive, !summaryEditing, summaryReadable', 'summaryReadable'), self.windows),
            (self.mac.replace('return summaryZoom < 4', 'return true'), self.windows),
            (self.mac, self.windows.replace('SummaryPanel.ZoomFactor > .5', 'SummaryPanel.ZoomFactor > 0')),
        ):
            with self.assertRaises(ValueError):
                self.checker.compare_sources(mac, self.app, windows)

    def test_file_deletion_commands_cannot_be_omitted(self):
        for command in ('delete-project', 'delete-content'):
            with self.assertRaises(ValueError):
                self.checker.compare_sources(self.mac.replace('runProject("' + command + '")', 'runProject("missing")'), self.app, self.windows)
            with self.assertRaises(ValueError):
                self.checker.compare_sources(self.mac, self.app, self.windows.replace('Command("' + command + '")', 'Command("missing")', 1))

    def test_copy_to_edit_menu_cannot_be_omitted_on_either_platform(self):
        self.checker.compare_sources(self.mac, self.app, self.windows)
        for mac, windows in ((self.mac.replace('editor?.run("copy-to")', 'editor?.run("missing-copy")'), self.windows),
                             (self.mac, self.windows.replace('Menu("Edit", Command("copy-to"), Command("segment-edit-mode"))', 'Menu("Edit", Command("segment-edit-mode"))'))):
            with self.assertRaises(ValueError): self.checker.compare_sources(mac, self.app, windows)

    def test_edit_mode_is_adjacent_to_copy_and_cannot_be_omitted(self):
        self.checker.compare_sources(self.mac, self.app, self.windows)
        for mac, windows in (
            (self.mac, self.windows.replace('Menu("Edit", Command("copy-to"), Command("segment-edit-mode"))', 'Menu("Edit", Command("copy-to"))')),
            (self.mac.replace('.accessibilityIdentifier("segment-edit-mode")\n                .keyboardShortcut("e", modifiers: [.command, .option])\n                .disabled(editor?.canRun("segment-edit-mode") != true)', '.accessibilityIdentifier("segment-edit-mode")'), self.windows),
        ):
            with self.assertRaises(ValueError): self.checker.compare_sources(mac, self.app, windows)

    def test_inspector_edit_mode_uses_shared_state_and_guarded_action(self):
        root = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', Path(__file__).resolve().parents[2]))
        languages = (root / 'VidiStudio Mac/VidiStudio/LanguageResults.swift').read_text()
        content = (root / 'VidiStudio Mac/VidiStudio/ContentView.swift').read_text()
        windows = (root / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.LanguageResults.cs').read_text()
        self.checker.compare_edit_mode_controls(languages, content, windows)
        for changed_languages, changed_content, changed_windows in (
            (languages.replace('else if editorActions.segmentEditingAvailable {', 'else if !editorActions.segmentEditMode && editorActions.segmentEditingAvailable {'), content, windows),
            (languages.replace('Button(editorActions.segmentEditModeTitle,', 'Button("Enter Edit Mode",'), content, windows),
            (languages, content, windows.replace('edit.Content = DesktopCommandTitle("segment-edit-mode");', 'edit.Content = "Edit";')),
            (languages, content, windows.replace('edit.Click += async (_, _) => await RunDesktopCommandAsync("segment-edit-mode");', 'edit.Click += (_, _) => {};')),
        ):
            with self.assertRaises(ValueError): self.checker.compare_edit_mode_controls(changed_languages, changed_content, changed_windows)

    def test_project_language_menu_checks_choices_state_and_guard_contract(self):
        self.checker.compare_sources(self.mac, self.app, self.windows)
        for mac, windows in (
            (self.mac.replace('projectLanguageMenu()\n                Divider()', 'Divider()', 1), self.windows),
            (self.mac.replace('editor?.viewingLanguage == language.id', 'editor?.viewingLanguage != language.id', 1), self.windows),
            (self.mac, self.windows.replace('ProjectLanguageMenu(), Separator()', 'Separator()', 1)),
            (self.mac, self.windows.replace('IsChecked = choice.Id == project.SelectedLanguage', 'IsChecked = false', 1)),
            (self.mac, self.windows.replace('!HasUnsavedLanguageSummary && p.AvailableViewingLanguages.Count > 0', 'true', 1)),
        ):
            with self.assertRaises(ValueError): self.checker.compare_sources(mac, self.app, windows)

    def test_saved_results_menu_and_selection_guard_cannot_be_omitted(self):
        self.checker.compare_sources(self.mac, self.app, self.windows)
        for mac, windows in (
            (self.mac.replace('savedResultsMenu()\n                Divider()', 'Divider()', 1), self.windows),
            (self.mac.replace('guard canRun("saved-results")', 'guard true', 1), self.windows),
            (self.mac, self.windows.replace('SavedResultsMenu(), Separator()', 'Separator()', 1)),
            (self.mac, self.windows.replace('!CanRunDesktopCommand("saved-results")', 'false', 1)),
        ):
            with self.assertRaises(ValueError): self.checker.compare_sources(mac, self.app, windows)

    def test_saved_results_follow_tab_and_project_language(self):
        self.assertIn('ForEach(editor?.savedResultKinds ?? []', self.mac)
        self.assertIn('project.languageResults(kind: kind, includingDrafts: true)', self.mac)
        self.assertIn('savedResultKinds.contains(result.kind)', self.mac)
        self.assertIn('foreach (var kind in CurrentLanguageKinds)', self.windows)
        self.assertIn('r.Language == project.SelectedLanguage', self.windows)
        self.assertIn('Model.Project.SelectedLanguage != result.Language', self.windows)

    def test_saved_results_titles_and_flat_versions(self):
        self.checker.compare_sources(self.mac, self.app, self.windows)
        for title in ('Transcript Saved Results', 'Summary Saved Results', 'Description Saved Results', 'AD Transcript Saved Results'):
            with self.assertRaises(ValueError):
                self.checker.compare_sources(self.mac.replace(title, 'Missing title'), self.app, self.windows)
            with self.assertRaises(ValueError):
                self.checker.compare_sources(self.mac, self.app, self.windows.replace(title, 'Missing title'))
        self.assertNotIn('Menu(SavedLanguageResult.kindTitle(kind))', self.mac)
        self.assertNotIn('group.Items.Add(item)', self.windows[self.windows.index('private void RefreshSavedResultMenus()'):self.windows.index('private void RefreshProjectLanguageMenus()')])

    def test_language_results_command_is_shared_and_guarded(self):
        self.assertIn('editor?.run("language-results")', self.mac)
        self.assertIn('Command("language-results")', self.windows)
        self.assertIn('"language-results" => "Language and Saved Results…"', self.windows)

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

    def test_settings_shortcuts_are_visible_on_both_file_menu_items(self):
        for title, modifiers in (("Settings…", ".command"), ("Open Project Settings…", ".command, .shift")):
            binding = '.keyboardShortcut(",", modifiers: [' + modifiers + '])'
            self.assertIn(binding, self.mac)
            with self.subTest(title=title), self.assertRaisesRegex(ValueError, 'File Settings shortcut'):
                self.checker.compare_sources(self.mac.replace(binding, '', 1), self.app, self.windows)
        for command in ('settings', 'project-settings'):
            changed = ''.join(line for line in self.windows.splitlines(keepends=True) if not line.lstrip().startswith('["' + command + '"] ='))
            with self.subTest(command=command), self.assertRaisesRegex(ValueError, 'File Settings shortcut'):
                self.checker.compare_sources(self.mac, self.app, changed)

    def test_summary_heading_shortcuts_take_priority_over_project_layout(self):
        self.assertIn('.disabled(browser?.grid == nil || editor?.summaryEditing == true)', self.mac)
        self.assertIn('if (id is "project-list" or "project-grid") return !desktopEditorVisible || !(Section.SelectedIndex == 1 && summaryEditMode);', self.windows)
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
