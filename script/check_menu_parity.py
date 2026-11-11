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
print('PASS: desktop tab/source visibility and menu/shortcut guards match.')

runpy.run_path(str(checker), run_name='__main__')
