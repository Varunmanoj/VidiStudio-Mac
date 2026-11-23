#!/usr/bin/env python3
"""Architecture guards for paired desktop forms; native geometry remains a separate required check."""
import argparse
import re
from pathlib import Path

MAC_FILES = ('ADOverviewView.swift', 'StudioHelp.swift', 'CreatedExportsView.swift', 'LanguageResults.swift', 'ContentView.swift', 'SettingsView.swift', 'ImportAssetsView.swift', 'ExportOptionsMenu.swift',
             'GeminiAPISettingsView.swift', 'SarvamVoiceSettingsView.swift', 'SystemVoiceCatalog.swift', 'PiperVoiceCatalog.swift', 'GeminiVoicePreview.swift', 'SarvamVoiceBrowser.swift', 'VoiceSampleSession.swift', 'AboutSettingsView.swift', 'KeyboardShortcuts.swift', 'ProjectBrowserPage.swift',
             'ProjectSourcesSettingsView.swift', 'YouTubeViews.swift', 'YouTubeProjectPreview.swift', 'VidiStudioApp.swift')
WIN_FILES = ('Views/SettingsDialog.Gemini.cs', 'Views/HelpWindow.xaml', 'Views/HelpWindow.xaml.cs', 'MainWindow.Presentation.cs', 'MainWindow.LanguageResults.cs', 'Views/ImportAssetsDialog.cs', 'MainWindow.Accessibility.cs', 'MainWindow.xaml', 'Views/CompactDialogLayout.cs', 'Views/WindowAppearance.cs',
             'Views/SettingsDialog.Compact.cs', 'Views/SettingsDialog.Layout.cs',
             'Views/SettingsDialog.ElevenLabs.cs', 'Views/SettingsDialog.SarvamBrowser.cs', 'Views/SettingsDialog.SpeechLayout.cs', 'MainWindow.DialogLayoutSmoke.cs', 'Views/SettingsDialog.cs', 'Views/SettingsDialog.Sarvam.cs', 'Views/PiperVoicesDialog.cs', 'Views/PiperDeleteVoicesDialog.cs', 'Services/VoiceSampleSession.cs', 'Views/SettingsDialog.Information.cs', 'MainWindow.Menus.cs',
             'Views/NewProjectDialog.cs', 'Views/CloudVideosDialog.cs', 'Views/ProjectSourcesSettingsControl.cs', 'MainWindow.YouTube.cs', 'MainWindow.xaml.cs', 'App.xaml.cs')

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
    require('Mac/ContentView.swift', 'MainWindowLifetime(onClose: { openWindow(id: "studio") })', 'editor close must return to All Projects')
    require('Windows/App.xaml.cs', 'var target = ProjectLibrary();', 'external activation must start in All Projects')
    require('Windows/MainWindow.xaml.cs', 'App.OpenOrActivateEditor(folder)', 'external activation must open a separate editor')
    require('Windows/MainWindow.Menus.cs', 'if (wasEditor && windowClosed) App.ShowProjectLibrary();', 'editor close must return to All Projects')
    for path, text in source.items():
        for label in ('My YouTube Videos', 'YouTube Accounts', 'Choose YouTube captions after',
                      'Download YouTube Captions', 'Import YouTube Captions', 'Caption account'):
            if label in text:
                raise ValueError(f'{path}: retired YouTube control: {label}')
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
    for path, token in (
        ('Windows/Views/NewProjectDialog.cs', 'Grid.SetRow(sourceCard, 1); layout.Children.Add(sourceCard);'),
        ('Windows/Views/NewProjectDialog.cs', 'Grid.SetRow(form, 2); layout.Children.Add(form);'),
        ('Windows/Views/WindowAppearance.cs', 'keepsSize = dialog is NewProjectDialog;'),
        ('Windows/Views/WindowAppearance.cs', 'if (keepsSize || disposed || observing) return;'),
        ('Windows/MainWindow.xaml.cs', 'ShowDialogAsync(dialog, Views.NewProjectDialog.WindowWidth, Views.NewProjectDialog.WindowHeight);'),
    ):
        require(path, token, 'Windows New Project must use fixed bounds across sources')
    for path in ('Mac/ContentView.swift', 'Windows/Views/CloudVideosDialog.cs'):
        for token in ('Open Cloud Videos', 'Google Cloud project', 'Source bucket', 'Search videos',
                      'Recently Modified', 'Largest First', 'Open in Editor', 'Load Thumbnail', 'Rename Video…', 'Delete Video…'):
            require(path, token, 'the dedicated Cloud browser must support browsing and video actions')
    for path, token in (
        ('Mac/VidiStudioApp.swift', '.disabled(!studio.canOpenCloudVideos)'),
        ('Windows/MainWindow.Menus.cs', 'if (id == "open-cloud-videos") return !cloudBrowserOpen && Model.Settings.GetBool("vertexConnected");'),
        ('Mac/ContentView.swift', 'if canDelete, let file'),
        ('Windows/Views/CloudVideosDialog.cs', 'if (CanDelete) menu.Items.Add('),
        ('Mac/ContentView.swift', 'if canRename, let file'),
        ('Windows/Views/CloudVideosDialog.cs', 'if (CanRename) menu.Items.Add('),
        ('Mac/KeyboardShortcuts.swift', 'if allProjects?.canShowDeleteProject ?? editor?.canShowDeleteProject ?? true'),
        ('Windows/MainWindow.Menus.cs', '&& !CanDeleteProjectVideo(ProjectManagementTarget())) return false;'),
    ):
        require(path, token, 'the Cloud browser and mutations must respect signed-in permissions')
    require('Windows/Views/SettingsDialog.cs', 'Enumerable.Range(0, labels.Length)',
            'Settings navigation must enumerate the current sidebar labels')
    for path, action in [
        ('Mac/YouTubeProjectPreview.swift', 'YouTubeService.shared.video(videoID)'),
        ('Windows/Views/NewProjectDialog.cs', 'YouTubeService.Shared.VideoAsync('),
        ('Mac/ProjectSourcesSettingsView.swift', 'Button("Video Details…"'),
        ('Windows/Views/ProjectSourcesSettingsControl.cs', '("Video Details…", "youtube-details")'),
        ('Mac/YouTubeViews.swift', 'YouTubeService.shared.video(id)'),
        ('Windows/MainWindow.YouTube.cs', 'service.VideoAsync(id, cancellation.Token)'),
    ]:
        require(path, action, 'linked YouTube videos must retain metadata lookup and details')
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
    require('Windows/Views/SettingsDialog.Information.cs', 'reference.Expanding += (_, _) => shortcutReferenceExpanded = true', 'Help reference must retain expansion across navigation')
    require('Mac/KeyboardShortcuts.swift', 'ForEach(StudioShortcut.editor + StudioShortcut.youtube)', 'Help must retain the complete shared shortcut list')
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
