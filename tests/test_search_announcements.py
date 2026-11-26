"""Rapid input announces the final visible count and cancels stale speech."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_contextual_menus import MAC, declaration


class SearchAnnouncements(unittest.TestCase):
    def test_native_announcement_debounce_clear_and_cancellation(self):
        source = (MAC / 'VidiStudio/ProjectSearchResultsView.swift').read_text()
        scheduler = declaration(source, 'final class SearchAnnouncementDebouncer')
        harness = '''import AppKit
@MainActor
''' + scheduler + '''
@main struct Main { @MainActor static func main() {
 let scheduler=SearchAnnouncementDebouncer();var spoken:[String]=[]
 func drain() {RunLoop.main.run(until:Date().addingTimeInterval(0.42))}
 func update(_ query:String,_ message:String,_ revision:Int=0) {scheduler.update(query:query,status:message,revision:revision){spoken.append($0)}}
 update("","cleared");drain();precondition(spoken.isEmpty,"Initial idle windows must stay silent")
 update("a","2 results");update("ab","0 results");drain();precondition(spoken==["0 results"],"Rapid typing must replace the pending count")
 update("abc","0 results");drain();precondition(spoken==["0 results","0 results"],"A different query needs an announcement even if its count is unchanged")
 update("abc","0 results");drain();precondition(spoken.count==2,"Unchanged render updates must stay silent")
 update("Command + Shift + J","1 shortcut found",1);drain();precondition(spoken.last=="1 shortcut found" && spoken.count==3)
 update("Command + Shift + J","1 shortcut found",2);drain()
 precondition(spoken.count==4,"Pressing the same shortcut again must announce the count")
 update("summary","7 shortcuts found",2);drain();precondition(spoken.last=="7 shortcuts found")
 update("","cleared",2);drain();precondition(spoken.last=="cleared")
 update("cancel","No shortcuts found",2);scheduler.cancel();drain();precondition(spoken.count==6,"Detached views must cancel pending speech")
 print("PASS: coalesced counts, repeated captures, changed queries, clearing and cancellation")
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'Main.swift').write_text(harness)
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path / 'Main.swift'), '-o', str(path / 'check')], capture_output=True, text=True)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(path / 'check')], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
