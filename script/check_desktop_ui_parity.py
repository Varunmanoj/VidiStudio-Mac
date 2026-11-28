#!/usr/bin/env python3
"""Architecture guards for paired desktop forms; native geometry remains a separate required check."""
import argparse
import re
from pathlib import Path

MAC_FILES = ('ADOverviewView.swift', 'StudioHelp.swift', 'CreatedExportsView.swift', 'LanguageResults.swift', 'ContentView.swift', 'SettingsView.swift', 'ImportAssetsView.swift', 'ImportDecision.swift', 'ExportOptionsMenu.swift',
             'GeminiAPISettingsView.swift', 'SarvamVoiceSettingsView.swift', 'SystemVoiceCatalog.swift', 'PiperVoiceCatalog.swift', 'GeminiVoicePreview.swift', 'SarvamVoiceBrowser.swift', 'VoiceSampleSession.swift', 'AboutSettingsView.swift', 'KeyboardShortcuts.swift', 'ProjectBrowserPage.swift',
             'ProjectSourcesSettingsView.swift', 'ProjectFilterSheet.swift', 'YouTubeViews.swift', 'YouTubeProjectPreview.swift', 'YouTubeInspectorInformationView.swift', 'GeneratedContentDeletionView.swift', 'VidiStudioApp.swift', 'SettingsWindowChrome.swift')
WIN_FILES = ('Views/SettingsDialog.Gemini.cs', 'Views/SettingsDialog.GeminiVoices.cs', 'Views/HelpWindow.xaml', 'Views/HelpWindow.xaml.cs', 'MainWindow.Presentation.cs', 'MainWindow.LanguageResults.cs', 'Views/ImportAssetsDialog.cs', 'MainWindow.ImportDecision.cs', 'MainWindow.Accessibility.cs', 'MainWindow.xaml', 'Views/CompactDialogLayout.cs', 'Views/WindowAppearance.cs',
             'Views/SettingsDialog.Compact.cs', 'Views/SettingsDialog.Layout.cs',
             'Views/SettingsDialog.ElevenLabs.cs', 'Views/SettingsDialog.SarvamBrowser.cs', 'Views/SettingsDialog.SpeechLayout.cs', 'MainWindow.DialogLayoutSmoke.cs', 'Views/SettingsDialog.cs', 'Views/SettingsDialog.Sarvam.cs', 'Views/PiperVoicesDialog.cs', 'Views/PiperDeleteVoicesDialog.cs', 'Services/VoiceSampleSession.cs', 'Views/SettingsDialog.Information.cs', 'MainWindow.Menus.cs',
             'Views/ProgressOverlay.xaml.cs', 'Views/ProgressOverlay.xaml', 'Views/NewProjectDialog.cs', 'Views/CloudVideosDialog.cs', 'Views/VideoBrowserSelection.cs', 'Views/ProjectSourcesSettingsControl.cs', 'MainWindow.YouTube.cs', 'MainWindow.xaml.cs', 'App.xaml.cs', 'Views/ExportDialog.cs')

def sources(workspace):
    workspace = Path(workspace)
    result = {}
    for platform, folder, source_dir, paths in (
        ('Mac', 'VidiStudio Mac', 'VidiStudio', MAC_FILES),
        ('Windows', 'Vidi-Studio-Windows', 'Vidi Studio Windows', WIN_FILES)):
        for path in paths:
            result[platform + '/' + path] = (workspace / folder / source_dir / path).read_text(encoding='utf-8')
    return result

def swift_blocks(text, name):
    # Match the enclosing layout, not a context-menu copy of the same button title.
    for match in re.finditer(r'\b' + name + r'(?:\([^\n]*?\))?\s*\{', text):
        start = match.end(); depth = 1; quoted = False; escaped = False
        for index in range(start, len(text)):
            char = text[index]
            if quoted:
                if escaped: escaped = False
                elif char == '\\': escaped = True
                elif char == '"': quoted = False
            elif char == '"': quoted = True
            elif char == '{': depth += 1
            elif char == '}':
                depth -= 1
                if not depth:
                    yield text[start:index]
                    break

