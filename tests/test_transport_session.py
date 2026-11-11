"""Exercise production transport session state independently of media output."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_contextual_menus import declaration, MAC, WIN


class TransportSession(unittest.TestCase):
    def test_video_session_survives_pause_and_clears_on_stop(self):
        source=(MAC/'VidiStudio/PlaybackModel.swift').read_text()
        methods='\n'.join(declaration(source,marker) for marker in ('    var playing = false', '    var buffering = false', '    func pausePlayback()', '    func stopPlayback()'))
        harness='''import Foundation
struct Time { static let zero = Time() }
class Player { func pause() {} ; func seek(to: Time, toleranceBefore: Time, toleranceAfter: Time) {} }
class Web { func evaluateJavaScript(_ text: String, completionHandler: Any?) {} }
class Check { var videoPlaybackStarted = false; var time = 3.0; var indicatedSegment: String?; var player = Player(); var originalAudioPlayer = Player(); var webView: Web?
 func stopNarration() {}; func cancelPendingPlayback() {}
'''+methods+'''
}
@main struct Main { static func main() {
 let c=Check(); precondition(!c.videoPlaybackStarted)
 c.playing=true;precondition(c.videoPlaybackStarted)
 c.pausePlayback();precondition(!c.playing && c.videoPlaybackStarted && c.time == 3)
 c.stopPlayback();precondition(!c.videoPlaybackStarted && c.time == 0)
 c.buffering=true;precondition(c.videoPlaybackStarted)
 c.stopPlayback();precondition(!c.buffering && !c.videoPlaybackStarted)
 print("PASS: paused session retains Stop, stopped session hides Stop, buffering session supports Stop")
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);(path/'Main.swift').write_text(harness)
            result=subprocess.run(['xcrun','swiftc','-parse-as-library',str(path/'Main.swift'),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_stop_visibility_grouping_and_row_transport_match_on_both_desktops(self):
        mac=(MAC/'VidiStudio/ContentView.swift').read_text();win=(WIN/'Vidi Studio Windows/MainWindow.Commands.cs').read_text()
        row=mac.split('@ViewBuilder private func segmentRowContextMenu(',1)[1].split('private func runSegmentRowAction(',1)[0]
        availability=declaration(mac,'    private func canRunSegmentRowAction(')
        self.assertNotIn('transcriptRows',availability)
        self.assertIn('audioReady: action == "segment-one-preview" && !isPreviewing && playableNarrationURL',availability)
        self.assertIn('guard transcriptRows.contains(where: { $0.id == row.id }) else { return }',mac)
        self.assertGreaterEqual(row.count('Divider()'),5)
        self.assertIn('if row.isDescription && activePreviewCueID == row.segment.id {',row)
        self.assertIn('id == "segment-one-preview-stop" && !ReferenceEquals(previewingSegment, segment)',win)
        self.assertIn('"segment-one-delete-audio" or "segment-one-reanalyze"',win)
        xaml=(WIN/'Vidi Studio Windows/MainWindow.xaml').read_text()
        self.assertIn('Click="SegmentPreviewStop_Click"',xaml)
        self.assertIn('Visibility="{Binding IsPreviewing, Converter={StaticResource VisibleWhenTrue}}"',xaml)
        self.assertIn('if playing { summaryReader.stop() }\n            refreshEditorShortcutActions()',mac)
        self.assertIn('.onChange(of: playback.buffering) { _, _ in refreshEditorShortcutActions() }',mac)
        self.assertIn('if playback.videoPlaybackStarted {',(MAC/'VidiStudio/VideoPlaybackControls.swift').read_text())
        self.assertIn('VideoStopButton.Visibility = videoPlaybackStarted ? Visibility.Visible : Visibility.Collapsed;', (WIN/'Vidi Studio Windows/MainWindow.xaml.cs').read_text())
        self.assertIn('if (segmentPreviewPaused) speech.Play(); else speech.Pause();',(WIN/'Vidi Studio Windows/MainWindow.Presentation.cs').read_text())
