"""Reject regressions on either desktop, including mutations of the owning source."""
import importlib.util
import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('desktop_ui_contract', ROOT / 'script/check_desktop_ui_parity.py')
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)

class DesktopUILayoutParityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workspace = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', ROOT.parent))
        if not all((workspace / name).is_dir() for name in ['VidiStudio Mac','Vidi-Studio-Windows']):
            raise unittest.SkipTest('Paired desktop source checks need both checkouts; native parity remains unverified.')
        cls.source = contract.sources(workspace)

    def test_both_desktops_preserve_the_layout_contract(self): contract.validate(self.source)

    def mutated(self, path, before, after, expected):
        self.assertIn(before, self.source[path])
        changed = dict(self.source); changed[path] = changed[path].replace(before, after)
        with self.assertRaisesRegex(ValueError, expected): contract.validate(changed)

    def test_inspector_language_stays_first_and_unique(self):
        self.mutated('Windows/MainWindow.LanguageResults.cs', 'panel.Children.Add(language);', '', 'must precede all actions')
        self.mutated('Mac/LanguageResults.swift', 'private var controls: some View {', 'private var controls: some View { /* Review language filter */', 'repeat language choices')
        self.mutated('Windows/Views/ImportAssetsDialog.cs', 'Content = panel;', 'Content = panel; /* languagePicker */', 'inherit the project language')
        self.mutated('Windows/MainWindow.Accessibility.cs', 'Shared inspector language must be accessible, bounded and above every action.', '', 'native inspector geometry')

    def test_created_exports_share_the_project_language(self):
        self.mutated('Mac/CreatedExportsView.swift', 'project.languagesForExport(path).contains(project.languageCode)', 'true', 'Created Exports must follow project language')
        self.mutated('Windows/MainWindow.Presentation.cs', 'project.LanguagesForExport(path).Contains(project.SelectedLanguage)', 'true', 'Created Exports must follow project language')

    def test_shared_project_progress_on_both_desktops(self):
        for path, marker in (
            ('Mac/ContentView.swift', 'ProgressView(message)'),
            ('Windows/MainWindow.xaml', 'x:Name="SharedVideoRing"'),
            ('Mac/ContentView.swift', '"shared-file-opening"'),
            ('Windows/MainWindow.xaml.cs', '"shared-file-opening"'),
            ('Mac/ContentView.swift', '"shared-youtube-opening"'),
            ('Windows/MainWindow.xaml.cs', '"shared-youtube-opening"'),
        ):
            with self.subTest(path=path, marker=marker):
                self.mutated(path, marker, '', 'shared project progress')

    def test_external_projects_keep_all_projects_available(self):
        self.mutated('Mac/VidiStudioApp.swift', 'MainWindowLifetime(isLibrary: true)', 'MainWindowLifetime()', 'library window')
        self.mutated('Mac/ContentView.swift', 'MainWindowLifetime(onClose: { openWindow(id: "studio") })', 'MainWindowLifetime()', 'editor close must return')
        self.mutated('Windows/App.xaml.cs', 'var target = ProjectLibrary();', 'var target = window;', 'external activation must start')
        self.mutated('Windows/MainWindow.xaml.cs', 'App.OpenOrActivateEditor(folder)', 'ShowEditor()', 'separate editor')
        self.mutated('Windows/MainWindow.Menus.cs', 'if (wasEditor && windowClosed) App.ShowProjectLibrary();', '', 'editor close must return')

    def test_youtube_link_controls_replace_signed_in_features(self):
        for path, token in (
            ('Mac/SettingsView.swift', 'var sections ='),
            ('Windows/Views/SettingsDialog.cs', 'var labels ='),
            ('Mac/ProjectBrowserPage.swift', 'Button("'),
            ('Windows/MainWindow.xaml', 'Click="NewProject_Click"'),
            ('Mac/ContentView.swift', 'Text("New Project")'),
            ('Windows/Views/NewProjectDialog.cs', 'var youtubeRow ='),
            ('Mac/ImportAssetsView.swift', 'Section("Text assets")'),
            ('Windows/Views/ImportAssetsDialog.cs', 'public sealed class ImportAssetsPicker'),
        ):
            with self.subTest(path=path):
                self.mutated(path, token, token + ' /* YouTube Accounts */', 'retired YouTube control')
        self.mutated('Windows/Views/SettingsDialog.cs', 'Enumerable.Range(0, labels.Length)',
                     'new[] { 0, 1, 2, 3, 8, 4, 5, 6, 7 }', 'current sidebar labels')
        self.mutated('Mac/YouTubeProjectPreview.swift', 'YouTubeService.shared.video(videoID)', 'missing', 'must retain metadata lookup')
        self.mutated('Windows/Views/NewProjectDialog.cs', 'YouTubeService.Shared.VideoAsync(', 'missing(', 'must retain metadata lookup')

    def test_sample_players_cannot_overlap_or_leak_the_shared_session(self):
        for file in ['SystemVoiceCatalog.swift','PiperVoiceCatalog.swift','GeminiVoicePreview.swift','SarvamVoiceSettingsView.swift']:
            with self.subTest(file=file):
                self.mutated('Mac/'+file,'VoiceSampleSession.shared.begin(sampleOwner)','true','shared session')
                self.mutated('Mac/'+file,'VoiceSampleSession.shared.end(sampleOwner)','','own session')
        for file in ['PiperVoicesDialog.cs','PiperDeleteVoicesDialog.cs']:
            self.mutated('Windows/Views/'+file,'VoiceSampleSession.Begin(sampleOwner)','true','playback guard')
    def test_ai_sample_preparation_cannot_hide_the_spinner(self):
        self.mutated('Mac/SarvamVoiceSettingsView.swift','if sample.preparing { ProgressView()','if false { ProgressView()','preparation spinner')
        self.mutated('Mac/GeminiVoicePreview.swift','if preview.loading { ProgressView()','if false { ProgressView()','preparation spinner')
        self.mutated('Windows/Views/SettingsDialog.cs','nativePreparingRing.IsActive = sampleState == SampleState.Generating','nativePreparingRing.IsActive = false','preparation must be visible')

    def test_voice_search_cannot_return_to_half_width_rows(self):
        for path, token in [
            ('SettingsDialog.ElevenLabs.cs','FullWidthVoiceSearch(field);parent.Children.Add(field);'),
            ('SettingsDialog.SarvamBrowser.cs','FullWidthVoiceSearch(searchBox);'),
            ('SettingsDialog.Sarvam.cs','FullWidthVoiceSearch(search);'),
            ('PiperVoicesDialog.cs','SettingsDialog.FullWidthVoiceSearch(search);'),
            ('PiperDeleteVoicesDialog.cs','SettingsDialog.FullWidthVoiceSearch(search);'),
        ]:
            with self.subTest(path=path): self.mutated('Windows/Views/'+path,token,'','voice search must remain full width')

    def test_hidden_voice_controls_keep_their_logical_owner_cleanup(self):
        self.mutated('Windows/Views/SettingsDialog.cs','previousVoiceGroup.Children.Remove(piperControls)','','hidden voice groups')

    def test_mac_settings_cannot_drop_grouped_forms(self):
        self.mutated('Mac/SettingsView.swift', '.formStyle(.grouped)', '.formStyle(.columns)', 'grouped forms')
    def test_mac_import_cannot_drop_grouped_forms(self):
        self.mutated('Mac/ImportAssetsView.swift', '.formStyle(.grouped)', '.formStyle(.columns)', 'grouped forms')
    def test_mac_export_cannot_drop_grouped_forms(self):
        self.mutated('Mac/ExportOptionsMenu.swift', '.formStyle(.grouped)', '.formStyle(.columns)', 'grouped forms')
    def test_mac_key_and_timing_actions_cannot_stack(self):
        for file in ['GeminiAPISettingsView.swift','SarvamVoiceSettingsView.swift','ImportAssetsView.swift']:
            with self.subTest(file=file): self.mutated('Mac/'+file, 'HStack', 'VStack', 'horizontal row')
    def test_windows_forms_cannot_bypass_shared_layout(self):
        self.mutated('Windows/Views/WindowAppearance.cs', 'CompactDialogLayout.PrepareDialog(dialog);', '', 'shared presentation')
    def test_windows_wide_dialogs_cannot_inherit_the_narrow_style_cap(self):
        self.mutated('Windows/Views/WindowAppearance.cs', 'dialog.ReadLocalValue(FrameworkElement.MaxWidthProperty)', 'dialog.MaxWidth', 'native style defaults')
        self.mutated('Windows/Views/WindowAppearance.cs', 'LocalSize(dialog.Resources,"ContentDialogMaxWidth")', 'dialog.Resources["ContentDialogMaxWidth"]', 'global theme defaults')
    def test_windows_cards_cannot_use_a_fixed_light_background(self):
        self.mutated('Windows/Views/SettingsDialog.Compact.cs', 'ThemeResource CardBackgroundFillColorDefaultBrush', 'StaticResource LightBackground', 'follow light/dark')
    def test_windows_actions_cannot_drop_width_based_arrangement(self):
        self.mutated('Windows/Views/SettingsDialog.SpeechLayout.cs', 'Fits(finalSize.Width)', 'false', 'actual width')
    def test_windows_cannot_drop_native_alignment_assertions(self):
        self.mutated('Windows/MainWindow.DialogLayoutSmoke.cs', 'TransformToVisual(row)', 'TransformToVisual(dialog)', 'rendered field positions')
    def test_windows_cannot_drop_value_preservation_assertions(self):
        self.mutated('Windows/MainWindow.DialogLayoutSmoke.cs', 'picker.SelectedIndex!=1 || events!=0', 'false', 'values/events')
    def test_windows_cannot_remove_accessible_grouping(self):
        self.mutated('Windows/Views/SettingsDialog.Compact.cs', 'new AccessibilityGroup', 'new ContentControl', 'named UI Automation')
    def test_windows_cannot_remove_narrow_window_reflow(self):
        self.mutated('Windows/Views/SettingsDialog.Layout.cs', 'args.NewSize.Width < stackBelow', 'false', 'available width')

    def test_about_cannot_regain_standalone_shortcuts_or_extra_components(self):
        self.mutated('Mac/AboutSettingsView.swift', 'var body: some View {', 'var body: some View { Text("Keyboard shortcuts")', 'shortcuts in Help')
        self.mutated('Windows/Views/SettingsDialog.Information.cs', 'private void BuildAbout(StackPanel panel)\n    {', 'private void BuildAbout(StackPanel panel)\n    { CompactGroup(panel,"Other components");', 'Other components')

    def test_about_keeps_the_short_version_license_and_right_alignment(self):
        self.mutated('Windows/Views/SettingsDialog.Information.cs', '"Bundled version"', '"Diagnostic output"', 'shared information')
        self.mutated('Windows/Views/SettingsDialog.Information.cs', 'TextAlignment = TextAlignment.Right', 'TextAlignment = TextAlignment.Left', 'align to the right')

    def test_help_cannot_lose_the_shared_shortcut_reference(self):
        self.mutated('Mac/SettingsView.swift', 'Keyboard shortcut reference', 'Shortcuts', 'Help controls')
        self.mutated('Windows/Views/SettingsDialog.Information.cs', 'Keyboard shortcut reference', 'Shortcuts', 'Help controls')
        self.mutated('Mac/KeyboardShortcuts.swift', '.init(id: "jump-to-time", title: "Jump to Time…"', '.init(id: "jump-to-time", title: "Jump"', 'Jump to Time')
        self.mutated('Windows/Views/SettingsDialog.Information.cs', 'private bool shortcutReferenceExpanded = false;', 'private bool shortcutReferenceExpanded = true;', 'starts collapsed')

    def test_about_groups_and_license_menus_cannot_drift(self):
        self.mutated('Windows/Views/SettingsDialog.Information.cs', 'about-license-index', 'unmatched', 'matching menus')
        self.mutated('Windows/Views/SettingsDialog.Information.cs', 'group=CompactGroup(panel,"FFmpeg");', 'group=CompactGroup(panel,"FFmpeg"); group=CompactGroup(panel,"Extra");', 'hierarchy/order')

    def test_help_and_about_cannot_be_disabled_by_editor_processing(self):
        self.mutated('Windows/MainWindow.Menus.cs', 'if (id is "settings" or "help" or "about") return true;', '', 'available during editor processing')

    def test_live_help_destination_and_connection_message_match(self):
        for reader in ('Mac/StudioHelp.swift', 'Windows/Views/HelpWindow.xaml.cs'):
            with self.subTest(reader=reader):
                self.mutated(reader, 'https://vidistudio.varunmanojkumar.in/docs', 'welcome.html', 'shared website guide')
                self.mutated(reader, 'Documentation requires internet.', '', 'unavailable connection')

    def test_help_retry_available_on_both_desktops(self):
        for reader in ('Mac/StudioHelp.swift', 'Windows/Views/HelpWindow.xaml'):
            self.mutated(reader, '"Retry"', '"Reload"', 'must offer Retry')

    def test_opening_help_cannot_close_settings(self):
        self.mutated('Windows/Views/SettingsDialog.Information.cs', 'openHelp.Click += (_,_) => App.OpenHelpWindow', 'openHelp.Click += (_,_) => HideAndOpenHelpWindow', 'keep Settings open')

    def test_help_reference_expansion_survives_navigation(self):
        self.mutated('Windows/Views/SettingsDialog.Information.cs', 'IsExpanded = shortcutReferenceExpanded', 'IsExpanded = false', 'retain expansion')

    def test_help_button_cannot_drift_into_an_extra_labeled_row(self):
        self.mutated('Windows/Views/SettingsDialog.Information.cs', 'guide.Children.Add(openHelp);', 'CompactRow(guide,"VidiStudio Help",openHelp);', 'match Mac placement')
