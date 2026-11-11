# Desktop menu contract

- **Edit > individual segment actions:** in timed-section Edit mode, Select All Segments and Deselect All Segments precede row-specific edit/play/skip/re-analysis or narration actions. These entries share guarded context-menu dispatch and require exactly one selected visible row; zero/multiple selections disable them. Delete Selected Segments… instead uses the existing bulk deletion command and accepts any nonempty selection. AD Transcript follows the selected row kind. Transcript rows omit narration actions; description rows omit transcript re-analysis. Summary/AD Overview and viewing mode omit these Edit entries. Right-click still targets its individual row in either mode. Playback > Segment Narration groups a single Play Narration / Pause Narration / Resume Narration action and a conditional Stop Narration action. They appear in Descriptions/AD Transcript Edit mode, with exactly one description row selected. Right-click offers the same stateful controls in either mode. Pausing/resuming requires that specific row to be the active preview, and starting requires usable audio. Stop is hidden without an active or paused preview and disappears on completion, matching the row controls. Right-click menus separate edit, video navigation, narration playback, creation/import and deletion; audio-only and whole-segment deletion share the final destructive group; Delete Segment Audio… is disabled without attached audio. No new shortcuts. Stable segment-one-* IDs match across desktops.

The Edit menu is application-only on both desktops. Mac replaces the native pasteboard and Undo/Redo groups and removes injected AutoFill, Dictation and Emoji entries; native text-field Cmd-X/C/V/A/Z/Shift-Z still route to the active text editor without visible native Edit items. Windows retains its application-only Edit layout and native text-control keyboard handling.

Mac is the reference layout. Windows' shared menus follow this order:

- **File:** New Project, Open Project Folder, Export. Native Windows additions: Open Editor in New Window, Settings, Close Window.
- **Edit:** Copy and Translate… followed by the active section’s Edit/Done Editing command (`segment-edit-mode`, Command-Option-E / Ctrl-Alt-E). The latter uses the same guarded toggle and dynamic title as Project > Segments and the inspector. In Descriptions it reads Edit Audio Description Segments or Done Editing Segments. The inspector retains its matching Done control while editing. Copy and Translate… (`copy-to`) opens the same source/target-language translation and duplication dialog on both platforms. No new shortcut; native text-copy shortcuts keep their normal behavior. The command is also available in the language inspector and editor background context menu. The inspector has one Copy and Translate button named for the active section, with no duplicate per-content buttons. Its dialog preselects only that section (both transcript and descriptions on AD Transcript); the generic Edit-menu action preselects all three content types. Selected Segments Only is available when rows are selected and starts off for both entry points. Both use the same guarded copy command with an explicit current-section default. Individual transcript/description row right-click and More Actions (ellipsis) menus omit Copy and Translate… on both desktops; Edit > Copy and Translate… and inspector entry points remain available. Selected rows make Selected Segments Only available; whole results can be copied individually or together. It works in viewing mode, requires saved nonempty content and an idle app, and is blocked by pending summary edits. Translate Text defaults on; Translate and Copy requires Gemini access and a specific target language. Turning Translate Text off enables local duplication into a different language category, including Auto when the source is another category. Both Translate and Copy and Copy are disabled when source and target languages match; the engine also rejects those requests before changing the project. Translations preserve timing and source results but need new narration.
- **View:** Project Language (dynamic checked saved-language choices), separator; Preview, Timeline, Show/Hide Thumbnail Images (hidden by default, remembered on device, no shortcut); Project List visibility, Inspector visibility; Project List View, Project Grid View.
- **Playback:** Segment Narration (when applicable), separator, Preview, Full-Screen Video, dynamic Play Video/Pause Video, conditional Stop Video, Rewind/Fast Forward 5 Seconds, Toggle Narration. Stop Video is hidden before playback and after stopping/completion; it remains available while paused. The video transport uses the same conditional Stop control on both desktops.
  - **Transcript Overlay:** Cycle; Off, Transcript, AD Transcript.
  - **Summary Reading:** Play/Resume, Pause, Stop; Previous/Next Sentence; Previous/Next Paragraph; Read from Start, Read from Selection, Read Selected Text.
