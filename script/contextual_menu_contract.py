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
    for token in ['allProjects.projectSort.wrappedValue == .lastOpened',
                  'allProjects.projectSort.wrappedValue == .name',
                  'allProjects.projectSort.wrappedValue == .duration',
                  'allProjects.projectSort.wrappedValue == .type',
                  'StudioHelp.openWebsite()', '.accessibilityIdentifier("website")']:
        if token not in mac: raise ValueError('Mac project sort/website contract missing: ' + token)
    for token in ['if (id.StartsWith("projects-sort-", StringComparison.Ordinal)) return !desktopEditorVisible;',
                  'if (name is "Filter Projects by Source" or "Sort Projects") group.IsEnabled = !desktopEditorVisible;',
                  'Model.ProjectSort == "opened"', 'Model.ProjectSort == "name"',
                  'Model.ProjectSort == "duration"', 'Model.ProjectSort == "type"',
                  'if (id == "website") return true;',
                  'case "website": await Launcher.LaunchUriAsync(new Uri("https://vidistudio.varunmanojkumar.in/")); break;']:
        if token not in windows: raise ValueError('Windows project sort/website contract missing: ' + token)
    if _policy(mac, True) != _policy(windows, False):
        raise ValueError('Desktop tab/source visibility policies differ')
    mac_guards = [
        'guard available, handler != nil, isCommandVisible(action) else',
        'guard canRun(action) else',
        'guard isCommandVisibleInMode(action) else',
        'if action == "copy-to" { copyHandler?(false); return }',
        'func copyCurrentSection()',
        'copyHandler?(true)',
        'if editor?.segmentEditMode == true {',
        'return segmentEditMode',
        'if activeSection == "summary", summaryEditing {',
        'ForEach(shortcuts.filter { editor?.isCommandVisible($0.id) == true })',
        'if editor?.isCommandVisible(id) == true, let shortcut',
        'if editor?.summaryActive == true && editor?.summaryEditing != true {',
        'if editor?.canFilterSegments == true {',
        'if editor?.youtubeProject == true {',
        'if youtubeMenusVisible {',
        'ForEach(allProjects.languageOptions)',
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
        'Concat(Model.ProjectFilterLanguages)',
        'if (!EditorCommandVisibleInMode(id)) return false;',
        'if (Section.SelectedIndex == 1 && summaryEditMode)',
        '&& EditorCommandVisible(id)',
        'menu.Title == "YouTube" && !YouTubeMenusVisible',
        'if (!YouTubeMenusVisible) return false;',
        'if (!CanRunDesktopCommand(id)) return;',
        'private async Task RunDesktopCommandAsync(string id, bool copyCurrentSectionOnly = false)',
        'await ShowCopyToAsync(initialKinds: CopyDefaultKinds(copyCurrentSectionOnly)',
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


def check_row_more_actions(mac_content, windows_commands, mac_language, windows_language):
    more_menus = re.findall(r'SegmentActionsMenu\(actions: \[(.*?)\n\s*\]\)', mac_content, re.S)
    if len(more_menus) != 2 or any('Copy' in menu for menu in more_menus):
        raise ValueError('Mac row More Actions must omit copying for transcript and description rows')
    context = mac_content.split('.accessibilityValue(validationHighlightID == row.id ? "Timing validation issue" : "")', 1)[1]
    context = context.split('.contextMenu {', 1)[1].split('}.listStyle(.inset)', 1)[0]
    helper = mac_content.split('@ViewBuilder private func segmentRowContextMenu(', 1)[1].split('private func runSegmentRowAction(', 1)[0]
    if 'Copy' in context or 'Copy' in helper:
        raise ValueError('Mac individual row context menu must omit copying')
    row_branch = windows_commands.split('\n        if (segment != null)\n        {', 1)[1].split('\n        else\n        {', 1)[0]
    if 'Copy' in row_branch or 'ShowCopyToAsync' in row_branch:
        raise ValueError('Windows individual row context and More Actions must omit copying')
    if 'Button(editorActions.currentSectionCopyTitle,' not in mac_language or 'Content = CurrentSectionCopyTitle' not in windows_language:
        raise ValueError('Inspector must retain the current-section Copy and Translate action')
    if 'editorActions.copyCurrentSection()' not in mac_language or 'copyAll.Click += async (_, _) => await RunDesktopCommandAsync("copy-to", copyCurrentSectionOnly: true)' not in windows_language:
        raise ValueError('Inspector must use the guarded current-section copy command')
    if mac_language.count('Button(editorActions.currentSectionCopyTitle,') != 1 or windows_language.count('Content = CurrentSectionCopyTitle') != 1:
        raise ValueError('Inspector must offer exactly one Copy and Translate action')
    if '_selectedOnly = State(initialValue: false)' not in mac_language or 'Content = "Selected Segments Only", IsChecked = false' not in windows_language:
        raise ValueError('Copy dialog must initially allow all preselected content types')
    if 'Text("Copy and Translate")' not in mac_language or 'Title = "Copy and Translate"' not in windows_language:
        raise ValueError('Copy and Translate dialog titles must match')


def check_single_segment_commands(mac, windows, content, commands):
    for source, tokens in [
        (mac, ['segmentEditMode, selectedSegmentCount == 1, let kind = selectedSegmentKind',
               'return canRunRowCommand(action, kind: kind, hasAudio: selectedSegmentHasAudio, audioReady: selectedSegmentAudioReady, isPreviewing: selectedSegmentPreviewing)',
               'segmentEditMode && rowCommandVisible(action, kind: selectedSegmentKind)']),
        (windows, ['return editMode && SingleSelectedSegment() is { } segment && CanRunRowCommand(id, segment);',
                   'Segments.SelectedItems.Count == 1', 'Segments.Items.Contains(segment) && SegmentBelongsToCurrentTab(segment)',
                   'return CanRunSingleSegmentCommand(id);', 'return editMode && RowCommandVisible(id, SingleSelectedSegment()?.IsDescription) &&']),
        (content, ['.contextMenu { segmentRowContextMenu(row) }',
                   'guard canRunSegmentRowAction(action, row: row) else { return }',
                   'guard shortcutActions.canRun(action), selectedSegmentIDs.count == 1, selectedRows.count == 1,']),
        (commands, ['if (!CanRunRowCommand(id, segment)) return;', 'await RunSegmentRowCommandAsync(id, segment)',
                    'RowCommandVisible(id, segment.IsDescription)', 'IsEnabled = CanRunRowCommand(id, segment)'])
    ]:
        for token in tokens:
            if token not in source: raise ValueError('Single-segment command guard missing: ' + token)
    mac_edit = mac.split('CommandGroup(replacing: .pasteboard)', 1)[1].split('CommandGroup(replacing: .textEditing)', 1)[0]
    win_edit = windows.split('Menu("Edit",', 1)[1].split('Menu("View",', 1)[0]
    for action in ['edit', 'play', 'skip', 'synthesize', 'rewrite', 'import-audio', 'delete-audio', 'reanalyze']:
        command = 'segment-one-' + action
        if 'editor?.run("' + command + '")' not in mac_edit or 'Command("' + command + '")' not in win_edit:
            raise ValueError('Edit must mirror individual row actions: ' + command)
    if 'editor?.run("segment-delete-selected")' not in mac_edit or 'Command("segment-delete-selected")' not in win_edit:
        raise ValueError('Edit must retain deletion for any nonempty selection')

    mac_playback = mac.split('CommandMenu("Playback")', 1)[1].split('CommandMenu("Project")', 1)[0]
    win_playback = windows.split('Menu("Playback",', 1)[1].split('Menu("Project",', 1)[0]
    for command in ['segment-one-preview', 'segment-one-preview-stop']:
        if command in mac_edit or command in win_edit:
            raise ValueError('Narration playback belongs in Playback rather than Edit')
        if 'editor?.run("' + command + '")' not in mac_playback or 'Command("' + command + '")' not in win_playback:
            raise ValueError('Playback must expose guarded narration transport: ' + command)

    if 'Menu("Segment Narration"' not in mac_playback or 'Submenu("Segment Narration"' not in win_playback:
        raise ValueError('Segment narration transport must be grouped separately from video controls')
    if 'action != "segment-one-preview-stop" || selectedSegmentPreviewing' not in mac or 'id != "segment-one-preview-stop" || SingleSelectedSegment()' not in windows:
        raise ValueError('Stop narration must be hidden without an active preview for the selected row')
    if 'if action == "stop" { return videoPlaybackStarted }' not in mac or 'if (id == "stop") return videoPlaybackStarted;' not in windows:
        raise ValueError('Stop Video must be hidden before playback and after stopping')


def check_jump_to_time(mac, windows, context, playback, dialog, win_dialog):
    required = [
        ('jump-to-time', mac), ('Jump to Time…', mac),
        ('["play", "back", "forward", "jump-to-time"].contains(action)', mac),
        ('case "jump-to-time": return canJumpToTime', mac),
        ('Command("jump-to-time")', windows), ('case "jump-to-time": await ShowJumpToTimeAsync()', windows),
        ('"play" or "back" or "forward" or "jump-to-time"', windows),
        ('case "jump-to-time": return double.IsFinite(p.Duration) && p.Duration > 0', windows),
        ('playback.goTo(seconds)', context), ('!showingJumpToTime', context),
        ('if playbackActive { play(from: seconds) }', playback),
        ('player?.pauseVideo()', playback),
        ('JumpTime.parse(time, duration: duration)', dialog), ('.disabled(target == nil)', dialog),
        ('Button("Jump", action: submit)', dialog), ('Button("Cancel")', dialog), ('.contextMenu', dialog),
        ('var wasPlaying = IsVideoPlaying()', win_dialog), ('await SeekAsync(target)', win_dialog),
        ('wasPlaying ? "window.vidiPlay?.()" : "window.vidiPause?.()"', win_dialog),
        ('JumpTime.Parse(input.Text, project.Duration)', win_dialog),
        ('dialog.PrimaryButtonClick', win_dialog), ('content.ContextFlyout = menu', win_dialog),
    ]
    for token, source in required:
        if token not in source:
            raise ValueError('Jump to Time transport/dialog contract missing: ' + token)


def check_export_completion_sound(mac, windows):
    """All four sound rows share preview/menu dispatch and persistent toggle state."""
    choices = [
        ('Sound when narration is off', 'soundWhenNarrationOff', 'Boink3', 'narration-off-sound'),
        ('Sound when synthesized audio is unavailable', 'soundWhenNarrationMissing', 'ascend', 'narration-missing-sound'),
        ('Play sound after export', 'soundAfterExport', 'descend', 'export-completion-sound'),
        ('Sound when timing validation fails', 'soundWhenTimingInvalid', 'Buzzer1', 'timing-validation-sound'),
    ]
    for label, key, resource, identifier in choices:
        for token in (f'SettingsSoundRow(title: "{label}", resource: "{resource}"',
                      f'menuIdentifier: "{identifier}-menu"', f'enabled: $studio.settings.{key}, preview: soundPreview'):
            if token not in mac: raise ValueError('Mac sound preference mapping missing: ' + token)
        token = f'AddSoundPreference(narrationGroup, "{label}", "{key}", "{resource}", "{identifier}", "{identifier}-menu")'
        if token not in windows: raise ValueError('Windows sound preference mapping missing: ' + token)
    for token in ('Toggle(title, isOn: $enabled).accessibilityIdentifier(menuIdentifier)',
                  'Button(previewTitle) { preview.toggle(resource) }',
                  'Button { preview.toggle(resource) } label:',
                  'preview.isPlaying(resource) ? "Pause" : "Play"',
                  '.accessibilityIdentifier(identifier + "-preview-menu")',
                  '.onChange(of: section) { _, _ in soundPreview.stop() }'):
        if token not in mac: raise ValueError('Mac preview/menu state contract missing: ' + token)
    for token in ('SettingsStore.GetBool(draft[key], true)',
                  'choice.IsChecked = toggle.IsOn',
                  'choice.Click += (_, _) => toggle.IsOn = choice.IsChecked;',
                  'toggle.Toggled += (_, _) => draft[key] = toggle.IsOn;',
                  'toggle.ContextFlyout = menu;',
                  'preview.Click += (_, _) => ToggleSoundPreview(resource);',
                  'previewItem.Click += (_, _) => ToggleSoundPreview(resource);',
                  'soundPreview.IsPlaying(resource) ? "Pause" : "Play"',
                  'soundPreview.Dispose();'):
        if token not in windows: raise ValueError('Windows preview/menu state contract missing: ' + token)

    for token in ('restore-speech-defaults-menu', 'restore-highlight-defaults-menu'):
        if token not in mac or token not in windows: raise ValueError('Missing matching Narration restore menu: ' + token)


def check_summary_highlight_appearance(mac, model, readback, windows, voices):
    appearance = mac[mac.index('private var appearanceSections:'):mac.index('private func summaryColorBinding(')]
    narration = mac[mac.index('if section == "Narration"'):mac.index('if section == "Developer prompts"')]
    if 'summaryHighlightSection' not in appearance or 'Summary readback' in narration:
        raise ValueError('Mac summary highlighting must live only in Appearance')
    if 'summaryControls' in voices or 'summaryOnly' in windows:
        raise ValueError('Windows summary highlighting must live only in Appearance')
    for label, key, identifier in [('Highlight the spoken sentence','summarySentenceHighlightEnabled','summary-sentence-highlight'),('Highlight the spoken word','summaryWordHighlightEnabled','summary-word-highlight')]:
        if mac.count(f'Toggle("{label}", isOn: $studio.settings.{key})') != 2:
            raise ValueError('Missing shared Mac highlight switch/menu state: ' + key)
        if f'{identifier}-menu' not in mac or identifier not in windows:
            raise ValueError('Missing highlight menu ID: ' + identifier)
        if f'var {key} = true' not in model: raise ValueError('Highlight default must preserve enabled behavior')
        if key not in readback: raise ValueError('Highlight switch is not wired into native rendering')
    for token in ('menu.Opening += (_, _) => choice.IsChecked = toggle.IsOn;', 'choice.Click += (_, _) => toggle.IsOn = choice.IsChecked;', 'toggle.ContextFlyout = menu;'):
        if token not in windows: raise ValueError('Windows highlight state/menu route missing: ' + token)
    if 'if highlightSentence {' not in readback or 'if highlightWord, let wordRange' not in readback:
        raise ValueError('Summary highlighting must be independent')


def check_search_highlight_settings(mac, windows):
    for label in ('Highlight search matches', 'Search highlight color', 'Search Highlight Color…'):
        if label not in mac or label not in windows: raise ValueError('Search highlight setting/menu label differs: ' + label)
    for identifier in ('search-highlight-menu', 'search-highlight-color-menu'):
        if identifier not in mac or identifier not in windows: raise ValueError('Missing search highlight menu: ' + identifier)
    if mac.count('Toggle("Highlight search matches", isOn: $studio.settings.searchHighlightEnabled)') != 2:
        raise ValueError('Mac search highlight toggle/menu must share state')
    if 'well.activate(true)' not in mac or 'searchHighlightColorRequest += 1' not in mac:
        raise ValueError('Mac search color menu must activate its native color well')
    for token in ('searchHighlightChoice.IsChecked = searchHighlight.IsOn', 'searchHighlight.IsOn = searchHighlightChoice.IsChecked', 'searchColor.Flyout.ShowAt(searchColor)'):
        if token not in windows: raise ValueError('Windows search highlight menu dispatch missing: ' + token)


def check_all_highlight_defaults(mac, model, windows):
    for source, marker in ((mac, 'private var appearanceSections:'), (windows, 'private void BuildAppearance(')):
        body = source[source.index(marker):]
        if body.index('Search highlight color') >= body.index('Button("Restore Highlight Defaults"' if source == mac else 'var restoreHighlights = new Button'):
            raise ValueError('Restore Highlight Defaults must be below search highlighting')
        if 'restore-highlight-defaults-menu' not in source: raise ValueError('Missing shared all-highlight restore menu')
    if mac.count('studio.settings.restoreHighlightDefaults()') != 2: raise ValueError('Mac restore control/menu must share the all-highlight action')
    action = model[model.index('mutating func restoreHighlightDefaults()'):model.index('mutating func restoreCaptionAppearanceDefaults()')]
    for token in ('summarySentenceHighlightEnabled = true', 'summaryWordHighlightEnabled = true', 'searchHighlightEnabled = true', 'searchHighlightColor = ProjectSearchHighlight.defaultColor'):
        if token not in action: raise ValueError('Mac restore omits a highlight preference: ' + token)
    action = windows[windows.index('void RestoreHighlights()'):windows.index('restoreHighlights.Click')]
    for key in ('summarySentenceHighlightColor', 'summaryWordHighlightColor', 'summarySentenceHighlight', 'summaryWordHighlight', 'searchHighlightEnabled', 'searchHighlightColor'):
        if 'draft["' + key + '"] =' not in action: raise ValueError('Windows restore omits ' + key)
