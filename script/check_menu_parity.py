#!/usr/bin/env python3
"""Run the combined-workspace desktop menu checker."""
from pathlib import Path
import runpy
import sys

checker = Path(__file__).resolve().parents[2] / 'script/check_menu_parity.py'
if not checker.is_file():
    if '--allow-missing' in sys.argv:
        print('SKIP: desktop menu parity requires the combined Mac/Windows workspace.')
        raise SystemExit(0)
    raise SystemExit('Desktop menu parity requires the combined Mac/Windows workspace.')
workspace = checker.parent.parent
contract = runpy.run_path(str(Path(__file__).with_name('contextual_menu_contract.py')))
contract['check_contextual_menus'](
    (workspace / 'VidiStudio Mac/VidiStudio/KeyboardShortcuts.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Menus.cs').read_text())
contract['check_row_more_actions'](
    (workspace / 'VidiStudio Mac/VidiStudio/ContentView.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Commands.cs').read_text(),
    (workspace / 'VidiStudio Mac/VidiStudio/LanguageResults.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.LanguageResults.cs').read_text())
contract['check_single_segment_commands'](
    (workspace / 'VidiStudio Mac/VidiStudio/KeyboardShortcuts.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Menus.cs').read_text(),
    (workspace / 'VidiStudio Mac/VidiStudio/ContentView.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Commands.cs').read_text())
contract['check_jump_to_time'](
    (workspace / 'VidiStudio Mac/VidiStudio/KeyboardShortcuts.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Menus.cs').read_text(),
    (workspace / 'VidiStudio Mac/VidiStudio/ContentView.swift').read_text(),
    (workspace / 'VidiStudio Mac/VidiStudio/PlaybackModel.swift').read_text(),
    (workspace / 'VidiStudio Mac/VidiStudio/JumpToTime.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.JumpToTime.cs').read_text())
contract['check_export_completion_sound'](
    (workspace / 'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text() + (workspace / 'VidiStudio Mac/VidiStudio/SettingsSoundPreview.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.cs').read_text() + (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Appearance.cs').read_text())
contract['check_summary_highlight_appearance'](
    (workspace / 'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text(),
    (workspace / 'VidiStudio Mac/VidiStudio/StudioModel.swift').read_text(),
    (workspace / 'VidiStudio Mac/VidiStudio/SummaryReadback.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Appearance.cs').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Voices.cs').read_text())
contract['check_search_highlight_settings'](
    (workspace / 'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Appearance.cs').read_text())
contract['check_all_highlight_defaults'](
    (workspace / 'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text(),
    (workspace / 'VidiStudio Mac/VidiStudio/StudioModel.swift').read_text(),
    (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Appearance.cs').read_text())
layout = runpy.run_path(str(Path(__file__).with_name('context_menu_layout_contract.py')))
layout['check_context_menu_layouts'](workspace)
print('PASS: desktop tab/source/mode guards and row More Actions match.')

runpy.run_path(str(checker), run_name='__main__')
