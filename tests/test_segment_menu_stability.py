"""Repeated view refreshes must not replace unchanged native row menus."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_contextual_menus import MAC, WIN


class SegmentMenuStability(unittest.TestCase):
    def test_native_presentation_is_stable_but_actions_remain_current(self):
        source=MAC/'VidiStudio/SegmentActionsMenu.swift'
        harness='''import AppKit
@main struct Main { @MainActor static func main() {
 let coordinator=SegmentActionsMenu.Coordinator()
 var calls=0
 let first=SegmentActionsMenu.Action(title:"Edit",systemImage:"pencil",perform:{calls+=1})
 precondition(coordinator.updateActions([first],enabled:true))
 for _ in 0..<100 { precondition(!coordinator.updateActions([first],enabled:true)) }
 let updated=SegmentActionsMenu.Action(title:"Edit",systemImage:"pencil",perform:{calls+=10})
 precondition(!coordinator.updateActions([updated],enabled:true))
 let item=NSMenuItem();item.tag=0;coordinator.performAction(item)
 precondition(calls==10,"An unchanged menu must still dispatch the latest closure")
 precondition(coordinator.updateActions([updated],enabled:false));coordinator.performAction(item);precondition(calls==10)
 precondition(coordinator.updateActions([updated],enabled:true))
 let renamed=SegmentActionsMenu.Action(title:"Done",systemImage:"pencil",perform:{})
 precondition(coordinator.updateActions([renamed],enabled:true))
 let divided=SegmentActionsMenu.Action(title:"Done",systemImage:"pencil",separatorBefore:true,perform:{})
 precondition(coordinator.updateActions([divided],enabled:true))
 print("PASS: 100 unchanged render passes reuse menu items; closure, title, availability and group updates remain correct")
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);(path/'Main.swift').write_text(harness)
            result=subprocess.run(['xcrun','swiftc','-parse-as-library',str(source),str(path/'Main.swift'),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_app_icons_are_visible_without_replacing_images_or_system_items(self):
        source=MAC/'VidiStudio/NativeMenuIcons.swift'
        from tests.test_contextual_menus import declaration
        import re, json
        shortcut=declaration((MAC/'VidiStudio/KeyboardShortcuts.swift').read_text(),'struct StudioShortcut:')
        commands=(MAC/'VidiStudio/KeyboardShortcuts.swift').read_text()+(MAC/'VidiStudio/VidiStudioApp.swift').read_text()
        titles=sorted(set(re.findall(r'(?:Button|Menu)\("([^"\n]+)", systemImage: "[^"]+"', commands)))
        harness='''import AppKit
import SwiftUI
'''+shortcut+'''

@main struct Main { @MainActor static func main() {
 let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
 NativeMenuIcons.shortcutSymbols = Dictionary((StudioShortcut.editor + StudioShortcut.youtube).map { ($0.title,$0.icon) },uniquingKeysWith:{ first,_ in first })
 let menu=NSMenu(); let names=["New Project…","Open Project Folder…","My YouTube Videos…","Settings…","Close","Language and Saved Results…","Show Transcript","Pause Video","Copy and Translate…","Edit Transcript Segments","Open in New Window","Rename Project…","Open in YouTube","Open Project Settings…","Open in Project Folder","Open Project Configuration","Analysis","Export…","Remove from List","Choose What to Delete…","Delete Project…"]
 for name in names + (StudioShortcut.editor + StudioShortcut.youtube).map({ $0.title }) {menu.addItem(NSMenuItem(title:name,action:nil,keyEquivalent:""))}
 let system=NSMenuItem(title:"Ask Siri",action:nil,keyEquivalent:"");menu.addItem(system)
 for name in '''+json.dumps(titles,ensure_ascii=False)+''' {menu.addItem(NSMenuItem(title:name,action:nil,keyEquivalent:""))}
 menu.removeItem(system);menu.addItem(system)
 NativeMenuIcons.applyApplicationItems(to:menu)
 let images=menu.items.dropLast().map { $0.image! }
 for _ in 0..<100 { NativeMenuIcons.applyApplicationItems(to:menu) }
 for (index,item) in menu.items.dropLast().enumerated() {
  precondition(item.image === images[index],"Unchanged icon must retain identity")
  if #available(macOS 27.0,*) { precondition(item.preferredImageVisibility == .visible) }
 }
 precondition(system.image == nil,"System commands must remain untouched during tracking")
 print("PASS: app menu icons remain visible and stable across 100 refreshes")
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);(path/'Main.swift').write_text(harness)
            result=subprocess.run(['xcrun','swiftc','-parse-as-library',str(source),str(path/'Main.swift'),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_idle_editor_does_not_publish_preview_timer_ticks(self):
        content=(MAC/'VidiStudio/ContentView.swift').read_text()
        self.assertNotIn('Timer.publish(every: 0.2, on: .main, in: .common)',content)
        self.assertIn('.task(id: activePreviewCueID)',content)
        self.assertIn('guard let cueID = activePreviewCueID else { return }',content)
        source=(MAC/'VidiStudio/SegmentActionsMenu.swift').read_text()
        self.assertIn('guard context.coordinator.updateActions(actions, enabled: enabled) else { return }',source)
        windows=(WIN/'Vidi Studio Windows/MainWindow.Menus.cs').read_text()
        self.assertIn('if (!SameMenuIcon(item.Icon, nextIcon)) item.Icon = nextIcon;',windows)
        self.assertIn('if (item.Text != title) item.Text = title;',windows)
        self.assertIn('desktopPlaybackWasPlaying == playing && desktopPlaybackWasStarted == videoPlaybackStarted',windows)

    def test_video_ticks_and_callback_refreshes_do_not_invalidate_command_menus(self):
        source=(MAC/'VidiStudio/PlaybackModel.swift').read_text()
        self.assertIn('if self.playing != playing { self.playing = playing }',source)
        self.assertIn('if self.buffering != buffering { self.buffering = buffering }',source)
        self.assertIn('if playback.playing != playing { playback.playing = playing }',source)
        commands=(MAC/'VidiStudio/KeyboardShortcuts.swift').read_text()
        self.assertIn('@ObservationIgnored var handler:',commands)
        self.assertIn('@ObservationIgnored var copyHandler:',commands)
        content=(MAC/'VidiStudio/ContentView.swift').read_text()
        self.assertIn('shortcutActions.resultProject?.updatedAt != project.updatedAt',content)

    def test_native_notification_burst_cannot_redecorate_an_open_menu(self):
        from tests.test_contextual_menus import declaration
        source=(MAC/'VidiStudio/VidiStudioApp.swift').read_text()
        delegate=declaration(source,'final class VidiStudioAppDelegate:')
        harness='''import AppKit
struct StudioShortcut {
 let title:String;let icon:String
 static let editor:[StudioShortcut]=[];static let youtube:[StudioShortcut]=[]
}
@MainActor enum NativeMenuIcons {
 static var shortcutSymbols:[String:String]=[:]
 static var calls=0
 static func applyApplicationItems(to menu:NSMenu) {}
 static func apply(to menu:NSMenu,isMenuBar:Bool=false) {
  calls+=1
  NotificationCenter.default.post(name:NSMenu.didChangeItemNotification,object:menu)
 }
}
@MainActor
'''+delegate+'''
@main struct Main { @MainActor static func main() {
 let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
 let root=NSMenu();let top=NSMenuItem(title:"Edit",action:nil,keyEquivalent:"");let edit=NSMenu(title:"Edit");top.submenu=edit;root.addItem(top);app.mainMenu=root
 edit.addItem(NSMenuItem(title:"Copy",action:NSSelectorFromString("copy:"),keyEquivalent:"c"))
 let autofill=NSMenuItem(title:"AutoFill",action:nil,keyEquivalent:"");autofill.submenu=NSMenu();edit.addItem(autofill)
 edit.addItem(NSMenuItem(title:"Start Dictation",action:NSSelectorFromString("startDictation:"),keyEquivalent:""))
 edit.addItem(NSMenuItem(title:"Copy and Translate…",action:NSSelectorFromString("privateSwiftUIBridgeAction:"),keyEquivalent:""))
 edit.addItem(NSMenuItem(title:"Edit Transcript Segments",action:nil,keyEquivalent:""))
 let delegate=VidiStudioAppDelegate()
 func drain() { RunLoop.main.run(until:Date().addingTimeInterval(0.05)) }
 delegate.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
 drain();let baseline=NativeMenuIcons.calls
 precondition(baseline==1,"Decoration must not recursively schedule itself")
 precondition(edit.items.map { $0.title }==["Copy and Translate…","Edit Transcript Segments"],"Edit must retain app actions while removing native clipboard, AutoFill and Dictation")
 for _ in 0..<100 {NotificationCenter.default.post(name:NSMenu.didChangeItemNotification,object:edit)}
 drain();precondition(NativeMenuIcons.calls==baseline+1,"Closed-menu bursts must coalesce")
 let beforeOpening=NativeMenuIcons.calls
 NotificationCenter.default.post(name:NSMenu.didBeginTrackingNotification,object:root)
 let opened=NativeMenuIcons.calls
 precondition(opened==beforeOpening,"Beginning menu tracking must not decorate the root menu bar")
 for _ in 0..<100 {NotificationCenter.default.post(name:NSMenu.didChangeItemNotification,object:edit)}
 drain();precondition(NativeMenuIcons.calls==opened,"An open menu must not be repainted asynchronously")
 NotificationCenter.default.post(name:NSMenu.didEndTrackingNotification,object:root)
 drain();precondition(NativeMenuIcons.calls==opened+1,"Closing must flush one deferred decoration pass")
 delegate.applicationWillTerminate(Notification(name:NSApplication.willTerminateNotification))
 print("PASS: 100 changes coalesce while closed, 100 changes cause no repaint while tracking, own changes do not recurse")
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);(path/'Main.swift').write_text(harness)
            result=subprocess.run(['xcrun','swiftc','-parse-as-library',str(path/'Main.swift'),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_edit_group_replaces_native_defaults_and_routes_text_shortcuts(self):
        commands=(MAC/'VidiStudio/KeyboardShortcuts.swift').read_text()
        app=(MAC/'VidiStudio/VidiStudioApp.swift').read_text()
        self.assertIn('CommandMenu("Edit") {',commands)
        self.assertIn('CommandGroup(replacing: .textFormatting) { }',commands)
        self.assertIn('CommandGroup(replacing: .pasteboard)',commands)
        self.assertIn('CommandGroup(replacing: .undoRedo) { }',commands)
        self.assertIn('self.removeSystemEditCommands()',app)
        self.assertIn('systemTitles.contains(item.title)',app)
        self.assertIn('let actions = ["x": "cut:", "c": "copy:", "v": "paste:", "a": "selectAll:"]',app)
        self.assertIn('text.undoManager',app)
