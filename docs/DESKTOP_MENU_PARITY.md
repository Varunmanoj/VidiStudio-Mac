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
    - **Narration Audio:** Generate/Regenerate All AD Audio, Generate Missing or Changed AD Audio, Review Narration Issues, Review Narration Voices; Delete All Narration Audio.
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

There are exactly two bulk audio commands in AD Overview, Inspector, and the menu on both desktops. `synthesize-tts` is labeled **Generate All AD Audio** before any segment has audio and **Regenerate All AD Audio…** once any segment has recorded audio. Both states always attempt every segment and save the selected primary engine/voice before generation starts, including when a later segment fails or the run is canceled. The initial run needs no replacement confirmation; subsequent runs use the same confirmation everywhere. The separate `regenerate-all-narration` entry was removed. Unqualified engine `synthesize-tts` is also a full run, so legacy callers cannot silently preserve usable audio or an obsolete primary voice.

`synthesize-changed` is labeled **Generate Missing or Changed AD Audio**. It is visible but disabled before any segment has generated audio, and enabled thereafter only if at least one segment is missing audio or has a text/timing/generation issue. It preserves valid audio and the primary voice. Single-segment generation remains in segment context menus, not as an extra Inspector bulk control. Full generation retains old files until replacements succeed; failed old files keep their truthful voice metadata. Actual generation failures are reported without an additional automatic mixed-voice dialog after a full run.

The Narration menu mirrors the Inspector's separate AD generation and narration audio groups using native nested submenus. Audio Description generation moved from Analysis into AD Segment Generation; its Command+Option+Shift+D / Ctrl+Alt+Shift+D shortcut and prerequisites are unchanged. Description deletion targets descriptions regardless of the active editor section and uses the existing confirmation. Review Narration Voices remains directly after Review Narration Issues inside Narration Audio.

Windows row/header More action buttons in Transcript, Descriptions, and AD Transcript are visible only in segment Edit mode, matching Mac's edit-only action controls. View-mode right-click/context menus and narration preview remain available. This changes the button entry point, not the underlying commands or shared menu hierarchy.

Narration preview mode restricts speech-engine selection to native local voices: Apple Speech on Mac; Windows OneCore and SAPI 5 on Windows. Gemini is offered only for synthesized/saved narration playback. Switching to preview switches a selected Gemini engine to the native default without clearing the saved Gemini voice preference. Settings loading/saving also normalizes invalid preview+Gemini combinations. Mac's AD Overview engine picker follows the same rule as Narration settings. Returning to saved narration playback makes Gemini selectable again; existing project audio is not regenerated or relabeled by this settings change.

Speech-engine selection is independent of the narration playback mode and controls which engine generates saved narration audio: `Apple Voices`, `Gemini Voices`, or `Azure Voices` on Mac; `Windows OneCore`, `Natural Voices`, `Windows SAPI 5`, `Azure Voices`, or `Gemini Voices` on Windows. `Azure Voices` shows its Azure Speech key and region fields only while it is selected, on both platforms. Windows `Natural Voices` lists only voices downloaded to the PC for Narrator/Magnifier, under `Downloaded to this PC`; it is a Windows-only exception. Summary read-aloud can use the Azure online voice on both platforms (`Read aloud with → Azure online voice` on Mac, `Summary read-aloud voice → Azure online voice` on Windows, each offered only while a key is saved); live preview never uses online voices. The Playback → Summary Reading commands are unchanged. These are settings choices, not menu items, so no menu hierarchy changes. `Gemini Voices` stays selectable and saved in either playback mode, and its voice picker lists only the voice names (`Aoede`, `Callirrhoe`, `Charon`, `Fenrir`, `Kore`, `Leda`, `Orus`, `Puck`, `Zephyr`) on both platforms without language/gender suffixes. Speech rate, pitch, and volume sliders are shown for `Apple Voices` and `Azure Voices` on Mac and for `Windows OneCore`, `Natural Voices`, `Windows SAPI 5` and `Azure Voices` on Windows, and are hidden under `Gemini Voices`, which does not support those controls. Preview playback speaks segment text live with on-device speech and never creates audio files. The AD Overview reflects the selected engine on both platforms: Mac's overview engine picker is live-bound to settings; Windows refreshes its overview speech-engine line whenever the settings dialog closes. Generation commands always use the engine saved in settings, and the legacy `device` playback alias still migrates to Windows' `ondevice` on load/save.

## Keeping parity

For any menu change, update both implementations, behavior/availability, shortcuts, native smoke expectations, and the checker as necessary. Run `python3 script/check_menu_parity.py` from the combined workspace or either desktop, then each desktop's `tests.test_menu_parity`. The checker compares actual hierarchy/order/separators, common labels, handler coverage, and translated editor shortcuts and rejects collisions. Mutation tests demonstrate that missing/moved actions, wrong labels, unwired commands, and conflicts fail.

Build and pre-commit scripts invoke the checker. Outside the combined workspace they explicitly skip; this does not validate parity. Windows UI smoke tests still require a Windows host.
