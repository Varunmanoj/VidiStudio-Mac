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

    def test_summary_voice_follows_the_narration_provider(self):
        path = 'Windows/Views/SettingsDialog.cs'
        call = 'BuildAdditionalSpeechControls(panel);'
        self.mutated(path, call, '', 'Narration provider settings must precede Summary voice')
        changed = dict(self.source)
        changed[path] = changed[path].replace(call, '').replace(
            'var voiceGroup = AddNarrationGroup(panel, "Voices");',
            call + '\n        var voiceGroup = AddNarrationGroup(panel, "Voices");')
        with self.assertRaisesRegex(ValueError, 'Narration provider settings must precede Summary voice'):
            contract.validate(changed)

    def test_import_decision_cannot_lose_safe_default_or_scoped_menu(self):
        for path, token in (
            ('Mac/ImportDecision.swift', 'window.defaultButtonCell = okay.cell'),
            ('Mac/ImportDecision.swift', 'button.menu = menu'),
            ('Windows/MainWindow.ImportDecision.cs', 'DefaultButton = ContentDialogButton.Close'),
            ('Windows/MainWindow.ImportDecision.cs', 'dialog.ContextFlyout = actions'),
        ):
            self.mutated(path, token, 'REMOVED', 'import decisions must preserve safe defaults')

    def test_youtube_playback_controls(self):
        for path, marker in (
            ("Mac/GeneratedContentDeletionView.swift", '"delete-local-playback-video"'),
            ("Windows/MainWindow.LanguageResults.cs", '"delete-local-playback-video"'),
            ("Mac/GeneratedContentDeletionView.swift", '"delete-original-audio"'),
            ("Windows/MainWindow.LanguageResults.cs", '"delete-original-audio"'),
            ("Mac/ExportOptionsMenu.swift", "!project.hasVideoExportSource ? [.audio, .text]"),
            ("Windows/Views/ExportDialog.cs", "IsYouTube: true, HasVideoExportSource: false"),
            ('Mac/ImportAssetsView.swift', 'Section("Local playback video") { playbackVideoRow }'),
            ('Windows/Views/ImportAssetsDialog.cs', 'panel.Children.Insert(0, Section("Local playback video", row));'),
            ('Mac/YouTubeInspectorInformationView.swift', 'Button("Remove Local Playback Video…", systemImage: "trash")'),
            ('Windows/MainWindow.Menus.cs', 'group.IsEnabled = Model.Project is { } project && CanChangeYouTubePlayback(project);'),
            ('Mac/ImportAssetsView.swift', 'canChoose: project.allowsOriginalAudioImport && selection.localPlaybackVideo == nil'),
            ('Windows/Views/ImportAssetsDialog.cs', 'CanChoosePlaybackVideo => !hasSavedOriginalAudio && originalAudio == null'),
        ):
            with self.subTest(path=path):
                self.mutated(path, marker, '', 'YouTube account preview, playback, deletion and export controls')

    def test_project_settings_shares_youtube_and_deletion_controls(self):
        for path, marker in (
            ('Mac/ProjectSourcesSettingsView.swift', 'YouTubePlaybackVideoControls(studio: model, project: project, inProjectSettings: true)'),
            ('Mac/ProjectSourcesSettingsView.swift', 'YouTubeProjectLinkButtons(studio: model, project: project)'),
            ('Mac/ProjectSourcesSettingsView.swift', 'deleteContentButton(project).contextMenu { deleteContentButton(project) }'),
            ('Windows/Views/ProjectSourcesSettingsControl.cs', 'item.Click += async (_, _) => await RunAction("delete-content");'),
            ('Windows/Views/ProjectSourcesSettingsControl.cs', 'MainWindow.BuildYouTubeProjectLinks(project)'),
            ('Windows/Views/ProjectSourcesSettingsControl.cs', 'editor.BuildYouTubePlaybackControls(project, RunAction, inProjectSettings: true)'),
            ('Mac/ProjectSourcesSettingsView.swift', '.accessibilityValue(imported ? "Imported" : "")'),
            ('Windows/Views/ProjectSourcesSettingsControl.cs', 'AutomationProperties.SetHelpText(button, "Imported");'),
            ('Mac/YouTubeInspectorInformationView.swift', 'if showSource && (!inProjectSettings || project.youtubePlaybackVideo != nil || project.originalAudio != nil)'),
            ('Windows/MainWindow.YouTube.cs', 'var fileRow = !inProjectSettings || attachment != null || project.OriginalAudio != null'),
        ):
            with self.subTest(path=path):
                self.mutated(path, marker, '', 'Project Settings must preserve shared actions and imported assets')

    def test_inspector_language_stays_first_and_unique(self):
        self.mutated('Windows/MainWindow.LanguageResults.cs', 'panel.Children.Add(language);', '', 'must precede all actions')
        self.mutated('Mac/LanguageResults.swift', 'private var controls: some View {', 'private var controls: some View { /* Review language filter */', 'repeat language choices')
        self.mutated('Windows/Views/ImportAssetsDialog.cs', 'Content = panel;', 'Content = panel; /* languagePicker */', 'inherit the project language')
        self.mutated('Windows/MainWindow.Accessibility.cs', 'Shared inspector language must be accessible, bounded and above every action.', '', 'native inspector geometry')

    def test_overview_preserves_accessible_section_groups(self):
        self.mutated('Mac/ADOverviewView.swift', 'overviewGroup("Summary")', 'overviewGroup("Details")', 'Overview group')
        self.mutated('Windows/MainWindow.xaml', 'AutomationProperties.Name="Transcript" Background=', 'Background=', 'Overview group')

    def test_overview_summary_shows_only_metadata(self):
        mac = self.source['Mac/ADOverviewView.swift'].split('overviewGroup("Summary") {', 1)[1].split('\n                    }', 1)[0]
        self.assertEqual([line.split('"')[1] for line in mac.splitlines() if 'statistic(' in line],
                         ['Summary status', 'Summary characters'])
        self.assertNotIn('Text(', mac)
        windows = self.source['Windows/MainWindow.Presentation.cs'].split('OverviewSummary.Children.Clear();', 1)[1].split('AddInfo(OverviewStatistics', 1)[0]
        self.assertEqual([line.split('"')[1] for line in windows.splitlines() if 'AddInfo(OverviewSummary,' in line],
                         ['Summary status', 'Summary characters'])
        self.assertNotIn('Children.Add', windows)

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

    def test_open_editor_displays_cloud_download_progress(self):
        for path, token in (
            ('Mac/ContentView.swift', 'CloudImportProgressBanner()'),
            ('Windows/MainWindow.xaml.cs', 'CloudImportActivity.Current'),
            ('Windows/MainWindow.xaml.cs', 'Cloud video download progress'),
        ):
            with self.subTest(path=path, token=token):
                self.mutated(path, token, '', 'Open editors must display accessible Cloud Storage download progress')

    def test_external_projects_keep_all_projects_available(self):
        self.mutated('Mac/VidiStudioApp.swift', 'MainWindowLifetime(isLibrary: true)', 'MainWindowLifetime()', 'library window')
        self.mutated('Mac/VidiStudioApp.swift', 'func application(_ application: NSApplication, open urls: [URL])', '', 'must not promote the minimized library')
        self.mutated('Mac/VidiStudioApp.swift', 'andEventID: AEEventID(kAEGetURL)', '', 'must bypass the default reopen')
        self.mutated('Mac/ContentView.swift', 'appDelegate.takeSharedURLs().forEach(handleSharedURL)', '', 'forward queued and live external activations')
        self.mutated('Mac/ContentView.swift', 'AppWindowLifetime.returnToLibrary { openWindow(id: "studio") }', 'openWindow(id: "studio")', 'editor close must return')
        self.mutated('Windows/App.xaml.cs', 'var target = ProjectLibrary();', 'var target = window;', 'external activation must start')
        self.mutated('Windows/MainWindow.xaml.cs', 'App.OpenOrActivateEditor(folder)', 'ShowEditor()', 'separate editor')
        self.mutated('Windows/MainWindow.Menus.cs', 'if (wasEditor && windowClosed) App.ShowProjectLibrary();', '', 'editor close must return')

    def test_editor_maximize_does_not_change_library_window_state(self):
        for path, marker, expected in (
            ('Mac/VidiStudioApp.swift', 'context.defaultDisplay.visibleRect', 'editor must open maximized'),
            ('Windows/MainWindow.xaml.cs', 'presenter.Maximize();', 'editor must open maximized'),
            ('Mac/SettingsWindowChrome.swift', 'guard !libraryWindow.isMiniaturized else { return }', 'keep minimized All Projects'),
            ('Windows/App.xaml.cs', 'library.BringToForeground(restoreMinimized: false);', 'keep minimized All Projects'),
            ('Windows/MainWindow.xaml.cs', 'if (IsIconic(hWnd))', 'preserve maximized windows'),
            ('Windows/MainWindow.Presentation.cs', 'PrivateYouTubeChannel: null, ActiveLocalYouTubePlaybackPath: null', 'saved private projects must not require remote YouTube access'),
            ('Windows/MainWindow.xaml.cs', 'PrivateYouTubeAccessException => "Video Unavailable"', 'private-video recovery'),
        ):
            with self.subTest(path=path, marker=marker):
                self.mutated(path, marker, '', expected)

    def test_both_video_browsers_keep_checkbox_selection(self):
        self.mutated('Mac/ContentView.swift', 'VideoBrowserRowCheckbox(title: video.filename, id: video.id, selection: $videoID)', '',
                     'both video browsers need the shared checkbox selection')
        self.mutated('Mac/YouTubeViews.swift', 'VideoBrowserRowCheckbox(title: video.title, id: video.id, selection: $selectedVideoID)', '',
                     'both video browsers need the shared checkbox selection')
        for path in ('Windows/Views/CloudVideosDialog.cs', 'Windows/MainWindow.YouTube.cs'):
            self.mutated(path, 'videoSelection.ModeItem(', '', 'both video browsers need the shared checkbox selection')

    def test_double_click_respects_video_selection_mode(self):
        for path, token in (
            ('Mac/ContentView.swift', 'guard !selectingVideos, selection.count == 1,'),
            ('Mac/YouTubeViews.swift', 'guard !selectingVideos, selection.count == 1,'),
            ('Windows/Views/CloudVideosDialog.cs', 'videoSelection.AddPrimaryAction(OpenSelectedVideoAsync)'),
            ('Windows/MainWindow.YouTube.cs', 'videoSelection.AddPrimaryAction('),
            ('Windows/Views/VideoBrowserSelection.cs', 'if (Enabled || !list.IsEnabled) return;'),
        ):
            self.mutated(path, token, '', 'double-click must run the selected video action only outside Select mode')

    def test_loading_indicators_stay_in_the_video_results(self):
        self.mutated('Mac/ContentView.swift', 'if let listingMessage { VideoBrowserLoadingIndicator(message: listingMessage) }', '',
                     'browser results need centered loading progress')
        self.mutated('Mac/YouTubeViews.swift', 'if loading { VideoBrowserLoadingIndicator(message: loadingMessage) }', '',
                     'browser results need centered loading progress')
        self.mutated('Windows/Views/CloudVideosDialog.cs', 'results.Children.Add(centeredLoading)', '',
                     'browser results need centered loading progress')
        self.mutated('Windows/MainWindow.YouTube.cs', 'results.Children.Add(loadingRow)', '',
                     'browser results need centered loading progress')

    def test_signed_out_cloud_browser_opens_with_cloud_sign_in(self):
        for path, token in (
            ('Mac/ContentView.swift', 'else { signedOutBrowser }'),
            ('Windows/Views/CloudVideosDialog.cs', 'signedOutBrowser.Visibility = connected ? Visibility.Collapsed : Visibility.Visible;'),
        ):
            self.mutated(path, token, '', 'the signed-out Cloud browser must open and offer Cloud sign-in')

    def test_cloud_browser_matches_youtube_layout_and_thumbnail_table(self):
        for path, token in (
            ('Mac/ContentView.swift', 'TableColumn("Thumbnail")'),
            ('Windows/Views/CloudVideosDialog.cs', 'videoScroll.HorizontalScrollMode'),
            ('Windows/Views/CloudVideosDialog.cs', 'CompactActions(actions, openEditor, cancel)'),
        ):
            with self.subTest(path=path, token=token):
                self.mutated(path, token, '', 'the Cloud browser must match the YouTube browser layout')

    def test_youtube_account_controls_coexist_with_link_metadata(self):
        for path, token in (
            ('Mac/SettingsView.swift', 'YouTubeAccountsView()'),
            ('Windows/Views/SettingsDialog.cs', 'new YouTubeAccountsPanel(this)'),
            ('Mac/VidiStudioApp.swift', 'Window("My YouTube Videos", id: "youtube-browser")'),
            ('Windows/MainWindow.YouTube.cs', 'ShowYouTubeBrowserAsync'),
        ):
            with self.subTest(path=path):
                self.mutated(path, token, '', 'YouTube account, browser or caption control is missing')
        self.mutated('Mac/YouTubeProjectPreview.swift', 'YouTubeService.shared.videoForNewProject(', 'missing(', 'must retain metadata lookup')
        self.mutated('Windows/Views/NewProjectDialog.cs', 'FetchYouTubeDetailsAsync(YouTubeService.Shared.VideoForNewProjectAsync)', 'missing', 'must retain metadata lookup')
        self.mutated('Mac/YouTubeInspectorInformationView.swift', 'YouTubeService.shared.refreshedProjectVideo(', 'missing(', 'must retain metadata lookup')
        self.mutated('Windows/MainWindow.YouTube.cs', 'YouTubeService.Shared.RefreshedProjectVideoAsync(', 'missing(', 'must retain metadata lookup')

    def test_youtube_link_preview_requires_visibility_and_private_owner_guard(self):
        for path, token in (
            ('Mac/ContentView.swift', 'Visibility: \\(youtubePreview.video.visibility.capitalized)'),
            ('Mac/ContentView.swift', 'YouTubeService.shared.privateConnection(video.channelID, settings: studio.settings) != nil'),
            ('Windows/Views/NewProjectDialog.cs', '"Visibility: " + '),
            ('Windows/Views/NewProjectDialog.cs', 'sourceReady &= YouTubeService.Shared.PrivateConnection(video.ChannelId, settings) != null;'),
        ):
            with self.subTest(path=path, token=token):
                self.mutated(path, token, '', 'pasted YouTube links must show visibility and gate private project creation')

    def test_cloud_and_youtube_settings_use_separate_sign_in_actions(self):
        workspace = Path(os.environ.get('VIDISTUDIO_DESKTOP_WORKSPACE', ROOT.parent))
        mac = workspace / 'VidiStudio Mac' / 'VidiStudio'
        windows = workspace / 'Vidi-Studio-Windows' / 'Vidi Studio Windows'
        for settings, accounts, service, cloud_call, youtube_call, cloud_remove, youtube_remove in (
            (mac / 'GeminiAPISettingsView.swift', mac / 'YouTubeViews.swift', mac / 'YouTubeService.swift',
             'signInToCloud()', 'signIn()', 'disconnectCloudAccount()', 'private func removeYouTubeAccount'),
            (windows / 'Views/SettingsDialog.Gemini.cs', windows / 'Views/YouTubeAccountsPanel.cs',
             windows / 'Services/YouTubeService.cs', 'SignInToCloudAsync(', 'SignInAsync(',
             'DisconnectCloudAccountAsync()', 'private void RemoveYouTubeAccount'),
        ):
            with self.subTest(platform=settings.parent):
                self.assertIn(cloud_call, settings.read_text(encoding='utf-8'))
                self.assertIn(youtube_call, accounts.read_text(encoding='utf-8'))
                self.assertNotIn(cloud_call, accounts.read_text(encoding='utf-8'))
                service_text = service.read_text(encoding='utf-8')
                self.assertNotIn('oauth2.googleapis.com/revoke', service_text)
                youtube_section = service_text.split(youtube_remove, 1)[1].split(cloud_remove, 1)[0]
                self.assertNotIn('updateCloudCredential', youtube_section)
                self.assertNotIn('UpdateCloudCredentialAsync', youtube_section)

    def test_youtube_picker_returns_to_new_project(self):
        self.mutated('Mac/ContentView.swift', 'youtubeURL = preview.canonicalURL', '',
                     'the YouTube picker must return its video to the open New Project form')
        self.mutated('Windows/Views/NewProjectDialog.cs', 'youtubeUrl.Text = result.Video.Url', '',
                     'the YouTube picker must return its video to the open New Project form')

    def test_video_tables_have_leading_selection_and_row_actions(self):
        self.mutated('Mac/YouTubeViews.swift', 'TableColumn("Select")', 'TableColumn("Wrong")',
                     'selection must precede the thumbnail')
        self.mutated('Windows/Views/CloudVideosDialog.cs', 'videoSelection.AddRowActions(', 'missing(',
                     'video tables need per-row Actions')
        self.mutated('Mac/ContentView.swift', 'TableColumn("Actions")', 'TableColumn("Wrong")',
                     'video tables need per-row Actions')
        self.mutated('Windows/MainWindow.YouTube.cs', '"Captions", "Actions" };', '"Actions", "Captions" };',
                     'Actions must be the last video table column')

    def test_new_project_youtube_error_presentation(self):
        self.mutated('Mac/ContentView.swift', 'Image(systemName: "xmark.circle.fill")',
                     'Image(systemName: "exclamationmark.triangle.fill")',
                     'New Project YouTube errors need a red cross')
        self.mutated('Windows/Views/NewProjectDialog.cs', 'SystemFillColorCriticalBrush', 'TextFillColorSecondaryBrush',
                     'New Project YouTube errors need a red cross')

    def test_new_project_preserves_title_inset_in_taller_modes(self):
        self.mutated('Mac/ContentView.swift', 'maxHeight: preferredHeight, alignment: .topLeading',
                     'maxHeight: preferredHeight', 'New Project must keep its title inset')

    def test_gallery_filter_dialog(self):
        self.mutated('Mac/ProjectBrowserPage.swift', 'aiProviderFilter: $aiProviderFilter', '',
                     'All Projects must stage filters in an accessible dialog')
        self.mutated('Windows/MainWindow.xaml', 'x:Name="GalleryFilterProjects"', '',
                     'All Projects must stage filters in an accessible dialog')

    def test_cloud_sources_are_visible_but_disabled_before_sign_in(self):
        for path, token in (
            ('Mac/ContentView.swift', 'sourcePicker([.cloud], selection: .constant(.videoFile))\n                                .disabled(true)'),
            ('Windows/Views/NewProjectDialog.cs', 'cloud.IsEnabled = settings.GetBool("vertexConnected");'),
            ('Windows/Views/NewProjectDialog.cs', 'sourceOptions.Children.Add(cloud);'),
            ('Windows/MainWindow.Menus.cs', 'if (id is "new-project" or "new-youtube-project" or "new-cloud-project") return true;'),
        ):
            with self.subTest(path=path, token=token):
                self.mutated(path, token, '', 'Cloud project controls must stay visible and disabled')

    def test_gallery_toolbar_has_no_separate_cloud_creation_action(self):
        for path, token in (
            ('Mac/ProjectBrowserPage.swift', 'Button("New Project", systemImage: "plus", action: newProject)'),
            ('Windows/MainWindow.xaml', 'AutomationProperties.Name="New Project"'),
        ):
            with self.subTest(path=path):
                self.mutated(path, token, token.replace("New Project", "New Cloud Project"),
                             'toolbar must use one New Project action')

    def test_windows_new_project_does_not_fit_again_after_source_changes(self):
        self.mutated('Windows/Views/WindowAppearance.cs', 'if (keepsSize || disposed || observing) return;',
                     'if (disposed || observing) return;', 'New Project must use fixed bounds')

    def test_windows_new_project_source_picker_stays_above_scrolling_form(self):
        self.mutated('Windows/Views/NewProjectDialog.cs', 'Grid.SetRow(sourceCard, 1); layout.Children.Add(sourceCard);',
                     'contents.Children.Add(sourceCard);', 'New Project must use fixed bounds')

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