- **Project:**
  - **Editor Sections:** Transcript, Summary, Descriptions, AD Overview, AD Transcript.
  - **Segments:** Edit Mode, Add; Re-Analyze a Video Section, Select All, Deselect All, Edit Selected, Delete Selected; Follow, Undo, Redo.
  - **Analysis:** Analyze Video; Video Details/Timeline Pictures, Transcript, Summary.
  - **Narration:**
    - **AD Segment Generation:** Generate/Regenerate Audio Descriptions; Delete Descriptions.
    - **Narration Audio:** Generate/Regenerate All AD Audio, Generate Missing or Changed AD Audio, Review Narration Issues, Review Narration Voices; Delete All Narration Audio.
  - Delete Current Page; Import Existing Assets…; Show Project in Finder/File Explorer; Open Project Configuration (project.json in the default editor). Import Existing Assets… uses the same label and stable command ID `import-assets` on both desktops, appears at the same position after Delete Current Page, and has no new shortcut. It opens the existing-asset import sheet for the active editor project.
  - After a separator: Rename Project…; Move Project to Bin… (Windows: Move Project to Recycle Bin…). These target the active editor project, use the existing rename/confirmed whole-project recycling flows, require an idle editor, and do not require an API key. Rename is unavailable for an unreadable/missing project. No new shortcuts are assigned. The Bin/Recycle Bin label difference is the intentional native-OS exception, checked explicitly by the parity validator.
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
| Previous / next summary sentence | Command+Shift+[ / ] | Ctrl+Shift+[ / ] |
| Previous / next summary paragraph | Command+Option+[ / ] | Ctrl+Alt+[ / ] |

Deselect All uses Command+Option+Shift+U / Ctrl+Alt+Shift+U to avoid colliding with Analyze Video. Ctrl+Shift+D toggles narration on Windows, matching Mac; it no longer generates all narration.

There are exactly two bulk audio commands in AD Overview, Inspector, and the menu on both desktops. `synthesize-tts` is labeled **Generate All AD Audio** before any segment has audio and **Regenerate All AD Audio…** once any segment has recorded audio. Both states always attempt every segment and save the selected primary engine/voice before generation starts, including when a later segment fails or the run is canceled. The initial run needs no replacement confirmation; subsequent runs use the same confirmation everywhere. The separate `regenerate-all-narration` entry was removed. Unqualified engine `synthesize-tts` is also a full run, so legacy callers cannot silently preserve usable audio or an obsolete primary voice.

`synthesize-changed` is labeled **Generate Missing or Changed AD Audio**. It is visible but disabled before any segment has generated audio, and enabled thereafter only if at least one segment is missing audio or has a text/timing/generation issue. It preserves valid audio and the primary voice. Single-segment generation remains in segment context menus, not as an extra Inspector bulk control. Full generation retains old files until replacements succeed; failed old files keep their truthful voice metadata. Actual generation failures are reported without an additional automatic mixed-voice dialog after a full run.

The Narration menu mirrors the Inspector's separate AD generation and narration audio groups using native nested submenus. Audio Description generation moved from Analysis into AD Segment Generation; its Command+Option+Shift+D / Ctrl+Alt+Shift+D shortcut and prerequisites are unchanged. Description deletion targets descriptions regardless of the active editor section and uses the existing confirmation. Review Narration Voices remains directly after Review Narration Issues inside Narration Audio.

Windows row/header More action buttons in Transcript, Descriptions, and AD Transcript are visible only in segment Edit mode, matching Mac's edit-only action controls. View-mode right-click/context menus and narration preview remain available. This changes the button entry point, not the underlying commands or shared menu hierarchy.

Speech-engine selection is independent of the narration playback mode. Both apps keep the saved engine when switching between saved-audio and live preview, and preview playback speaks segment text live without creating audio files in the project. Mac uses Apple Speech or a temporary Piper WAV for live preview; Windows uses the selected Windows OneCore, SAPI 5, or Piper voice. Gemini remains selectable for saved narration generation in either playback mode.

