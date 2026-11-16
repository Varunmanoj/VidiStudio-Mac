#!/usr/bin/env python3
"""Architecture guards for paired desktop forms; native geometry remains a separate required check."""
import argparse
import re
from pathlib import Path

MAC_FILES = ('SettingsView.swift', 'ImportAssetsView.swift', 'ExportOptionsMenu.swift',
             'GeminiAPISettingsView.swift', 'SarvamVoiceSettingsView.swift')
WIN_FILES = ('Views/CompactDialogLayout.cs', 'Views/WindowAppearance.cs',
             'Views/SettingsDialog.Compact.cs', 'Views/SettingsDialog.Layout.cs',
             'Views/SettingsDialog.SpeechLayout.cs', 'MainWindow.DialogLayoutSmoke.cs')

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
    for path in ('SettingsView.swift', 'ImportAssetsView.swift', 'ExportOptionsMenu.swift'):
        require('Mac/' + path, '.formStyle(.grouped)', 'retain native compact grouped forms')
        require('Mac/' + path, 'Section', 'retain section grouping')
    for path, titles in (
        ('GeminiAPISettingsView.swift', ('Check API Key', 'Open API Keys in Google AI Studio')),
        ('SarvamVoiceSettingsView.swift', ('Check API Key', 'Open Sarvam API Keys')),
        ('ImportAssetsView.swift', ('Distribute Evenly', 'Auto-time with Gemini'))):
        if not any(all(title in block for title in titles) for block in swift_blocks(source['Mac/' + path], 'HStack')):
            raise ValueError('Mac/' + path + ': related actions must share a horizontal row')
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
        print('PASS: Mac grouped forms/adjacent actions and Windows shared responsive, accessible, theme-aware forms; native geometry guards retained.')
