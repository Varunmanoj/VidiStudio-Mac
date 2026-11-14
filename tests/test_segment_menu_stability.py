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
 let menu=NSMenu(); let names=["Project Language","VidiStudio","My YouTube Videos","YouTube Details","New Project…","Open Project Folder…","My YouTube Videos…","Settings…","Close","Language and Saved Results…","Show Transcript","Pause Video","Copy and Translate…","Edit Transcript Segments","Open in New Window","Rename Project…","Open in YouTube","Open Project Settings…","Open in Project Folder","Open Project Configuration","Analysis","Export…","Remove from List","Choose What to Delete…","Delete Project…"]
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

    def test_app_owned_presentation_survives_native_rebuilds_without_mutating_sources(self):
        harness='''import AppKit
@MainActor final class Target:NSObject {
 var calls=0
 @objc func search(_ sender:Any?) {calls+=1}
}
@main struct Main { @MainActor static func main() {
 let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
 let model=NSMenu();let target=Target()
 func branch(_ title:String,_ items:[NSMenuItem])->NSMenuItem {
  let top=NSMenuItem(title:title,action:nil,keyEquivalent:"");let menu=NSMenu(title:title)
  menu.autoenablesItems=false;menu.items=items;top.submenu=menu;return top
 }
 let search=NSMenuItem(title:"Search Project…",action:#selector(Target.search(_:)),keyEquivalent:"f");search.target=target
 let clear=NSMenuItem(title:"Clear Search",action:#selector(Target.search(_:)),keyEquivalent:"");clear.target=target;clear.isEnabled=false
 let custom=branch("Edit",[search,.separator(),clear]);let sourceEdit=custom.submenu!
 let generated=branch("Edit",[NSMenuItem(title:"Copy",action:nil,keyEquivalent:"c")])
 let format=branch("Format",[NSMenuItem(title:"Font",action:nil,keyEquivalent:"")])
 let file=branch("File",[]);let view=branch("View",[])
 model.items=[file,custom,generated,format,view];app.mainMenu=model
 // Simulate SwiftUI creating brand-new rows when the user actually opens File.
 final class Rebuild:NSObject,NSMenuDelegate {
  func menuNeedsUpdate(_ menu:NSMenu) {
   menu.items=["New Project…","Export…","Close"].map {NSMenuItem(title:$0,action:nil,keyEquivalent:"")}
  }
 }
 let rebuild=Rebuild();file.submenu!.delegate=rebuild
 let controller=AppMenuController();controller.start()
 file.submenu!.delegate?.menuNeedsUpdate?(file.submenu!)
 precondition(file.submenu!.items.map{$0.title}==["New Project…","Export…","Close"])
 for item in file.submenu!.items {
  precondition(item.image != nil,"Opening-time rebuild lost icon for "+item.title)
  if #available(macOS 27.0,*) {precondition(item.preferredImageVisibility == .visible)}
 }
 func drain(){RunLoop.main.run(until:Date().addingTimeInterval(0.04))}
 let visible=app.mainMenu! // no run-loop drain before the initial layout check
 precondition(visible === model,"SwiftUI must retain main-menu ownership for focused scene values")
 precondition(visible.items.map{$0.title}==["File","Edit","View"])
 precondition(sourceEdit.items.count==3 && search.menu===sourceEdit,"Never modify source command models")
 let edit=visible.items[1].submenu!;let top=visible.items[1]
 precondition(top===custom && edit===sourceEdit,"Keep focused native command ownership")
 precondition(edit.items.map{$0.title}==["Search Project…","","Clear Search"])
 precondition(edit.items[0].keyEquivalent=="f" && !edit.items[2].isEnabled)
 edit.performActionForItem(at:0);precondition(target.calls==1,"Forward guarded native actions")
 let late=NSMenuItem(title:"Export…",action:nil,keyEquivalent:"")
 NotificationCenter.default.post(name:NSMenu.didBeginTrackingNotification,object:file.submenu!)
 file.submenu!.addItem(late)
 if #available(macOS 27.0,*) {precondition(late.preferredImageVisibility == .visible,"New items must request icons before the run loop drains")}
 late.image=NSImage(systemSymbolName:"square.and.arrow.up",accessibilityDescription:nil)
 if #available(macOS 27.0,*) {precondition(late.preferredImageVisibility == .visible)}
 NotificationCenter.default.post(name:NSMenu.didEndTrackingNotification,object:file.submenu!)
 let originalItems=sourceEdit.items
 for _ in 0..<100 {NotificationCenter.default.post(name:NSMenu.didChangeItemNotification,object:sourceEdit)}
 drain();precondition(app.mainMenu===visible && visible.items[1]===top,"Stable menu bar identity")
 precondition(sourceEdit.items.elementsEqual(originalItems,by:{$0===$1}))
 NotificationCenter.default.post(name:NSMenu.didBeginTrackingNotification,object:edit)
 for _ in 0..<50 { NotificationCenter.default.post(name:NSMenu.didChangeItemNotification,object:sourceEdit) }
 drain();precondition(edit.items.elementsEqual(originalItems,by:{$0===$1}),"Never repaint a tracking menu")
 NotificationCenter.default.post(name:NSMenu.didEndTrackingNotification,object:edit);drain()
 sourceEdit.removeItem(search)
 let replacement=NSMenu();replacement.items=[branch("File",[]),branch("Edit",[search]),branch("Format",[]),branch("View",[])]
 app.mainMenu=replacement
 precondition(app.mainMenu===replacement,"Never reenter AppKit during its main-menu setter")
 drain();precondition(app.mainMenu===replacement && replacement.items.map{$0.title}==["File","Edit","View"])
 let currentEdit=replacement.items[1].submenu!
 precondition(currentEdit !== edit && search.menu===currentEdit)
 let emoji=NSMenuItem(title:"Emoji & Symbols",action:nil,keyEquivalent:"")
 search.menu!.addItem(emoji)
 precondition(emoji.menu === currentEdit && !emoji.isHidden, "Never mutate AppKit's backing view during insertion")
 drain()
 precondition(emoji.menu == nil, "Filter late commands after native insertion finishes")
 currentEdit.delegate?.menuNeedsUpdate?(currentEdit)
 precondition(currentEdit.items.map{$0.title}==["Search Project…"],"Native additions must never appear in the open Edit menu")
 let focusedSearch=NSMenuItem(title:"Search Projects…",action:#selector(Target.search(_:)),keyEquivalent:"f");focusedSearch.target=target
 replacement.items=[branch("File",[]),branch("Edit",[focusedSearch]),branch("Format",[]),branch("View",[])]
 drain();precondition(app.mainMenu===replacement && replacement.items.map{$0.title}==["File","Edit","View"])
 precondition(replacement.items[1].submenu!.items[0].title=="Search Projects…", "In-place focus updates must refresh the current command model")
 replacement.items[1].submenu!.performActionForItem(at:0);precondition(target.calls==2)
 controller.stop()
 print("PASS: custom Edit remains stable through 100 notifications, 50 open-menu model rebuilds and root replacement; source ownership and actions stay intact")
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);(path/'Main.swift').write_text(harness)
            result=subprocess.run(['xcrun','swiftc','-parse-as-library',str(MAC/'VidiStudio/AppMenuController.swift'),str(MAC/'VidiStudio/NativeMenuIcons.swift'),str(path/'Main.swift'),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_edit_group_replaces_native_defaults_and_routes_text_shortcuts(self):
        commands=(MAC/'VidiStudio/KeyboardShortcuts.swift').read_text()
        app=(MAC/'VidiStudio/VidiStudioApp.swift').read_text()
        self.assertIn('CommandGroup(replacing: .pasteboard) {',commands)
        self.assertNotIn('CommandMenu("Edit")',commands)
        self.assertEqual(commands.count('CommandGroup(replacing: .pasteboard)'),1)
        self.assertNotIn('CommandGroup(replacing: .textFormatting)',commands)
        self.assertIn('CommandGroup(replacing: .pasteboard)',commands)
        self.assertIn('CommandGroup(replacing: .undoRedo) { }',commands)
        self.assertIn('private let menus = AppMenuController()',app)
        self.assertIn('menus.start()',app)
        self.assertIn('let actions = ["x": "cut:", "c": "copy:", "v": "paste:", "a": "selectAll:"]',app)
        self.assertIn('text.undoManager',app)