The speech engine controls which engine generates saved narration audio: `Apple Voices`, `Piper Voices`, or `Gemini Voices` on Mac; `Windows OneCore`, `Windows SAPI 5`, `Piper Voices`, or `Gemini Voices` on Windows. **Piper Voices** is a bundled offline neural engine on both desktops; its voices are downloaded from an in-app catalog and work for samples, saved narration, live preview, and summary read-aloud. Mac synthesizes in-process with the bundled Python engine, while Windows runs the bundled Piper runtime through SpeechHost. Summary read-aloud always uses the same engine and voice chosen for narration on both platforms. The Playback → Summary Reading commands are unaffected by this engine choice apart from using its selected voice. These are settings choices, not menu items, so no menu hierarchy changes. `Gemini Voices` stays selectable and saved in either playback mode, and its voice picker lists only the voice names (`Aoede`, `Callirrhoe`, `Charon`, `Fenrir`, `Kore`, `Leda`, `Orus`, `Puck`, `Zephyr`) on both platforms without language/gender suffixes. Speech rate, pitch, and volume sliders are shown for `Apple Voices` and `Piper Voices` on Mac and for `Windows OneCore`, `Windows SAPI 5`, and `Piper Voices` on Windows, and are hidden under `Gemini Voices`, which does not support those controls. The AD Overview reflects the selected engine on both platforms: Mac's overview engine picker is live-bound to settings; Windows refreshes its overview speech-engine line whenever the settings dialog closes. Generation commands always use the engine saved in settings, and the legacy `device` playback alias still migrates to Windows' `ondevice` on load/save.

The summary editor's Markdown commands are editor-local. They use the shortcut list documented in Help (Command-B, Command-I, Command-Shift-X, Command-Option-Backtick, Command-Option-Shift-C, Command-K, Command-Shift-I, Command-Option-1–6, Command-Option-0, Command-Shift-8/7/9, Command-Option-Shift-Q, Command-Option-T, Command-Option-Hyphen, Command-Option-Shift-K, Command-Option-Shift-P, Command-Option-Shift-M, and Command-Z/Command-Shift-Z), translated to Ctrl/Alt on Windows. Neither desktop adds a Format menu, and the commands do not apply outside the summary editor. While that editor is active, Project List View and Project Grid View (Command-Option-1/2 on Mac, Ctrl-Alt-1/2 on Windows) are disabled because those combinations insert Heading 1 and Heading 2.

## Keeping parity

For any menu change, update both implementations, behavior/availability, shortcuts, native smoke expectations, and the checker as necessary. Run `python3 script/check_menu_parity.py` from the combined workspace or either desktop, then each desktop's `tests.test_menu_parity`. The checker compares actual hierarchy/order/separators, common labels, handler coverage, and translated editor shortcuts and rejects collisions. Mutation tests demonstrate that missing/moved actions, wrong labels, unwired commands, and conflicts fail.

Build and pre-commit scripts invoke the checker. Outside the combined workspace they explicitly skip; this does not validate parity. Windows UI smoke tests still require a Windows host.

## Import Existing Assets

Both desktops expose **Project → Import** with **Import Transcript…**, **Import Summary…**, **Import Descriptions…**, then a separator and **Import Existing Assets…**. Stable IDs are `import-transcript`, `import-summary`, `import-descriptions`, and `import-assets`. Windows shortcuts are Ctrl+Alt+I/M/D and Ctrl+Alt+Shift+I; Mac uses Command/Option equivalents. All actions require an idle, readable project. The editor also exposes scoped Add/Import actions.

Markdown commands are local to the Summary editor. While it is active, Project List/Grid menu items and accelerators are disabled on both platforms so Command+Option+1/2 and Ctrl+Alt+1/2 apply headings. Windows accelerators consult the same command guard as the menu and leave disabled keys unhandled so the text editor can receive them. This restores the already-implemented Mac behavior; it is not an OS-specific exception.

## Contextual editor overflow actions

Windows' header three-dot menu now follows the active section: Summary offers Edit/Done Editing Summary, Generate/Regenerate Summary, and Delete Summary (only Done while editing); Transcript offers segment editing, selection, and history actions; Descriptions adds the two bulk narration commands; AD Overview offers only those narration commands; AD Transcript offers segment selection/editing/history and narration, without Add. Timed-section header menus remain edit-only. Segment-row context menus remain scoped to their individual transcript or description. Relevant commands retain their normal prerequisites and dynamic titles, and activation rechecks the current project, section, editing mode, and shared command guard.

