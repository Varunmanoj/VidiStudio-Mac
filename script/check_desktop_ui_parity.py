#!/usr/bin/env python3
"""Architecture guards for paired desktop forms; native geometry remains a separate required check."""
import argparse
import re
from pathlib import Path

MAC_FILES = ('StudioHelp.swift', 'CreatedExportsView.swift', 'LanguageResults.swift', 'ContentView.swift', 'SettingsView.swift', 'ImportAssetsView.swift', 'ExportOptionsMenu.swift',
             'GeminiAPISettingsView.swift', 'SarvamVoiceSettingsView.swift', 'SystemVoiceCatalog.swift', 'PiperVoiceCatalog.swift', 'GeminiVoicePreview.swift', 'SarvamVoiceBrowser.swift', 'VoiceSampleSession.swift', 'AboutSettingsView.swift', 'KeyboardShortcuts.swift', 'ProjectBrowserPage.swift',
             'ProjectSourcesSettingsView.swift', 'YouTubeViews.swift', 'YouTubeProjectPreview.swift')
WIN_FILES = ('Views/HelpWindow.xaml', 'Views/HelpWindow.xaml.cs', 'MainWindow.Presentation.cs', 'MainWindow.LanguageResults.cs', 'Views/ImportAssetsDialog.cs', 'MainWindow.Accessibility.cs', 'MainWindow.xaml', 'Views/CompactDialogLayout.cs', 'Views/WindowAppearance.cs',
             'Views/SettingsDialog.Compact.cs', 'Views/SettingsDialog.Layout.cs',
             'Views/SettingsDialog.ElevenLabs.cs', 'Views/SettingsDialog.SarvamBrowser.cs', 'Views/SettingsDialog.SpeechLayout.cs', 'MainWindow.DialogLayoutSmoke.cs', 'Views/SettingsDialog.cs', 'Views/SettingsDialog.Sarvam.cs', 'Views/PiperVoicesDialog.cs', 'Views/PiperDeleteVoicesDialog.cs', 'Services/VoiceSampleSession.cs', 'Views/SettingsDialog.Information.cs', 'MainWindow.Menus.cs',
             'Views/NewProjectDialog.cs', 'Views/ProjectSourcesSettingsControl.cs', 'MainWindow.YouTube.cs')

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
    if ('ProgressView("Opening YouTube project…")' not in source['Mac/ContentView.swift']
            or 'x:Name="SharedVideoRing"' not in source['Windows/MainWindow.xaml']
            or 'Text="Opening YouTube project…" ' not in source['Windows/MainWindow.xaml']):
        raise ValueError("Missing shared YouTube project progress indicator")

    def require(path, token, reason):
        if token not in source[path]: raise ValueError(path + ': ' + reason)
    for path, text in source.items():
        for label in ('My YouTube Videos', 'YouTube Accounts', 'Choose YouTube captions after',
                      'Download YouTube Captions', 'Import YouTube Captions', 'Caption account'):
            if label in text:
                raise ValueError(f'{path}: retired YouTube control: {label}')
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
