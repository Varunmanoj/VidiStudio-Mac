from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


class InspectorGroups(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        if not (root / 'VidiStudio Mac/VidiStudio/ContentView.swift').is_file() or not (root / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.xaml').is_file():
            raise unittest.SkipTest('Inspector grouping checks require the combined desktop workspace.')

    def test_mac_separates_segment_and_audio_controls(self):
        root = Path(__file__).resolve().parents[2]
        source = (root / 'VidiStudio Mac/VidiStudio/ContentView.swift').read_text()
        start = source.index('GroupBox(editorActions.activeSection == "descriptions" ? "AD Segment Generation"')
        audio = source.index('GroupBox("Narration Audio")', start)
        end = source.index('GroupBox("Export")', audio)
        generation = source[start:audio]
        narration = source[audio:end]
        self.assertIn('editorActions.run(action)', generation)
        self.assertIn('Button("Undo Segment Edit"', generation)
        self.assertNotIn('editorActions.run("synthesize-tts")', generation)
        for command in ('synthesize-tts', 'synthesize-changed'):
            self.assertIn(f'editorActions.run("{command}")', narration)
        self.assertNotIn('Button("Undo Segment Edit"', narration)

    def test_windows_has_separate_sibling_groups(self):
        root = Path(__file__).resolve().parents[2]
        path = root / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.xaml'
        tree = ET.parse(path)
        names = {e.get('{http://schemas.microsoft.com/winfx/2006/xaml}Name'): e for e in tree.iter()}
        parents = {child: parent for parent in tree.iter() for child in parent}
        generation, narration = names['ContextActions'], names['NarrationActions']
        self.assertIs(parents[generation], parents[narration])
        self.assertIn(names['InspectorGenerate'], list(generation.iter()))
        self.assertIn(names['InspectorRewriteButton'], list(generation.iter()))
        for name in ('InspectorSynthesizeNarrationButton', 'InspectorSynthesizeChangedButton'):
            self.assertIn(names[name], list(narration.iter()))
            self.assertNotIn(names[name], list(generation.iter()))
        self.assertTrue(any(e.get('Text') == 'Narration Audio' for e in narration.iter()))
        self.assertNotIn('InspectorRegenerateAllNarrationButton', names)
        self.assertNotIn('InspectorNarrateSelectedButton', names)


if __name__ == '__main__':
    unittest.main()