Native layout exception: Windows consolidates these existing commands in its compact header overflow menu. Mac already places the corresponding section-scoped actions in its native toolbar, Selection menu, Summary editor, and inspector, so it does not add a duplicate header overflow. The shared desktop menu hierarchy and shortcuts are unchanged.

## Remove from List in project context menus

Both desktops expose **Remove from List** (`remove-from-list`) in the main project gallery's list/grid context menu, before the separate destructive project actions. It requires an idle app and works for healthy, damaged, local, and external project entries without an API key. It stores a per-user visibility preference outside the project, leaves project files and open editors intact, and persists across refresh and restart. **Open Project** restores that folder to the list. Mac keeps open editor models independent from the filtered browser list; Windows filters removed folders from both full and incremental gallery refreshes.

**File → Remove from List** uses the same `remove-from-list` command after selecting a project in the main list/grid. It appears after Export, is disabled with no selected project, while processing, or when the editor project browser is hidden, and rechecks the current selection when activated. Windows preserves the selected project when switching list/grid layouts. This entry point uses the same non-destructive removal behavior as the context menu.

## Project browsing inside editor windows

Both desktop editors expose their project list/grid through View → Show/Hide Project List and Project List/Grid View. Selecting a listed project switches the current editor; the project context menu separately offers Open in This Window and Open in New Window, followed by Remove from List and the native project deletion action. Remove keeps project files and an already-open editor intact; deletion retains confirmation. The editor browser footer uses icon-only Remove and Delete buttons with tooltips and accessible names. Windows list and grid share the save-summary-before-switch path. Mac disables project switching while a summary is being edited and updates the typed scene value on switching, so subsequent window routing and restoration refer to the current project. Open-project settings track multiple windows owning the same project.

The project browser inside each editor starts closed on both platforms. View → Show Project List or the sidebar control opens it; choosing Project List View or Project Grid View also reveals it in the requested layout. Layout choice can be remembered while initial visibility remains closed.

## Rename pencil and project management availability

Both editor headers show an icon-only pencil beside the project name, labeled Rename project with a Rename this project tooltip. It uses the same guarded rename dialog as Project → Rename Project. Rename, Bin/Recycle Bin, folder access, and configuration access now act on the selected main-list project or the current editor project, including when the editor project browser is closed. They do not require an API key; processing and file-availability checks remain in place.


Editor control parity: Transcript, Summary, Descriptions, and AD Transcript use one native accent-colour pencil/checkmark button to enter/finish editing, with icon-only presentation, descriptive accessibility names, and tooltips. Summary uses the same control to save text and provenance; its second Save/Done button is removed. Generation appears in the inspector while open and falls back to the section toolbar when closed. AD Overview owns its narration controls without a second inspector group. Menu/context command alternatives remain available.


Project-pane transitions: the left project browser remains closed by default. Toolbar, View menu, and list/grid commands share the same native visibility state. Mac uses NavigationSplitView with a reduced-motion-aware animated binding. Windows uses inline SplitView panes for both projects and inspector, preserving editor space and delegating open/close transitions and reduced-motion handling to WinUI. Closing the Windows project pane restores keyboard focus to its toggle when focus was inside the pane.


## Developer-only project configuration

**Open Project Configuration** (`open-configuration`) is visible only while Settings → Appearance → Developer mode is on. Both desktops hide it from the Project menu, project list/grid context menus, and inspector when off. The command guard and final file-opening action recheck the current setting, including requests from a previously opened menu. Existing idle, selection, and file-availability requirements still apply.

## YouTube audio sources (1.0.194)

Project > Import includes Import Original Audio and Import AD Audio on both desktops. Original Audio is enabled for YouTube projects; AD Audio supports local and YouTube projects. Both actions use the shared command guard, and neither adds a keyboard shortcut. Audio Sources is also available from the editor toolbar, inspector, and YouTube audio export dialog.


