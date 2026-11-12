from pathlib import Path
import runpy
import unittest

class JumpToTimeContract(unittest.TestCase):
    def test_state_validation_and_dialog_routes(self):
        root = Path(__file__).resolve().parents[2]
        check = runpy.run_path(str(root/'VidiStudio Mac/script/contextual_menu_contract.py'))['check_jump_to_time']
        sources = [(root/path).read_text() for path in [
            'VidiStudio Mac/VidiStudio/KeyboardShortcuts.swift',
            'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Menus.cs',
            'VidiStudio Mac/VidiStudio/ContentView.swift',
            'VidiStudio Mac/VidiStudio/PlaybackModel.swift',
            'VidiStudio Mac/VidiStudio/JumpToTime.swift',
            'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.JumpToTime.cs']]
        check(*sources)
        for index, token in [(2, 'playback.goTo(seconds)'), (3, 'if playbackActive { play(from: seconds) }'),
                             (4, '.disabled(target == nil)'), (5, 'await SeekAsync(target)'),
                             (5, 'content.ContextFlyout = menu')]:
            changed = sources.copy()
            changed[index] = changed[index].replace(token, '')
            with self.assertRaises(ValueError): check(*changed)
