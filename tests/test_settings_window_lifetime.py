"""Settings follows actual main-window closes, including multiple and hidden windows."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_contextual_menus import MAC, WIN, declaration


class SettingsWindowLifetime(unittest.TestCase):
    def test_native_main_window_lifetime_closes_only_orphaned_settings(self):
        source = (MAC / 'VidiStudio/SettingsWindowChrome.swift').read_text()
        policy = declaration(source, 'enum AppWindowLifetime')
        harness = '''import AppKit
@MainActor
''' + policy + '''
@main struct Main { @MainActor static func main() {
 let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
 func window()->NSWindow {let value=NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:200),styleMask:[.titled,.closable],backing:.buffered,defer:false);value.isReleasedWhenClosed=false;return value}
 func drain() {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
 let first=window(),second=window(),settings=window();var settingsClosed=false
 let observer=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:settings,queue:.main){_ in settingsClosed=true}
 AppWindowLifetime.registerMainWindow(first);AppWindowLifetime.registerMainWindow(second);AppWindowLifetime.registerSettingsWindow(settings)
 drain();precondition(!settingsClosed)
 first.close();drain();precondition(!settingsClosed,"Another main window must keep Settings open")
 second.orderOut(nil);drain();precondition(!settingsClosed,"Hidden or minimized main windows are still open")
 second.close();drain();precondition(settingsClosed,"The final main window must close Settings")
 NotificationCenter.default.removeObserver(observer)
 let orphan=window();var orphanClosed=false
 let orphanObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:orphan,queue:.main){_ in orphanClosed=true}
 AppWindowLifetime.registerSettingsWindow(orphan);drain();precondition(orphanClosed,"Settings cannot open by itself")
 NotificationCenter.default.removeObserver(orphanObserver)
 let original=window(),replacement=window(),preferences=window();var preferencesClosed=false
 let replacementObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:preferences,queue:.main){_ in preferencesClosed=true}
 AppWindowLifetime.registerMainWindow(original);AppWindowLifetime.registerSettingsWindow(preferences);drain()
 original.close();AppWindowLifetime.registerMainWindow(replacement);drain();precondition(!preferencesClosed,"A replacement main window must prevent premature closure")
 replacement.close();drain();precondition(preferencesClosed)
 NotificationCenter.default.removeObserver(replacementObserver)
 print("PASS: multi-window, hidden-window, final close, orphan opening and replacement-window Settings lifetime")
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'Main.swift').write_text(harness)
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path / 'Main.swift'), '-o', str(path / 'check')], capture_output=True, text=True)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(path / 'check')], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_all_main_scenes_register_and_windows_uses_live_main_window_count(self):
        app = (MAC / 'VidiStudio/VidiStudioApp.swift').read_text()
        self.assertEqual(app.count('.background(MainWindowLifetime().frame(width: 0, height: 0))'), 4)
        windows = (WIN / 'Vidi Studio Windows/App.xaml.cs').read_text()
        self.assertIn('internal static bool HasMainWindows => Windows.Count > 0;', windows)
        projects = (WIN / 'Vidi Studio Windows/Views/SettingsDialog.Projects.cs').read_text()
        self.assertIn('if (!closed && !App.HasMainWindows) { Hide(); return; }', projects)