## Internet availability (1.0.197)

Both desktops use the same command requirements for toolbar buttons, Project/Playback menus, project and segment context menus, and keyboard actions. Gemini processing requires reachable Gemini plus the existing key/service prerequisites. YouTube details, project creation, metadata refresh and streaming playback require reachable YouTube; local media preparation stays available offline. Cloud narration is gated by the selected provider. Export availability follows the selected soundtrack and AD source: local imported soundtracks, full AD mixes, narration-only audio and text do not acquire a YouTube requirement. Connection changes restore only actions whose other prerequisites are satisfied. Final execution guards recheck availability; Mac also rechecks after modal confirmation. No command IDs, menu order or shortcuts change.

The Check Connection action is on the connection banner on both platforms. Connectivity and API-key/quota validation are separate. Windows Summary Reading can use the selected Gemini provider and therefore requires internet when creating cloud speech; Mac summary reading uses its existing local Apple/Piper path.

YouTube commands: File > My YouTube Videos…; Project > YouTube > Video Details…, Refresh Details, Import YouTube Captions…. Stable IDs: youtube-browser, youtube-details, youtube-refresh, youtube-captions. No new keyboard shortcuts.

YouTube browser commands now have a dedicated YouTube menu and selected-video editor/browser actions. Shortcuts: Cmd/Ctrl+Option/Alt+Y (videos), +Shift+Y (accounts); Cmd/Ctrl+Return (editor), +Shift+Return (YouTube); Cmd/Ctrl+R (refresh); Cmd/Ctrl+Option/Alt+L (more videos), +Shift+L (more playlists). Browser actions are guarded by the focused browser and selection.

Project > YouTube > Refresh YouTube Details (stable ID youtube-refresh) now refreshes the inspector and saved project metadata directly. The inspector button shares that action. Video Details and caption import remain separate commands.

YouTube > List View/Table View change the remembered YouTube browser layout. File > Open in YouTube and YouTube > Open in YouTube share youtube-open-browser and resolve the focused YouTube browser selection, otherwise the selected/current imported YouTube project. Project context menus and inspector use the same saved canonical URL.

File has adjacent Settings… and Open Project Settings… commands. Open Project Settings uses stable ID `project-settings`, is enabled in an active usable editor, and opens Settings directly to Projects for that project. Project context menus target the clicked project. On Mac, Settings… also remains in the application menu.


## Settings shortcuts (1.0.211)

File > Settings… shows Cmd/Ctrl+Comma. File > Open Project Settings… shows Cmd/Ctrl+Shift+Comma and uses the existing guarded project-settings command for the active editor. The shared Settings window selects that editor project in Projects. The Mac application-menu Settings entry retains the native Cmd+Comma action.

Project > Language and Saved Results… is first in the Project menu on both desktops. It has no keyboard shortcut and uses the shared command guard. It opens the same language/result controls as the inspector; Filter Segments includes those controls too. Section deletion actions open Delete Content by Language, prefilled with the active result. Auto is a content category; All Languages is a filter only.

Language and Saved Results follows the active editor tab on both desktops. View Project Language is shared and available in view mode; section generation targets and Assign Language require Edit mode. Saved versions in the current language remain selectable in view mode. Edit is available even for an empty Transcript or Descriptions section so its initial target language can be chosen. Pending summary edits must be saved or cancelled before language/result context switches.

Manual editing of existing segments requires Edit mode on both desktops: row pencils/context Edit, double-click editing, and bulk editing. Add Segment, generation/regeneration, and deletion remain available in view mode. Context menus never automatically enter Edit mode. Playback/navigation remain available in view mode.

Read Frame Text remains available for review without segment editing. Mac offers Add as Description and Windows can open a new description draft in view mode; manually editing existing descriptions still requires Edit mode.

Every tab, including AD Overview, uses the single View Project Language picker. Saved-result selectors use that language. Viewing actions preserve section targets; language assignment and target changes retain their Edit-mode guards. There is no separate overview viewing-language override.


## Project Language submenu

