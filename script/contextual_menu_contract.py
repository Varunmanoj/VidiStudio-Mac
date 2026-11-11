"""Check shared tab/source visibility and menu/accelerator wiring."""
import re

SECTIONS = ['transcript', 'summary', 'descriptions', 'ad-overview', 'ad-transcript']


def _policy(source, swift):
    start = source.index('func isCommandVisible(' if swift else 'private bool EditorCommandVisible(')
    end = source.index('\n    }', start)
    body = source[start:end]
    if swift:
        rows = re.findall(r'case\s+(.+?):\s*return\s+(.+?)(?=\n\s*case|\n\s*default)', body, re.S)
    else:
        rows = re.findall(r'((?:"[^"]+"\s*(?:or\s*)?)+)\s*=>\s*([^,]+)', body)
    result = {}
    for keys, expression in rows:
        if swift:
            allowed = {SECTIONS.index(name) for name in re.findall(r'"([^"]+)"', expression) if name in SECTIONS}
        else:
            allowed = {int(number) for number in re.findall(r'\b[0-4]\b', expression)}
        source_only = 'youtubeProject' in expression or 'IsYouTube' in expression
        if not allowed and 'false' not in expression: allowed = set(range(5))
        for key in re.findall(r'"([^"]+)"', keys): result[key] = (allowed, source_only)
    return result


def check_contextual_menus(mac, windows):
    if _policy(mac, True) != _policy(windows, False):
        raise ValueError('Desktop tab/source visibility policies differ')
    mac_guards = [
        'guard available, handler != nil, isCommandVisible(action) else',
        'guard canRun(action) else',
        'guard isCommandVisibleInMode(action) else',
        'if editor?.segmentEditMode == true {',
        'return segmentEditMode',
        'if activeSection == "summary", summaryEditing {',
        'ForEach(shortcuts.filter { editor?.isCommandVisible($0.id) == true })',
        'if editor?.isCommandVisible(id) == true, let shortcut',
        'if editor?.summaryActive == true && editor?.summaryEditing != true {',
        'if editor?.canFilterSegments == true {',
        'if editor?.youtubeProject == true {',
        'if youtubeMenusVisible {',
        'if youtubeBrowser != nil {',
        'allProjects != nil || editor?.youtubeProject == true || youtubeBrowser != nil',
        'if action.hasPrefix("summary-") { return activeSection == "summary" }',
    ]
    for action in ('copy-to', 'segment-edit-mode', 'add', 'synthesize-tts', 'generate-ad-cues',
                   'youtube-captions', 'import-transcript', 'import-summary', 'import-descriptions', 'import-original-audio', 'import-ad-audio'):
        mac_guards.append('if editor?.isCommandVisible("' + action + '") == true {')
    for action in ('transcribe', 'generate-summary'):
        mac_guards.append('if allProjects != nil || editor?.isCommandVisible("' + action + '") == true {')
    win_guards = [
        'desktopEditorVisible && !EditorCommandVisible(id)',
        'if (!EditorCommandVisibleInMode(id)) return false;',
        'if (Section.SelectedIndex == 1 && summaryEditMode)',
        '&& EditorCommandVisible(id)',
        'menu.Title == "YouTube" && !YouTubeMenusVisible',
        'if (!YouTubeMenusVisible) return false;',
        'if (!CanRunDesktopCommand(id)) return;',
        '() => CanRunDesktopCommand(id)',
        'if (id.StartsWith("summary-", StringComparison.Ordinal)) return Section.SelectedIndex == 1;',
        'if (name == "Segments") group.Visibility = timedSection',
        'if (name == "Summary Reading") {\n                group.Visibility = desktopEditorVisible && Section.SelectedIndex == 1 && !summaryEditMode',
        'if (name == "YouTube") group.Visibility = desktopEditorVisible && Model.Project?.IsYouTube == true',
        'if (name is "Narration" or "Narration Audio") group.Visibility = desktopEditorVisible && EditorCommandVisible("synthesize-tts")',
        'if (name == "AD Segment Generation") group.Visibility = desktopEditorVisible && EditorCommandVisible("generate-ad-cues")',
    ]
    for platform, source, guards in [('Mac', mac, mac_guards), ('Windows', windows, win_guards)]:
        for guard in guards:
            if guard not in source: raise ValueError(platform + ' contextual menu guard missing: ' + guard)