def validate(source):
    def require(path, token, reason):
        if token not in source[path]: raise ValueError(path + ': ' + reason)

    headings = ('Project details', 'Transcript', 'Summary', 'Audio description details', 'Description origins', 'Create narration audio')
    for path, markers in (
        ('Mac/ADOverviewView.swift', [f'overviewGroup("{title}")' for title in headings[:4]] +
            [f'.accessibilityGroup("{title}")' for title in headings[4:]]),
        ('Windows/MainWindow.xaml', [f'AutomationProperties.Name="{title}"' for title in headings]),
    ):
        section = source[path].split('x:Name="OverviewPanel"', 1)[-1]
        last = -1
        for marker in markers:
            position = section.find(marker, last + 1)
            if position < 0: raise ValueError(path + ': missing or misplaced Overview group ' + marker)
            last = position

    for path in ('Mac/ADOverviewView.swift', 'Windows/MainWindow.Presentation.cs'):
        require(path, '"Summary status"', 'Overview must show summary availability')
        require(path, '"Summary characters"', 'Overview must show summary length')

    for path, marker in (
        ('Mac/ContentView.swift', 'ProgressView(message)'),
        ('Windows/MainWindow.xaml', 'x:Name="SharedVideoRing"'),
        ('Mac/ContentView.swift', '"shared-file-opening"'),
        ('Windows/MainWindow.xaml.cs', '"shared-file-opening"'),
        ('Mac/ContentView.swift', '"shared-youtube-opening"'),
        ('Windows/MainWindow.xaml.cs', '"shared-youtube-opening"'),
    ):
        require(path, marker, 'shared project progress must cover video files and YouTube links')
    for title in ('Copy ', 'Clear ', 'Google account connected', 'Remove Google sign-in', 'Google Cloud project ID', 'Cloud Storage bucket', 'vertex-signin-status', 'vertex-test-status', 'Vertex AI connection verified'):
        require('Mac/GeminiAPISettingsView.swift', title, 'Cloud connection field or sign-in action is missing')
        require('Windows/Views/SettingsDialog.Gemini.cs', title, 'Cloud connection field or sign-in action is missing')
    for path in ('Mac/GeminiAPISettingsView.swift', 'Windows/Views/SettingsDialog.Gemini.cs'):
        for token in ('Gemini 4', 'vertexModelPolicy', 'vertex-model-', 'Unavailable in express mode', 'No compatible models',
                      'SignInOnly' if path.startswith('Windows/') else 'signInOnly',
                      'ProjectModelGroups' if path.startswith('Windows/') else 'projectModelGroups'):
            require(path, token, 'Vertex pickers must use the shared capability rules and identify empty choices')
    require('Mac/VidiStudioApp.swift', 'MainWindowLifetime(isLibrary: true)', 'All Projects must register as the library window')
    require('Mac/VidiStudioApp.swift', 'func application(_ application: NSApplication, open urls: [URL])', 'external activation must not promote the minimized library scene')
    require('Mac/VidiStudioApp.swift', 'andEventID: AEEventID(kAEGetURL)', 'project URLs must bypass the default reopen of minimized All Projects')
    require('Mac/ContentView.swift', 'appDelegate.takeSharedURLs().forEach(handleSharedURL)', 'the library must forward queued and live external activations')
    require('Mac/ContentView.swift', 'AppWindowLifetime.returnToLibrary { openWindow(id: "studio") }', 'editor close must return to All Projects')
    require('Windows/App.xaml.cs', 'var target = ProjectLibrary();', 'external activation must start in All Projects')
    require('Windows/MainWindow.xaml.cs', 'App.OpenOrActivateEditor(folder)', 'external activation must open a separate editor')
    require('Windows/MainWindow.Menus.cs', 'if (wasEditor && windowClosed) App.ShowProjectLibrary();', 'editor close must return to All Projects')
    require('Mac/ContentView.swift', 'geometry.size.height - 180 - dividerHeight', 'reserve height for the active editor section')
    require('Windows/MainWindow.xaml', '<RowDefinition x:Name="PreviewRow" Height="2*" MaxHeight="320"/>', 'share available height between preview and section content')
    require('Windows/MainWindow.xaml.cs', 'PreviewRow.Height = showPreview && !besideTimeline ?', 'return preview space to the active section when hidden')
    editor_scene = source['Mac/VidiStudioApp.swift'].split('id: "project-editor"', 1)[1].split('Window("My YouTube Videos"', 1)[0]
    if '.defaultWindowPlacement' not in editor_scene or 'context.defaultDisplay.visibleRect' not in editor_scene:
        raise ValueError('Mac editor must open maximized within the usable display')
    require('Windows/MainWindow.xaml.cs', 'presenter.Maximize();', 'Windows editor must open maximized')
    require('Mac/SettingsWindowChrome.swift', 'guard !libraryWindow.isMiniaturized else { return }', 'keep minimized All Projects minimized')
    require('Windows/App.xaml.cs', 'library.BringToForeground(restoreMinimized: false);', 'keep minimized All Projects minimized')
    require('Windows/MainWindow.xaml.cs', 'if (IsIconic(hWnd))', 'foreground activation must preserve maximized windows')
    require('Windows/MainWindow.Presentation.cs', 'PrivateYouTubeChannel: null, ActiveLocalYouTubePlaybackPath: null', 'opening saved private projects must not require remote YouTube access')
    require('Windows/MainWindow.xaml.cs', 'PrivateYouTubeAccessException => "Video Unavailable"', 'private-video recovery must show an unsupported-video notice')
    for path, token in (
        ('Mac/SettingsView.swift', 'YouTubeAccountsView()'),
        ('Windows/Views/SettingsDialog.cs', 'new YouTubeAccountsPanel(this)'),
        ('Mac/VidiStudioApp.swift', 'Window("My YouTube Videos", id: "youtube-browser")'),
        ('Windows/MainWindow.YouTube.cs', 'ShowYouTubeBrowserAsync'),
        ('Mac/ContentView.swift', 'Choose YouTube captions after creating'),
        ('Windows/Views/NewProjectDialog.cs', 'Choose YouTube captions after creating'),
    ):
        require(path, token, 'YouTube account, browser or caption control is missing')
    for path, token in (
        ("Mac/ContentView.swift", 'label: "Connected account"'),
        ("Windows/Views/NewProjectDialog.cs", '"Connected account: "'),
        ("Mac/YouTubeInspectorInformationView.swift", '"Replace Local Playback Video…" : "Choose Local Playback Video…"'),
        ("Windows/MainWindow.xaml", 'x:Name="ChoosePrivatePlaybackVideo"'),
        ("Mac/GeneratedContentDeletionView.swift", '"delete-local-playback-video"'),
        ("Windows/MainWindow.LanguageResults.cs", '"delete-local-playback-video"'),
        ("Mac/GeneratedContentDeletionView.swift", '"delete-original-audio"'),
        ("Windows/MainWindow.LanguageResults.cs", '"delete-original-audio"'),
        ("Mac/GeneratedContentDeletionView.swift", '.disabled(filename == nil)'),
        ("Windows/MainWindow.LanguageResults.cs", 'IsEnabled = filename != null'),
        ("Mac/ExportOptionsMenu.swift", "!project.hasVideoExportSource ? [.audio, .text]"),
        ("Windows/Views/ExportDialog.cs", "IsYouTube: true, HasVideoExportSource: false"),
        ('Mac/KeyboardShortcuts.swift', 'Menu("Video Player", systemImage: "play.rectangle")'),
        ('Mac/KeyboardShortcuts.swift', '.disabled(editor?.canRun("use-local-video-player") != true)'),
        ('Windows/MainWindow.Menus.cs', 'group.IsEnabled = Model.Project is { } project && CanChangeYouTubePlayback(project);'),
        ('Windows/MainWindow.Menus.cs', 'Submenu("Video Player", Command("use-youtube-player"), Command("use-local-video-player"), Separator(), Command("choose-playback-video"), Command("remove-playback-video"))'),
        ('Mac/YouTubeInspectorInformationView.swift', 'Button("Remove Local Playback Video…", systemImage: "trash")'),
        ('Windows/MainWindow.YouTube.cs', 'button.Content = MenuIcons.Create(id);'),
        ('Mac/ImportAssetsView.swift', 'Section("Local playback video") { playbackVideoRow }'),
        ('Windows/Views/ImportAssetsDialog.cs', 'panel.Children.Insert(0, Section("Local playback video", row));'),
        ('Mac/ImportAssetsView.swift', 'canChoose: project.allowsOriginalAudioImport && selection.localPlaybackVideo == nil'),
        ('Mac/ImportAssetsView.swift', '.disabled(!studio.canChooseYouTubePlaybackVideo(project) || selection.originalAudio != nil)'),
        ('Windows/Views/ImportAssetsDialog.cs', 'CanChooseOriginalAudio => !hasSavedPlaybackVideo && localPlaybackVideo == null'),
        ('Windows/Views/ImportAssetsDialog.cs', 'CanChoosePlaybackVideo => !hasSavedOriginalAudio && originalAudio == null'),
    ):
        require(path, token, 'YouTube account preview, playback, deletion and export controls must stay aligned')
    for path, token in (
        ('Mac/ContentView.swift', 'VideoBrowserRowCheckbox(title: video.filename, id: video.id, selection: $videoID)'),
        ('Mac/YouTubeViews.swift', 'VideoBrowserRowCheckbox(title: video.title, id: video.id, selection: $selectedVideoID)'),
        ('Windows/Views/CloudVideosDialog.cs', 'videoSelection.ModeItem('),
        ('Windows/MainWindow.YouTube.cs', 'videoSelection.ModeItem('),
    ):
        require(path, token, 'both video browsers need the shared checkbox selection')
    for path, token in (
        ('Mac/ContentView.swift', 'guard !selectingVideos, selection.count == 1,'),
        ('Mac/YouTubeViews.swift', 'guard !selectingVideos, selection.count == 1,'),
        ('Windows/Views/CloudVideosDialog.cs', 'videoSelection.AddPrimaryAction(OpenSelectedVideoAsync)'),
        ('Windows/MainWindow.YouTube.cs', 'videoSelection.AddPrimaryAction('),
        ('Windows/Views/VideoBrowserSelection.cs', 'list.AddHandler(UIElement.DoubleTappedEvent'),
        ('Windows/Views/VideoBrowserSelection.cs', 'if (Enabled || !list.IsEnabled) return;'),
        ('Windows/Views/VideoBrowserSelection.cs', 'ReferenceEquals(list.SelectedItem, target)'),
    ):
        require(path, token, 'double-click must run the selected video action only outside Select mode')
    for path, token in (
        ('Mac/ContentView.swift', 'if let listingMessage { VideoBrowserLoadingIndicator(message: listingMessage) }'),
        ('Mac/YouTubeViews.swift', 'if loading { VideoBrowserLoadingIndicator(message: loadingMessage) }'),
        ('Windows/Views/CloudVideosDialog.cs', 'results.Children.Add(centeredLoading)'),
        ('Windows/MainWindow.YouTube.cs', 'results.Children.Add(loadingRow)'),
    ):
        require(path, token, 'browser results need centered loading progress')
    for path, token in (
        ('Mac/ContentView.swift', '.sheet(isPresented: $showingYouTubePicker, onDismiss:'),
        ('Mac/ContentView.swift', 'youtubeURL = preview.canonicalURL'),
        ('Windows/Views/NewProjectDialog.cs', 'await browse(window) is { } result'),
        ('Windows/Views/NewProjectDialog.cs', 'youtubeUrl.Text = result.Video.Url'),
        ('Windows/MainWindow.xaml.cs', 'BrowseYouTubeVideo = owner => ShowYouTubeBrowserAsync(owner)'),
    ):
        require(path, token, 'the YouTube picker must return its video to the open New Project form')
    new_project = source['Mac/ContentView.swift'].split('private struct NewProjectView:', 1)[1].split('final class SharedVideoProgressPanel', 1)[0]
    for path, token in (
        ('Mac/ContentView.swift', 'CloudVideosView(studio: studio, selectConfiguredBucket: true)'),
        ('Mac/ContentView.swift', 'ProgressView(studio.message, value: studio.progress)'),
        ('Windows/Views/NewProjectDialog.cs', 'ImportedCloudProject = await browse(window, LibraryPath);'),
        ('Windows/Views/CloudVideosDialog.cs', 'buckets.SelectedItem = configured;'),
        ('Windows/Views/CloudVideosDialog.cs', 'UpdateImportProgress'),
        ('Windows/MainWindow.xaml.cs', 'if (dialog.ImportedCloudProject is { } cloudProject)'),
    ):
        require(path, token, 'New Project must use the shared Cloud browser and show import progress')
    for path, token in (
        ('Mac/ContentView.swift', 'CloudImportProgressBanner()'),
        ('Windows/MainWindow.xaml.cs', 'CloudImportActivity.Current'),
        ('Windows/MainWindow.xaml.cs', 'Cloud video download progress'),
    ):
        require(path, token, 'Open editors must display accessible Cloud Storage download progress')
    if 'Source bucket' in new_project or 'private readonly ListView bucketVideo' in source['Windows/Views/NewProjectDialog.cs']:
        raise ValueError('The New Project form must not contain an inline Cloud bucket browser')
    if not all(token in new_project for token in ('.accessibilityIdentifier("new-project-title")',
            '.fixedSize(horizontal: false, vertical: true)', '.frame(minHeight: 0, maxHeight: .infinity)',
            'maxHeight: preferredHeight, alignment: .topLeading')):
        raise ValueError('New Project must keep its title inset while the form shrinks and scrolls')
    for path, token in (
        ('Mac/ContentView.swift', 'sourcePicker([.cloud], selection: .constant(.videoFile))\n                                .disabled(true)'),
        ('Mac/VidiStudioApp.swift', '.disabled(!studio.canBeginNewProject || !studio.settings.vertexConnected)'),
        ('Windows/Views/NewProjectDialog.cs', 'sourceOptions.Children.Add(cloud);'),
        ('Windows/Views/NewProjectDialog.cs', 'cloud.IsEnabled = settings.GetBool("vertexConnected");'),
        ('Windows/MainWindow.Menus.cs', 'if (id is "new-project" or "new-youtube-project" or "new-cloud-project") return true;'),
        ('Windows/MainWindow.Menus.cs', 'if (id == "new-cloud-project") return Model.Settings.GetBool("vertexConnected");'),
    ):
        require(path, token, 'Cloud project controls must stay visible and disabled before Google sign-in')
    for path, start, end in (
        ('Mac/ProjectBrowserPage.swift', '.toolbar {', '.safeAreaInset(edge: .bottom)'),
        ('Windows/MainWindow.xaml', 'x:Name="GalleryToolbarActions"', '</StackPanel>'),
    ):
        toolbar = source[path].split(start, 1)[1].split(end, 1)[0]
        if 'New Cloud Project' in toolbar:
            raise ValueError(path + ': the gallery toolbar must use one New Project action')
    for path, tokens in (
        ('Mac/ProjectBrowserPage.swift', ('Button("Filter Projects", systemImage:',
                                           'actions.run("projects-filter-dialog")', 'aiProviderFilter: $aiProviderFilter',
                                           'ProjectFilterSheet(source: sourceFilter', 'SavedAIProvider.projectFilterOptions(projects)',
                                           'aiProviderOptions: aiProviderOptions')),
        ('Mac/ProjectFilterSheet.swift', ('onFilter(source, language, provider, sort)', '.keyboardShortcut(.cancelAction)',
                                         '.keyboardShortcut(.defaultAction)', '.contextMenu', 'Picker("Sort by", selection: $sort)',
                                         'ForEach(aiProviderOptions')),
        ('Windows/MainWindow.xaml', ('x:Name="GalleryFilterProjects"', 'Click="GalleryFilterProjects_Click"')),
        ('Windows/MainWindow.Presentation.cs', ('ShowProjectFiltersAsync()', 'CompactDialogLayout.Card(fields, "Project filters")',
                                                'result == ContentDialogResult.Primary', 'ApplyGalleryFilters(selectedSource.Id',
                                                'Picker("Sort by", sortOptions, Model.ProjectSort)',
                                                'providerOptions = Model.ProjectFilterAIProviders')),
    ):
        for token in tokens:
            require(path, token, 'All Projects must stage filters in an accessible dialog')
    for path, token in (
        ('Windows/Views/NewProjectDialog.cs', 'Grid.SetRow(sourceCard, 1); layout.Children.Add(sourceCard);'),
        ('Windows/Views/NewProjectDialog.cs', 'Grid.SetRow(form, 2); layout.Children.Add(form);'),
        ('Windows/Views/WindowAppearance.cs', 'keepsSize = dialog is NewProjectDialog;'),
        ('Windows/Views/WindowAppearance.cs', 'if (keepsSize || disposed || observing) return;'),
        ('Windows/MainWindow.xaml.cs', 'ShowDialogAsync(dialog, Views.NewProjectDialog.WindowWidth, Views.NewProjectDialog.WindowHeight);'),
    ):
        require(path, token, 'Windows New Project must use fixed bounds across sources')
    for path, token in (
        ('Mac/ContentView.swift', 'libraryStudio.newProjectPresentation(for: windowOwner)'),
        ('Mac/ContentView.swift', 'studio.pickLocalVideo(attachedTo: sheet)'),
        ('Mac/ContentView.swift', 'Button(chooseVideoTitle, systemImage: "folder", action: chooseVideo)'),
        ('Windows/Views/NewProjectDialog.cs', 'FileOpenPicker(pickerOwner.AppWindow.Id)'),
        ('Windows/Views/NewProjectDialog.cs', 'AutomationProperties.SetName(control, label);'),
        ('Windows/Views/NewProjectDialog.cs', 'chooseVideo.Focus(FocusState.Programmatic);'),
        ('Windows/Views/NewProjectDialog.cs', 'chooseVideoItem.Click += async (_, _) => await ChooseVideoAsync();'),
    ):
        require(path, token, 'New Project must keep the native file picker owned and accessible')
    for path, token in (
        ('Mac/ContentView.swift', 'announceProcessingStart(studio, suppress: openProjects.sharedVideoOpening != nil)'),
        ('Mac/ContentView.swift', '.announceProcessingStart(studio, usesGenerationIndicator: true)'),
        ('Mac/ContentView.swift', '.modifier(GenerationProcessingAccessibility(studio: studio))'),
        ('Mac/ContentView.swift', 'content.task(id: appearsActive ? studio.generationAnnouncementStage : nil)'),
        ('Windows/MainWindow.xaml.cs', 'Model.TakeGenerationAnnouncement() is not { } message'),
        ('Windows/MainWindow.xaml.cs', 'AutomationNotificationProcessing.ImportantAll, message, "generation-processing"'),
        ('Windows/MainWindow.xaml.cs', 'StatusRing.Visibility != Visibility.Visible'),
        ('Windows/Views/ProgressOverlay.xaml.cs', 'peer.RaiseNotificationEvent(AutomationNotificationKind.Other,'),
        ('Windows/Views/ProgressOverlay.xaml.cs', 'GetForegroundWindow() != WinRT.Interop.WindowNative.GetWindowHandle(window)'),
        ('Windows/Views/ProgressOverlay.xaml.cs', 'model.HasAnnouncedProcessing = true;'),
        ('Windows/Views/ProgressOverlay.xaml', 'AutomationProperties.AutomationId="ProcessingStatus"'),
    ):
        require(path, token, 'Processing must be announced where it appears without moving focus')
    for path in ('Mac/ContentView.swift', 'Windows/Views/CloudVideosDialog.cs'):
        for token in ('Open Cloud Videos', 'Google Cloud project', 'Source bucket', 'Search videos',
                      'Recently Modified', 'Largest First', 'Open in Editor', 'Load Thumbnail', 'Rename Video…', 'Delete Video…'):
            require(path, token, 'the dedicated Cloud browser must support browsing and video actions')
    for path, tokens in (
        ('Mac/ContentView.swift', ('Picker("Video layout"', 'Text("List View")', 'Text("Table View")', 'TableColumn("Thumbnail")')),
        ('Windows/Views/CloudVideosDialog.cs', ('Content = "List View"', 'Content = "Table View"', "Text='Thumbnail'",
                                              'CompactActions(actions, openEditor, cancel)', 'videoScroll.HorizontalScrollMode')),
    ):
        for token in tokens:
            require(path, token, 'the Cloud browser must match the YouTube browser layout and thumbnail table')
    for path in ('Mac/ContentView.swift', 'Mac/YouTubeViews.swift'):
        view = source[path]
        if not 0 <= view.find('TableColumn("Select")') < view.find('TableColumn("Thumbnail")'):
            raise ValueError(path + ': video table selection must precede the thumbnail')
        require(path, 'TableColumn("Actions")', 'video tables need per-row Actions')
        if re.findall(r'TableColumn\("([^"]+)"', view)[-1] != 'Actions':
            raise ValueError(path + ': Actions must be the last video table column')
        if 'Label("Select Video"' in view:
            raise ValueError(path + ': video row menus must use one Select option')
    for path in ('Windows/MainWindow.YouTube.cs', 'Windows/Views/CloudVideosDialog.cs'):
        require(path, 'videoSelection.AddRowActions(', 'video tables need per-row Actions')
        if 'videoSelection.TargetItem(' in source[path]:
            raise ValueError(path + ': video row menus must use one Select option')
    for path, token in (
        ('Windows/MainWindow.YouTube.cs', '"Captions", "Actions" };'),
        ('Windows/Views/CloudVideosDialog.cs', "Grid.Column='5' Text='Actions'"),
    ):
        require(path, token, 'Actions must be the last video table column')
    for path, tokens in (
        ('Mac/ContentView.swift', ('Image(systemName: "xmark.circle.fill")', '.font(.body.weight(.semibold))',
                                  '.foregroundStyle(errorColor)')),
        ('Windows/Views/NewProjectDialog.cs', ('Glyph="&#xE711;"', 'TextWrapping="Wrap" FontSize="16"',
                                               'SystemFillColorCriticalBrush', 'youtubeError.Visibility')),
    ):
        for token in tokens:
            require(path, token, 'New Project YouTube errors need a red cross and larger wrapping text')
    for path, token in (
        ('Mac/ContentView.swift', 'InspectorAIProcessing(studio: studio'),
        ('Mac/LanguageResults.swift', '"assign-result-ai-provider"'),
        ('Windows/MainWindow.xaml', 'x:Name="InspectorAIProcessingRows"'),
        ('Windows/MainWindow.LanguageResults.cs', '"assign-result-ai-provider"'),
    ):
        require(path, token, 'the inspector must show and assign saved AI providers')
    for path, token in (
        ('Mac/YouTubeViews.swift', 'openInEditor(target, choose: false)'),
        ('Mac/YouTubeViews.swift', 'https://studio.youtube.com/video/'),
        ('Windows/MainWindow.YouTube.cs', 'ChooseForNewProjectAsync(openInEditor: true)'),
        ('Windows/MainWindow.YouTube.cs', 'https://studio.youtube.com/video/'),
    ):
        require(path, token, 'the My YouTube Videos row menu must expose both editor and YouTube Studio opening')
    for path, token in (
        ('Mac/VidiStudioApp.swift', '.disabled(!studio.canOpenCloudVideos)'),
        ('Windows/MainWindow.Menus.cs', 'if (id == "open-cloud-videos") return !cloudBrowserOpen;'),
        ('Mac/ContentView.swift', 'if canDelete, let file'),
        ('Windows/Views/CloudVideosDialog.cs', 'if (CanDelete) menu.Items.Add('),
        ('Mac/ContentView.swift', 'if canRename, let file'),
        ('Windows/Views/CloudVideosDialog.cs', 'if (CanRename) menu.Items.Add('),
        ('Mac/KeyboardShortcuts.swift', 'if allProjects?.canShowDeleteProject ?? editor?.canShowDeleteProject ?? true'),
        ('Windows/MainWindow.Menus.cs', '&& !CanDeleteProjectVideo(ProjectManagementTarget())) return false;'),
    ):
        require(path, token, 'the Cloud browser and mutations must respect signed-in permissions')
    for path, token in (
        ('Mac/ContentView.swift', 'if studio.settings.vertexConnected { connectedBrowser }'),
        ('Mac/ContentView.swift', 'else { signedOutBrowser }'),
        ('Mac/ContentView.swift', 'try await YouTubeService.shared.signInToCloud()'),
        ('Windows/Views/CloudVideosDialog.cs', 'signedOutBrowser.Visibility = connected ? Visibility.Collapsed : Visibility.Visible;'),
        ('Windows/Views/CloudVideosDialog.cs', 'await YouTubeService.Shared.SignInToCloudAsync(request.Token);'),
    ):
        require(path, token, 'the signed-out Cloud browser must open and offer Cloud sign-in')
    require('Windows/Views/SettingsDialog.cs', 'new[] { 0, 1, 2, 3, 8, 4, 5, 6, 7 }',
            'Settings must place YouTube Accounts after AI without changing section IDs')
    for path, action in [
        ('Mac/YouTubeProjectPreview.swift', 'YouTubeService.shared.videoForNewProject(videoID, settings: settings)'),
        ('Windows/Views/NewProjectDialog.cs', 'FetchYouTubeDetailsAsync(YouTubeService.Shared.VideoForNewProjectAsync)'),
        ('Mac/ProjectSourcesSettingsView.swift', 'Button("YouTube Details & Captions…"'),
        ('Windows/Views/ProjectSourcesSettingsControl.cs', 'Action("YouTube Details & Captions…", "youtube-captions")'),
        ('Mac/YouTubeViews.swift', 'YouTubeService.shared.refreshedProjectVideo('),
        ('Mac/YouTubeInspectorInformationView.swift', 'YouTubeService.shared.refreshedProjectVideo('),
        ('Windows/MainWindow.YouTube.cs', 'YouTubeService.Shared.RefreshedProjectVideoAsync(id, project, Model.Settings)'),
    ]:
        require(path, action, 'linked YouTube videos must retain metadata lookup and details')
    for path, action in (
        ('Mac/ProjectSourcesSettingsView.swift', 'YouTubePlaybackVideoControls(studio: model, project: project, inProjectSettings: true)'),
        ('Mac/ProjectSourcesSettingsView.swift', 'YouTubeProjectLinkButtons(studio: model, project: project)'),
        ('Mac/ProjectSourcesSettingsView.swift', 'Text("Imported assets").accessibilityAddTraits(.isHeader)'),
        ('Mac/ProjectSourcesSettingsView.swift', 'deleteContentButton(project).contextMenu { deleteContentButton(project) }'),
        ('Windows/Views/ProjectSourcesSettingsControl.cs', 'Header = "Imported assets"'),
        ('Windows/Views/ProjectSourcesSettingsControl.cs', 'item.Click += async (_, _) => await RunAction("delete-content");'),
        ('Windows/Views/ProjectSourcesSettingsControl.cs', 'MainWindow.BuildYouTubeProjectLinks(project)'),
        ('Windows/Views/ProjectSourcesSettingsControl.cs', 'editor.BuildYouTubePlaybackControls(project, RunAction, inProjectSettings: true)'),
        ('Mac/YouTubeInspectorInformationView.swift', 'if showSource && (!inProjectSettings || project.youtubePlaybackVideo != nil || project.originalAudio != nil)'),
        ('Windows/MainWindow.YouTube.cs', 'var fileRow = !inProjectSettings || attachment != null || project.OriginalAudio != null'),
        ('Mac/ProjectSourcesSettingsView.swift', '.accessibilityValue(imported ? "Imported" : "")'),
        ('Windows/Views/ProjectSourcesSettingsControl.cs', 'AutomationProperties.SetHelpText(button, "Imported");'),
        ('Windows/MainWindow.YouTube.cs', 'var item = new MenuFlyoutItem { Text = title, Icon = MenuIcons.Create(id), IsEnabled = enabled };'),
    ):
        require(path, action, 'Project Settings must preserve shared actions and imported assets')
    for path, token in (
        ('Mac/ContentView.swift', 'Visibility: \\(youtubePreview.video.visibility.capitalized)'),
        ('Mac/ContentView.swift', 'YouTubeService.shared.privateConnection(video.channelID, settings: studio.settings) != nil'),
        ('Windows/Views/NewProjectDialog.cs', '"Visibility: " + '),
        ('Windows/Views/NewProjectDialog.cs', 'sourceReady &= YouTubeService.Shared.PrivateConnection(video.ChannelId, settings) != null;'),
    ):
        require(path, token, 'pasted YouTube links must show visibility and gate private project creation')
    for reader in ('Mac/StudioHelp.swift', 'Windows/Views/HelpWindow.xaml.cs'):
        require(reader, 'https://vidistudio.varunmanojkumar.in/docs"', 'Help must load the shared website guide')
        require(reader, 'Documentation requires internet.', 'Help must explain an unavailable connection')
    require('Mac/StudioHelp.swift', 'view.load(URLRequest(url: url', 'Mac Help must render the website directly')
    require('Windows/Views/HelpWindow.xaml.cs', 'core.NavigateWithWebResourceRequest(request)', 'Windows Help must render the website directly')
    for reader in ('Mac/StudioHelp.swift', 'Windows/Views/HelpWindow.xaml'):
        require(reader, '"Retry"', 'Help must offer Retry after a loading error')
        require(reader, 'Open in Browser', 'Help needs a browser action')
        require(reader, 'Loading documentation', 'Help needs an accessible loading indicator')
    mac_about = source['Mac/AboutSettingsView.swift']
    win_about = source['Windows/Views/SettingsDialog.Information.cs'].split('private void BuildAbout(', 1)[1].split('private Button LicenseAction', 1)[0]
    for about in (mac_about, win_about):
        if 'Keyboard shortcuts' in about or 'Jump to Time' in about:
            raise ValueError('About must keep shortcuts in Help')
    if 'Other components' in win_about:
        raise ValueError('Windows About must omit Other components')
    for token in ('"VidiStudio"', '"FFmpeg"', '"Piper voices"', '"Bundled version"', '"License"', '"Open FFmpeg License"', '"Third-party notices"', '"Open Piper License"', '"Piper source code"'):
        if token not in mac_about or token not in win_about:
            raise ValueError('About must retain shared information groups and license actions: ' + token)
    mac_groups = re.findall(r'header: \{ Text\("([^"]+)"\)', mac_about)
    win_groups = re.findall(r'CompactGroup\(panel,"([^"]+)"\)', win_about.split('private Button LicenseAction', 1)[0])
    if mac_groups != win_groups:
        raise ValueError('About group hierarchy/order must match on both desktops')
    help_sources = {'Mac/SettingsView.swift': source['Mac/SettingsView.swift'], 'Windows/Views/SettingsDialog.Information.cs': source['Windows/Views/SettingsDialog.Information.cs'].split('private void BuildHelp(', 1)[1].split('private void BuildAbout(', 1)[0]}
    for path, help_source in help_sources.items():
        for label in ('Open VidiStudio Help', 'Help and keyboard shortcuts', 'Keyboard shortcut reference', 'settings-shortcut-reference'):
            if label not in help_source: raise ValueError(path + ': Help controls and shortcut-reference menu must match')
    require('Windows/Views/SettingsDialog.Information.cs', 'guide.Children.Add(openHelp);', 'Help button must match Mac placement')
    require('Windows/Views/SettingsDialog.Information.cs', 'openHelp.Click += (_,_) => App.OpenHelpWindow', 'opening Help must keep Settings open')
    require('Mac/SettingsView.swift', '@State private var shortcutReferenceExpanded = false', 'Help reference starts collapsed')
    require('Windows/Views/SettingsDialog.Information.cs', 'private bool shortcutReferenceExpanded = false;', 'Help reference starts collapsed')
    require('Windows/Views/SettingsDialog.Information.cs', 'IsExpanded = shortcutReferenceExpanded', 'Help reference must retain expansion across navigation')
    require('Windows/Views/SettingsDialog.Information.cs', 'shortcutReferenceExpanded = reference.IsExpanded', 'Help reference must retain expansion across navigation')
    mac_reference = source['Mac/KeyboardShortcuts.swift'].split('struct ShortcutReferenceView: View', 1)[1]
    win_registry = source['Windows/MainWindow.Menus.cs']
    win_reference = win_registry.split('[] ShortcutReferenceGroups =', 1)[1].split('};', 1)[0]
    mac_categories = dict(re.findall(r'^\s*case (\w+) = "([^"]+)"', mac_reference, re.M))
    mac_order = re.findall(r'^\s*\.(\w+):', mac_reference.split('private static let entries:', 1)[1].split('private var query:', 1)[0], re.M)
    require('Mac/KeyboardShortcuts.swift', r'ForEach(Category.allCases, id: \.self)', 'Help shortcut groups must follow category order')
    if mac_order != list(mac_categories):
        raise ValueError('Mac Expand All must cover the rendered shortcut sections exactly once')
    mac_sections = [mac_categories[category] for category in mac_order]
    win_sections = re.findall(r'\("([^"]+)", new\[\]', win_reference)
    if len(set(mac_sections)) < 2 or mac_sections != win_sections:
        raise ValueError('Help shortcut section headings and order must match on both desktops')
    win_shortcuts = win_registry.split('> DesktopShortcuts = new()', 1)[1].split('};', 1)[0]
    reference_ids = re.findall(r'"([\w-]+)"', re.sub(r'\("[^"]+", new\[\]', '', win_reference))
    if sorted(reference_ids) != sorted(re.findall(r'\["([^"]+)"\] = ', win_shortcuts)):
        raise ValueError('Windows Help must list every keyboard shortcut exactly once')
    require('Mac/KeyboardShortcuts.swift', 'accessibilityHeading(.h3)', 'Help reference sections need accessible headings')
    require('Windows/Views/SettingsDialog.Information.cs', 'ScreenReaderHeading.Mark(section, AutomationHeadingLevel.Level3)', 'Help reference sections need accessible headings')
    require('Mac/SettingsView.swift', 'ShortcutReferenceView(expandedSections: $expandedShortcutSections,', 'Help shortcut sections must retain independent expansion across navigation')
    require('Mac/KeyboardShortcuts.swift', 'DisclosureGroup(isExpanded: expanded)', 'Help shortcut sections must use a native disclosure')
    require('Windows/Views/SettingsDialog.Information.cs', 'expandedShortcutSections.Contains(group.Title)', 'Help shortcut sections must retain independent expansion across navigation')
    for path in ('Mac/KeyboardShortcuts.swift', 'Windows/Views/SettingsDialog.Information.cs'):
        require(path, 'settings-shortcut-section-', 'Help shortcut sections need matching context-menu commands')
        for label in ('Expand All', 'Collapse All', 'settings-shortcut-reference-expand-all', 'settings-shortcut-reference-collapse-all'):
            require(path, label, 'Help bulk controls must have matching context-menu commands')
    for path in ('Mac/KeyboardShortcuts.swift', 'Windows/Views/SettingsDialog.Information.cs'):
        for label in ('Search Shortcuts', 'Clear Shortcut Search', 'settings-shortcut-reference-search',
                      'settings-shortcut-reference-focus-search', 'settings-shortcut-reference-clear-search', 'No shortcuts found'):
            require(path, label, 'Help shortcut search must have matching accessible controls and menu commands')
    require('Mac/KeyboardShortcuts.swift', 'Text(Self.searchHint)', 'Help shortcut search needs a visible hint')
    require('Mac/KeyboardShortcuts.swift', '.accessibilityHint(Self.searchHint)', 'Help shortcut search needs accessible field help')
    require('Windows/Views/SettingsDialog.Information.cs', 'searchRow.Children.Add(hint)', 'Help shortcut search needs a visible hint')
    require('Windows/Views/SettingsDialog.Information.cs', 'AutomationProperties.SetHelpText(search, ShortcutSearchHint)', 'Help shortcut search needs accessible field help')
    require('Mac/KeyboardShortcuts.swift', '!collapsedSearchSections.contains(category)', 'Help search must open matching sections')
    require('Windows/Views/SettingsDialog.Information.cs', 'rowCount > 0 && !collapsedShortcutSearchSections.Contains(group.Title)', 'Help search must open matching sections')
    require('Mac/KeyboardShortcuts.swift', '.disabled(!canSetAllSections(expanded: true))', 'Help must disable bulk commands when already expanded or collapsed')
    require('Mac/KeyboardShortcuts.swift', '.disabled(!canSetAllSections(expanded: false))', 'Help must disable bulk commands when already expanded or collapsed')
    require('Windows/Views/SettingsDialog.Information.cs', 'expand.Button.IsEnabled = expand.Command.IsEnabled = CanSetAllSections(true)', 'Help must disable bulk commands when already expanded or collapsed')
    require('Windows/Views/SettingsDialog.Information.cs', 'collapse.Button.IsEnabled = collapse.Command.IsEnabled = CanSetAllSections(false)', 'Help must disable bulk commands when already expanded or collapsed')
    require('Mac/SettingsView.swift', 'ShortcutSearchKeys(isCaptureFocused: shortcutSearchFocused,', 'Help shortcut capture must follow search field focus')
    require('Mac/SettingsView.swift', 'onFind: { reference.focusSearch() },', 'Settings Find must use the same scoped action as Search Shortcuts')
    require('Mac/KeyboardShortcuts.swift', 'systemImage: "magnifyingglass", action: focusSearch)', 'Settings Find must use the same scoped action as Search Shortcuts')
    require('Windows/Views/SettingsDialog.cs', 'layout.PreviewKeyDown += HandleHelpShortcutSearch;', 'Settings Find must precede search field capture')
    require('Windows/Views/SettingsDialog.cs', 'focusHelpShortcutSearch = null;', 'Find must be scoped to the Settings Help page')
    require('Windows/Views/SettingsDialog.Information.cs', 'focusHelpShortcutSearch = FocusSearch;', 'Settings Find must use the same scoped action as Search Shortcuts')
    require('Windows/Views/SettingsDialog.Information.cs', 'KeyboardAcceleratorTextOverride = "Ctrl+F"', 'Settings Find must be available through the context menu')
    require('Mac/VidiStudioApp.swift', 'AppWindowLifetime.isSettingsWindow(window) || window.identifier == StudioHelp.windowIdentifier', 'Mac close shortcuts must keep Settings and Help separate from Quit')
    require('Windows/Views/SettingsDialog.Information.cs', 'search.PreviewKeyDown +=', 'Help shortcut capture must follow search field focus')
    require('Mac/KeyboardShortcuts.swift', 'revision: searchCaptureRevision', 'Help shortcut searches must announce repeated result counts')
    require('Windows/Views/SettingsDialog.Information.cs', 'RefreshSearch(announce: true)', 'Help shortcut searches must announce repeated result counts')
    require('Windows/Views/SettingsDialog.Information.cs', 'pendingAnnouncement, "settings-shortcut-reference-results"', 'Help shortcut search counts must send a native announcement')
    require('Mac/KeyboardShortcuts.swift', 'entries.values.first?.first?.singleResultAnnouncement', 'A sole shortcut match must announce the action and key')
    require('Windows/Views/SettingsDialog.Information.cs', 'SingleShortcutAnnouncement(match.Label, match.Shortcut)', 'A sole shortcut match must announce the action and key')
    for path in ('Mac/YouTubeInspectorInformationView.swift', 'Windows/MainWindow.YouTube.cs'):
        if '"Information source"' in source[path] or 'YouTube Data API · saved in this project' in source[path]:
            raise ValueError('YouTube Information must start with the saved video details')
    require('Mac/YouTubeInspectorInformationView.swift', 'YouTubeSourceInformationRows(videoID: source.videoID, sourceURL: source.url, identifierSuffix: "-youtube-information")', 'YouTube Information must share the copyable source rows')
    require('Windows/MainWindow.YouTube.cs', 'AddVideoSourceInformation(YouTubeInspectorDetails, project, "-youtube-information");', 'YouTube Information must share the copyable source rows')
    require('Mac/SettingsView.swift', 'reference.searchActions', 'Mac Help must expose search commands in the reference menu')
    require('Mac/SettingsView.swift', 'reference.bulkActions', 'Mac Help must expose bulk commands in the reference menu')
    require('Windows/Views/SettingsDialog.Information.cs', 'command.Click += (_, _) => SetAllSections(expanded)', 'Windows Help menu must share the bulk button action')
    for path in ('Mac/ContentView.swift', 'Windows/MainWindow.Presentation.cs'):
        for label in ('Copy YouTube Video ID', 'copy-youtube-video-id', 'Copy YouTube URL', 'copy-youtube-url'):
            require(path, label, 'YouTube video information must expose matching copy actions')
    require('Mac/KeyboardShortcuts.swift', '.init(id: "jump-to-time", title: "Jump to Time…"', 'Help must retain Jump to Time')
    require('Windows/Views/SettingsDialog.Information.cs', 'menuOwner.DesktopShortcutReference', 'Help must retain the complete shared shortcut list')
    for action in ('about-ffmpeg-license', 'about-license-index', 'about-license-folder'):
        if action not in mac_about or action not in win_about:
            raise ValueError('About license actions must have matching menus: ' + action)
    commands = source['Windows/MainWindow.Menus.cs'].split('private bool CanRunDesktopCommand(string id)', 1)[1]
    require('Windows/MainWindow.Menus.cs', 'if (id is "settings" or "help" or "about") return true;', 'Help/About must stay available during editor processing')
    if commands.index('if (id is "settings" or "help" or "about") return true;') > commands.index('if (!Model.Idle) return false;'):
        raise ValueError('Help/About must stay available during editor processing')
    require('Windows/Views/SettingsDialog.Information.cs', 'TextAlignment = TextAlignment.Right', 'information values must align to the right')
    mac_language = source['Mac/LanguageResults.swift']
    win_language = source['Windows/MainWindow.LanguageResults.cs']
    if mac_language.index('Picker(editorActions.segmentEditMode ?') > mac_language.index('Button(editorActions.currentSectionCopyTitle,') or 'panel.Children.Add(language);' not in win_language or win_language.index('panel.Children.Add(language);') > win_language.index('panel.Children.Add(copyAll);'):
        raise ValueError('Inspector project language must precede all actions')
    for path in ('Mac/LanguageResults.swift', 'Windows/MainWindow.LanguageResults.cs'):
        if any(token in source[path] for token in (' Generation Language', 'Review language filter', 'Keep All Sections in Sync', '"Source Language"')):
            raise ValueError('Inspector and copy must not repeat language choices')
    if 'OutputLanguagePicker(selection:' in source['Mac/ImportAssetsView.swift'] or 'languagePicker' in source['Windows/Views/ImportAssetsDialog.cs']:
        raise ValueError('Imports must inherit the project language')
    for path, token in (('Mac/CreatedExportsView.swift', 'project.languagesForExport(path).contains(project.languageCode)'), ('Windows/MainWindow.Presentation.cs', 'project.LanguagesForExport(path).Contains(project.SelectedLanguage)')):
        require(path, token, 'Created Exports must follow project language')
        if 'Export language filter' in source[path]: raise ValueError('Created Exports must not repeat language selection')
    require('Windows/MainWindow.Accessibility.cs', 'Shared inspector language must be accessible, bounded and above every action.', 'retain native inspector geometry checks')
    for path, tokens in (
        ('Mac/ImportDecision.swift', ('addButton(withTitle: "Okay")', 'canContinue ? alert.addButton(withTitle: "Import Anyway")',
                                     'window.defaultButtonCell = okay.cell', 'button.menu = menu', 'buttons[sender.tag].performClick(nil)')),
        ('Windows/MainWindow.ImportDecision.cs', ('CloseButtonText = "Okay"', 'PrimaryButtonText = canContinue ? "Import Anyway"',
                                                 'DefaultButton = ContentDialogButton.Close', 'dialog.ContextFlyout = actions',
                                                 'Icon = new SymbolIcon(icon)', 'choice = result; dialog.Hide();'))):
        for token in tokens:
            require(path, token, 'import decisions must preserve safe defaults, scoped icon commands, and guarded continuation')
    for path in ('SettingsView.swift', 'ImportAssetsView.swift', 'ExportOptionsMenu.swift'):
        require('Mac/' + path, '.formStyle(.grouped)', 'retain native compact grouped forms')
        require('Mac/' + path, 'Section', 'retain section grouping')
    for path, titles in (
        ('GeminiAPISettingsView.swift', ('Check API Key', 'Open API Keys in Google AI Studio')),
        ('SarvamVoiceSettingsView.swift', ('Check API Key', 'Open Sarvam API Keys')),
        ('ImportAssetsView.swift', ('Distribute Evenly', 'Auto-time with Gemini'))):
        if not any(all(title in block for title in titles) for block in swift_blocks(source['Mac/' + path], 'HStack')):
            raise ValueError('Mac/' + path + ': related actions must share a horizontal row')
    for path in ('SystemVoiceCatalog.swift','PiperVoiceCatalog.swift','GeminiVoicePreview.swift','SarvamVoiceSettingsView.swift'):
        require('Mac/' + path, 'VoiceSampleSession.shared.begin(sampleOwner)', 'sample starts must claim the shared session')
        require('Mac/' + path, 'VoiceSampleSession.shared.end(sampleOwner)', 'sample cleanup must release its own session')
    require('Mac/SystemVoiceCatalog.swift', 'playingVoiceID = voice.id; isPlayingSample = true', 'Apple icons must update before speech starts')
    require('Mac/SarvamVoiceSettingsView.swift', 'if sample.preparing { ProgressView()', 'Sarvam generation needs a visible preparation spinner')
    require('Mac/GeminiVoicePreview.swift', 'if preview.loading { ProgressView()', 'Gemini generation needs a visible preparation spinner')
    for path in ('Views/PiperVoicesDialog.cs','Views/PiperDeleteVoicesDialog.cs'):
        require('Windows/' + path, 'VoiceSampleSession.Begin(sampleOwner)', 'catalog samples share the playback guard')
        require('Windows/' + path, 'VoiceSampleSession.End(sampleOwner)', 'catalog samples release the playback guard')
    require('Windows/Views/SettingsDialog.cs', 'nativePreparingRing.IsActive = sampleState == SampleState.Generating', 'native/Gemini sample preparation must be visible')
    for path in ('Mac/GeminiVoicePreview.swift', 'Windows/Views/SettingsDialog.GeminiVoices.cs'):
        for token in ('Search voices', 'Search Voice Library', 'gemini-voice-language',
                      'gemini-voice-style', 'gemini-voice-sort', 'Reset Voice Filters', 'Stop Sample'):
            require(path, token, 'Gemini voice browser controls and context actions must match')
    require('Windows/Views/SettingsDialog.GeminiVoices.cs', 'parent.Children.Add(geminiVoiceControls)', 'embed the browser in the Narration settings card')
    require('Mac/GeminiVoicePreview.swift', 'GeminiNarrationCatalog(studio: studio, sampleText: sample)', 'embed the browser in the Narration settings card')
    for path, provider, summary in (
        ('Mac/SettingsView.swift', 'GeminiVoiceBrowser(studio: studio)', 'SummaryVoiceSettingsView(settings: $studio.settings)'),
        ('Windows/Views/SettingsDialog.cs', 'panel.Children.Add(sampleSection);', 'BuildAdditionalSpeechControls(panel);'),
    ):
        for token in (provider, summary):
            require(path, token, 'Narration provider settings must precede Summary voice')
        if source[path].index(provider) >= source[path].index(summary):
            raise ValueError(path + ': Narration provider settings must precede Summary voice')
    require('Windows/Views/SettingsDialog.Sarvam.cs', 'sarvamPreparingRing.IsActive = sarvamSamplePreparing', 'Sarvam sample preparation must be visible')
    require('Windows/Views/SettingsDialog.Sarvam.cs', '!VoiceSampleSession.Busy', 'Sarvam and Summary sample actions share the session guard')
    require('Windows/Views/WindowAppearance.cs', 'CompactDialogLayout.PrepareDialog(dialog);', 'all companion forms must use shared presentation')
    require('Windows/Views/WindowAppearance.cs', 'dialog.ReadLocalValue(FrameworkElement.MaxWidthProperty)', 'distinguish explicit width caps from narrow native style defaults')
    require('Windows/Views/WindowAppearance.cs', 'LocalSize(dialog.Resources,"ContentDialogMaxWidth")', 'distinguish local width resources from global theme defaults')
    for token, reason in (
        ('SettingsDialog.AddSettingsRow', 'reuse the responsive aligned row'),
        ('HeaderTemplate', 'preserve native header metadata while rendering inline labels'),
        ('AutomationProperties.SetName(field,name)', 'retain existing accessible names'),
        ('GroupActions(stack)', 'retain adjacent related actions'),
        ('GroupFields(stack)', 'retain compact field groups'),
        ('new CompactActionsPanel()', 'use measured, responsive action placement')):
        require('Windows/Views/CompactDialogLayout.cs', token, reason)
    require('Windows/Views/SettingsDialog.Compact.cs', 'ThemeResource CardBackgroundFillColorDefaultBrush', 'cards must follow light/dark/high contrast themes')
    require('Windows/Views/SettingsDialog.Compact.cs', 'new AccessibilityGroup', 'retain named UI Automation groups')
    for path, token in (
        ('SettingsDialog.ElevenLabs.cs', 'FullWidthVoiceSearch(field);parent.Children.Add(field);'),
        ('SettingsDialog.SarvamBrowser.cs', 'FullWidthVoiceSearch(searchBox);'),
        ('SettingsDialog.Sarvam.cs', 'FullWidthVoiceSearch(search);'),
        ('PiperVoicesDialog.cs', 'SettingsDialog.FullWidthVoiceSearch(search);'),
        ('PiperDeleteVoicesDialog.cs', 'SettingsDialog.FullWidthVoiceSearch(search);'),
        ('CompactDialogLayout.cs', 'field.Tag as string != "voice-search-full-width"'),
        ('SettingsDialog.Layout.cs', 'field.ActualWidth < host.ActualWidth - 2')):
        require('Windows/Views/' + path, token, 'voice search must remain full width')
    require('Windows/Views/SettingsDialog.cs', 'previousVoiceGroup.Children.Remove(piperControls)', 'hidden voice groups must release retained controls before rebuilding')
    require('Windows/Views/SettingsDialog.Sarvam.cs', 'Summary tuning must follow its heading and precede voice browsing.', 'Summary heading and tuning order need native coverage')
    require('Windows/Views/SettingsDialog.Layout.cs', 'SetLabeledBy(control, title)', 'retain explicit field labels')
    require('Windows/Views/SettingsDialog.Layout.cs', 'args.NewSize.Width < stackBelow', 'reflow according to available width')
    for token in ('MeasureOverride', 'ArrangeOverride', 'Fits(finalSize.Width)'):
        require('Windows/Views/SettingsDialog.SpeechLayout.cs', token, 'measure and arrange actions at their actual width')
    for token, reason in (
        ('TransformToVisual(row)', 'assert actual rendered field positions'),
        ('ActualTheme==ElementTheme.Dark', 'check dark theme card fills'),
        ('CompactActionsPanel', 'check related button geometry'),
        ('picker.SelectedIndex!=1 || events!=0', 'verify presentation preserves values/events'),
        ('project.json', 'verify cancellation preserves project data')):
        require('Windows/MainWindow.DialogLayoutSmoke.cs', token, reason)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--allow-missing', action='store_true')
    args = parser.parse_args()
    if not all((args.workspace / folder).is_dir() for folder in ('VidiStudio Mac', 'Vidi-Studio-Windows')) and args.allow_missing:
        print('SKIP: paired desktop UI source check needs both checkouts; native UI parity remains unverified.')
    else:
        validate(sources(args.workspace))
        print('PASS: desktop Help/About groups, shortcuts and menus; Mac grouped forms/adjacent actions and Windows shared responsive, accessible, theme-aware forms; native geometry guards retained.')