View > Project Language uses stable parent ID `project-language` and option IDs `project-language-<code>` on both desktops. Choices and titles match the inspector: supported categories with saved nonempty content only; Auto stays distinct. Exactly the current available viewing language is checked. Selecting an option dispatches the guarded `select-language` action without Edit mode; busy operation, missing editor/project, unsupported/unavailable categories and pending summary edits block selection. Re-selecting the current language keeps it selected and performs no project write. No shortcut is added. Speech inspector metadata uses Engine, project viewing Language, Voice on Summary, Descriptions, AD Overview and AD Transcript.


## File menu deletion commands

After Export and its separator, both platforms show Delete Project… (`delete-project`), Choose What to Delete… (`delete-content`), then a separator and Remove from List. Both new commands target the active project editor, are disabled outside an editor or during processing/pending summary edits, and have no shortcut. Delete Project uses the existing confirmed Bin/Recycle Bin flow; Choose What to Delete opens Delete Content by Language. Existing Project-menu recycling and browser context actions retain their OS-specific labels. Confirmed deletion shows an indeterminate spinner/status across gallery/editor windows until completion or failure. Successful whole-project deletion closes every editor for that project, keeps or opens All Projects, and never switches the window to another project. Cancellation/failure leaves editors open; section deletion keeps them open. Deletion does not expose Cancel Processing or an estimated percentage.

View > Saved Results mirrors current-language inspector versions grouped by content kind. Stable IDs: `saved-results`, `saved-result-<resultID>`. Selection is guarded while busy or with unsaved summary edits; no new shortcut.

The View saved-results menu is flat: its dynamic title is Transcript Saved Results, Summary Saved Results, Description Saved Results, or AD Transcript Saved Results. Versions are direct checked options without kind submenus. Inspector result labels use the same kind-specific wording; mixed-kind menu entries include the kind in their name. Stable command IDs and language/tab guards are unchanged.

Saved-result View options expose Selected, All AD segments have audio, and Export ready through native menu accessibility labels and status icons. macOS propagates saved-result image/tooltip metadata to NSMenuItem accessibility labels; Windows names the icon and menu item through UI Automation.

View saved-result menus and inspector/settings pickers include all stored versions for the current tab and viewing language, including review drafts and incomplete results. Draft entries include “Review draft” in visible and accessible names. Explicitly selecting a draft keeps and selects it as a saved alternative (Keep Both), preserving earlier results and generation targets. Viewing languages include categories containing only drafts or empty results. Export readiness does not gate these selectors; busy and unsaved-summary guards still apply.

## Summary zoom

View contains Zoom In (`summary-zoom-in`), Zoom Out (`summary-zoom-out`) and Actual Size (100%) (`summary-zoom-reset`) while Summary is active. They use the shared guard in reader mode with nonempty content and an idle editor, including during reading; editing/processing disables them. Shortcuts are Command/Ctrl + Equals, Minus, and 0. Shifted Plus is accepted too, and Windows accepts Ctrl+keypad Add/Subtract. The native OEM Equals/Minus keys map to 187/189. Range is 50–400%, with 10 percentage point button steps. The playback row always has minus/100%/plus; the footer slider and percentage appear only with Preview hidden. Native pinch zoom reflows text without changing speech or selection. This layout does not require OS full screen. Zoom is per open editor, default 100%, and does not alter project data or exports.


## All Projects window menus

View uses the All Projects source/language filters, reset filters, and checked list/grid layout. Project offers Open Selected Project, Analysis (including description generation), folder/configuration, rename and trash. File Export, deletion, Remove from List and Project Settings target the visible selection. Filtering a selection out disables those actions. Editor-only controls are hidden in this window, including preview/timeline/inspector, saved results, sections, segments, import, narration and playback. Native macOS Edit/Window commands remain system-owned; Windows hides its application-only Edit/Playback menus in All Projects. The macOS grid icon-size slider remains a native Mac presentation control.

### Piper Settings voice sample

In Settings > Narration, the Piper sample button offers Play Sample and Stop Sample in its context menu (right-click; Windows also supports Shift-F10). Both use the same guarded actions as the button and stable IDs `piper-settings-play-sample` / `piper-settings-stop-sample`. Play requires Piper and a selected downloaded voice; Stop is enabled while preparing or playing audio. The button remains visible but disabled without that voice. Mac applies rate, pitch and volume to the local sample; Windows applies rate and volume, retaining its existing saved-narration pitch behavior.

