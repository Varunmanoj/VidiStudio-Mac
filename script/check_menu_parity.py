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
runpy.run_path(str(checker), run_name='__main__')
