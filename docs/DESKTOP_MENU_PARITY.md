# Desktop menu contract

Mac is the reference layout. Windows' shared menus follow this order:

- **File:** New Project, Open Project Folder, Export. Native Windows additions: Open Editor in New Window, Settings, Close Window.
- **View:** Preview, Timeline; Project List visibility, Inspector visibility; Project List View, Project Grid View.
- **Playback:** Preview, Full-Screen Video, Play/Pause, Stop Video, Rewind/Fast Forward 5 Seconds, Toggle Narration.
  - **Transcript Overlay:** Cycle; Off, Transcript, AD Transcript.
  - **Summary Reading:** Play/Resume, Pause, Stop; Read from Start, Read from Selection, Read Selected Text.
- **Project:**
  - **Editor Sections:** Transcript, Summary, Descriptions, AD Overview, AD Transcript.
  - **Segments:** Edit Mode, Add; Re-Analyze a Video Section, Select All, Deselect All, Edit Selected, Delete Selected; Follow, Undo, Redo.
  - **Analysis:** Analyze Video; Video Details/Timeline Pictures, Transcript, Summary.
  - **Narration:**
    - **AD Segment Generation:** Generate/Regenerate Audio Descriptions; Delete Descriptions.
    - **Narration Audio:** Synthesize, Synthesize Changed Segments, Regenerate All Narration…, Review Narration Issues, Review Narration Voices; Delete All Narration Audio.
  - Delete Current Page; Show Project in Finder/File Explorer.
- **Help:** VidiStudio Help; About is here on Windows and in the native app menu on Mac.

The source declarations, not this summary, determine current labels, separators, and actions. Mac retains OS-owned app, standard Edit, and Window menus; Windows retains its system window menu/title-bar controls. Windows uses F1 for Help. Windows full-screen video is available for local media; the YouTube player owns its own full-screen action. Windows rendered-summary selection is paragraph based; Mac additionally supports a zero-length reading anchor.

## Shortcuts

Translate Command to Ctrl and Option to Alt. Standard text editing retains native Ctrl/Command+C/X/V/Z. Segment history uses the separate Ctrl/Command+Alt/Option+Z bindings. Native exceptions:

| Action | Mac | Windows |
|---|---|---|
| Overlay Off / Transcript / AD Transcript | Command+Control+0/1/2 | Ctrl+Alt+Shift+0/1/2 |
| Delete selected segments | Command+Control+Delete | Ctrl+Shift+Delete |
| Delete all narration | Command+Option+Delete | Ctrl+Alt+Backspace (Ctrl+Alt+Delete is reserved) |
| Help | Command+Option+/ | F1 |

Deselect All uses Command+Option+Shift+U / Ctrl+Alt+Shift+U to avoid colliding with Analyze Video. Ctrl+Shift+D toggles narration on Windows, matching Mac; it no longer generates all narration.

Regenerate All Narration uses the same guarded command from the Inspector and menu on both desktops (no shortcut). Confirmation names the selected voice and warns that every segment's generated audio will be replaced, keeping text and timing. Full regeneration bypasses repair-only preservation of usable audio; each old file is retained until its replacement succeeds. The project's primary narration engine/voice is saved before the first segment is attempted and immediately refreshed in the UI, even if generation later fails or is canceled. Failed segments retain their actual old audio/voice metadata, never relabeled as the new voice; successfully regenerated segments match the new primary voice. Full regeneration reports actual synthesis failures instead of automatically opening an additional mixed-voice dialog on Windows.

The Narration menu mirrors the Inspector's separate AD generation and narration audio groups using native nested submenus. Audio Description generation moved from Analysis into AD Segment Generation; its Command+Option+Shift+D / Ctrl+Alt+Shift+D shortcut and prerequisites are unchanged. Description deletion targets descriptions regardless of the active editor section and uses the existing confirmation. Review Narration Voices remains directly after Review Narration Issues inside Narration Audio.

## Keeping parity

For any menu change, update both implementations, behavior/availability, shortcuts, native smoke expectations, and the checker as necessary. Run `python3 script/check_menu_parity.py` from the combined workspace or either desktop, then each desktop's `tests.test_menu_parity`. The checker compares actual hierarchy/order/separators, common labels, handler coverage, and translated editor shortcuts and rejects collisions. Mutation tests demonstrate that missing/moved actions, wrong labels, unwired commands, and conflicts fail.

Build and pre-commit scripts invoke the checker. Outside the combined workspace they explicitly skip; this does not validate parity. Windows UI smoke tests still require a Windows host.