## Export dialog control menus

One File with Selected Tracks and the remaining combined-track toggles/pickers provide native context menus using the same state and enabled choices. Transcript and AD Transcript are independent per-language controls; closed captions allow both, while open captions permit one track. Native secondary click or keyboard context-menu invocation opens these menus. Standalone text options are confined to the dedicated Text category and remain independent of media packaging. The File > Export entry point and shortcut are unchanged.

Combined Audio Description is fixed to selectable tracks. The former audio-presentation dropdown and its menu are removed on both desktops; Include Original Audio and per-language AD Audio keep their shared state/control menus. Caption presentation remains selectable.

Created Exports language picker/context menu lists All Languages plus only languages in tracked outputs; each entry shares the same selection and filter behavior. Combined files match each included language, are grouped once under Multilingual, and retain existing file actions and icons. Main menu hierarchy is unchanged.


## Timing validation navigation and sound
The segment dialog footer action (Show Description / Show Transcript / Show Validation Issues) has a matching context-menu action, stable IDs `show-validation-issue` and `show-validation-issue-menu`, and Command-Option-V / Ctrl-Alt-V keyboard access, scoped to a timing error in the active dialog. Bounds/order errors reveal the local error; overlaps briefly showcase affected rows in their corresponding sections and return to the unchanged draft. Settings > Narration includes the default-on Sound when timing validation fails toggle and a matching checked context-menu toggle (`timing-validation-sound-menu`) on both platforms.


## Segment filter modes and Sort Options
View > Filter Transcript / Filter Descriptions / Filter AD Transcript exposes All segments, Select segment numbers, Segment number ranges and Time ranges. Filter mode, segment checkbox, range add/remove and time-match actions have matching dialog-local context menus and checked state. Range bounds are separate controls and Apply is guarded by validation. System accent indicates checked rows. View > Sort Segments adds Sort Options… (`sort-segments`) before direct sort commands; its modal exposes saved results and sort choices only. Filter/Sort modals use the already viewed language and omit copy, language, generation-language, synchronization and editing controls. Existing View > Saved Results menu selectors operate on the same result state.

Clear Filter (`clear-segment-filter`) is conditional directly below Filter in View; Clear Sort (`clear-segment-sort`) is conditional at the top of Sort. Matching icon-only section-toolbar buttons sit next to Generate/Add. UI/menu share guarded dispatch and hide independently when inactive; each reset retains the other setting. Filters and sort orders are scoped to the current tab/language/result.

## Active tab and project source

Both desktops hide unrelated commands and reject them through the shared menu/shortcut dispatch. Transcript: transcription/import/delete; Summary: summary generation/import/delete, Summary Reading/Zoom, Edit Summary; Descriptions: AD generation/import/delete and narration; AD Overview: narration tools; AD Transcript: combined-segment and narration tools. Segments is limited to timed tabs, with Add/Re-Analyze/Undo/Redo only on Transcript and Descriptions. AD Transcript overlay and narration playback choices appear only on AD timed tabs. All Editor Sections navigation remains available. Shared project management, source preparation, export and generic existing-asset import remain project-wide. Full-project Analyze Video is scoped to the gallery.

Local-video editors hide YouTube from Project, File and the top-level bar. YouTube project details and refresh remain source-scoped; caption import additionally requires Transcript. Original-audio import requires a YouTube project. The library is still reachable from All Projects, and library-only layout/list commands require the library window. Relevant actions stay visible while disabled by prerequisites, busy state or selection; hidden actions cannot run through accelerators. Windows normalizes separators after filtering; Mac conditionally declares the same groups and actions.

Edit/View filtering uses the same visibility predicate as command dispatch. Bulk selection and selected-row edit/delete require timed-section Edit mode. Re-analysis and Undo/Redo require Edit mode on Transcript/Descriptions. Add remains available in both modes as in the toolbar. Summary reading/zoom, generation/import/delete require viewing mode; Edit/Done remains accessible in both. Windows editor background action menus also filter through this predicate to avoid exposing hidden commands as disabled entries.

