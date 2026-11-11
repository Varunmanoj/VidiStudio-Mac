"""Regression contract for the actual right-click declarations on both desktops."""
import re
from pathlib import Path


def check_context_menu_layouts(workspace, windows_root=None):
    mac = Path(workspace) / 'VidiStudio Mac/VidiStudio'
    win = Path(windows_root or Path(workspace) / 'Vidi-Studio-Windows') / 'Vidi Studio Windows'
    source = (win / 'MainWindow.Commands.cs').read_text(encoding='utf-8')
    rendering = source.split('private MenuFlyout ProjectMenu(', 1)[1]
    sidebar, gallery = rendering.split('        if (editorBrowser)\n', 1)[1].split('        else\n', 1)
    gallery = gallery.split('        menu.Opening', 1)[0]
    actual = re.findall(r'Item\("([^"]+)"', gallery)
    expected = ['open-gallery-window', 'rename-project', 'youtube-open-browser', 'project-settings',
                'show-in-finder', 'open-configuration', 'prepare-video', 'analyze', 'transcribe',
                'generate-summary', 'generate-ad-cues', 'export', 'remove-from-list', 'delete-content', 'delete-project']
    if actual != expected:
        raise ValueError('Windows gallery context action order differs from Mac: ' + repr(actual))
    if re.findall(r'Item\("([^"]+)"', sidebar) != ['open-project-here', 'youtube-open-browser', 'open-editor-window', 'project-settings', 'remove-from-list', 'trash-project']:
        raise ValueError('Windows editor project context menu must match the smaller Mac sidebar menu')
    for token in ['MenuFlyoutSubItem { Text = "Analysis"', 'entries: analysis.Items', 'menu.Items.Add(analysis);',
                  'SegmentMenu(element.Tag as Segment, moreActionsOnly: true)',
                  'analysis.Items.Add(new MenuFlyoutSeparator());', 'DesktopCommandTitle(id, project)',
                  'IsEnabled = CanRunProjectContextCommand(id, project, editorBrowser)',
                  'if (!CanRunProjectContextCommand(id, project, editorBrowser)) return;',
                  'Item("delete-content", "Choose Content to Delete…")',
                  'Item("show-in-finder", "Open in Project Folder")']:
        if token not in source:
            raise ValueError('Windows project context contract missing: ' + token)
    gallery_titles = ['Open in New Window', 'Rename', 'Open in YouTube', 'Open Project Settings…', 'Open in Project Folder', 'Open Project Configuration', 'Remove from List', 'Choose Content to Delete…', 'Delete Project…']
    for path, body in [('ProjectBrowserPage.swift', None), ('ProjectGridView.swift', None)]:
        text = (mac/path).read_text(encoding='utf-8')
        if path == 'ProjectBrowserPage.swift': text = text.split('private func projectMenu(', 1)[1]
        else: text = text.split('.contextMenu {', 1)[1].split('struct ProjectThumbnail', 1)[0]
        if re.findall(r'Button\("([^"]+)"', text) != gallery_titles:
            raise ValueError('Mac gallery context order changed; update both desktops: ' + path)
        if 'ProjectAnalysisMenu(' not in text or 'ProjectExportButton(' not in text:
            raise ValueError('Mac gallery must retain Analysis and Export')
    if re.findall(r'Button\("([^"]+)"|Link\("([^"]+)"', (mac/'EditorProjectBrowser.swift').read_text(encoding='utf-8').split('.contextMenu {', 1)[1]) != [('Open in This Window',''), ('','Open in YouTube'), ('Open in New Window',''), ('Open Project Settings…',''), ('Remove from List',''), ('Delete Project…','')]:
        raise ValueError('Mac sidebar context menu changed; update Windows too')
    guard = source.split('private bool CanRunProjectContextCommand(', 1)[1].split('private async', 1)[0]
    if re.search(r'"export"[^\n]*Model.CanUseAI', guard):
        raise ValueError('Context Export must not acquire an AI requirement')
    for path, tokens in [('MainWindow.ContextMenus.cs', ['Read from Start', 'Read from Selection', 'Read Selected Text Only', 'Edit Summary…', 'Stop', 'Read Summary from Here', 'Read Selected Text', 'Pause Summary Reading', 'Resume Summary Reading', 'Stop Summary Reading']), ('MainWindow.YouTube.cs', ['list.ContextRequested +=', 'new[] { "youtube-open-editor", "youtube-open-browser" }', 'ReferenceEquals(list.SelectedItem, target) && youtubeBrowserCanRun?.Invoke(id) == true'])]:
        text = (win/path).read_text(encoding='utf-8')
        for token in tokens:
            if token not in text: raise ValueError('Windows context contract missing: ' + token)
    background = (win/'MainWindow.xaml.cs').read_text(encoding='utf-8')
    if 'copyToItem.Visibility = desktopEditorVisible && EditorCommandVisible("copy-to")' not in background:
        raise ValueError('Windows background context must omit unrelated Copy and Translate')