All Projects Edit contains only Rename Project… on both desktops, using the visible selected project's existing rename guard and confirmation path. Open in New Window (`open-gallery-window`) is in File. Other file operations stay in File; analysis, folder access and Developer-mode configuration stay in Project. Right-click retains the full project context menu. Editor Edit entries are unchanged. Mac’s app-owned menus restore icons idempotently; system entries remain excluded and unchanged images are retained during menu tracking.

Project language filters (All Projects toolbar, View > Filter Projects by Language and the editor project-list dropdown) share the library’s unfiltered saved-content language set on both desktops. Include All Languages, plus only distinct languages with saved nonempty transcript/summary/description/imported-AD content. Empty results, drafts and configured-only languages do not add options. Auto requires actual saved Auto content; unknown legacy labels remain accessible when they have content. Clearing/removing the final matching content resets stale selections to All Languages. Reset Project Filters still clears search/source/language. Creation, import and edit-language pickers keep the supported catalog. Native action icons cover static and dynamic menu actions and nested groups; Mac preserves existing images and applies explicit visibility only when needed, while Windows uses the matching Fluent action icons.

YouTube > YouTube Accounts… uses the shared Settings window outside the YouTube browser on both desktops. It selects YouTube Accounts and reuses an existing Settings window. Sidebar order is Appearance, Projects, Narration, Gemini API, YouTube Accounts, optional Developer prompts, Storage, Help, About; stable Windows page IDs remain independent of visual order.

## All Projects sorting and website

View > Sort Projects appears only in All Projects, after the language filter, with checked Last Opened (default), Name (A–Z), Duration (Longest First), and Type (Local, then YouTube) choices. Stable IDs projects-sort-opened/name/duration/type share guarded dispatch; sorting requires no selection or API key and remains available during processing. Choices affect list/grid presentation, preserve selection and filters, and last for the window. Reset Project Filters preserves sort. Local opening history persists outside projects, falling back to updatedAt for older projects. Help > VidiStudio Website (website) opens https://vidistudio.varunmanojkumar.in/ in the default browser on both desktops, including during processing; no shortcut. VidiStudio Help stays offline. Windows retains About after the website item; Mac retains native About placement.

YouTube Accounts uses Disconnect Google Account followed by a Cancel-default Disconnect confirmation on both desktops. Windows has no separate disconnect checkbox; Settings and My YouTube Videos share the same account panel and confirmation. The existing Disconnect action is retained; no additional shortcut.

## Matching context menus (1.0.287)

Mac is the reference for All Projects list/grid, the editor project browser, timed rows, Summary reading/text, editor background and YouTube rows. Windows gallery now mirrors the opening separator, Rename/source/settings/folder/configuration order, nested Analysis with its separators and dynamic labels, Export…, Remove from List, and the two final deletion commands. Editor browser uses only its seven applicable entries (including the source-specific YouTube item), with existing open-project-here/open-editor-window/trash-project IDs. Gallery uses open-gallery-window/delete-project. Export has no AI-key gate; description generation retains saved transcript/summary requirements. Captured targets, mode, busy, connection and developer prerequisites are checked at execution. Blank project/segment space never falls back to a previous pointer selection.

Windows adds the Mac YouTube row and Summary Play/text menus; AD Overview background omits Copy and Translate instead of disabling it. Row/menu actions retain shared guarded handlers. Native text commands, OS chrome, menu rendering and Bin/Recycle Bin destinations are genuine platform differences. Right-click and native keyboard context invocation are supported. The focused Windows ContextMenusOnly smoke checks order, nesting, separators, dynamic labels, source/developer scopes, offline export and stale context rejection using temporary fixtures.

Deletion icons: Windows command IDs and display labels resolve through the shared icon factory. Project/section/segment deletion uses Fluent Delete (E74D), content selection for deletion uses EraseTool (E75C), and narration-only audio removal uses E74F, matching Mac trash/eraser/audio-removal semantics. Native smoke assertions compare actual glyph values, including both gallery deletion items; a non-null fallback icon does not pass.
