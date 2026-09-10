# Build and validation — 8 September 2026

## Icon Composer appearances — 8 September 2026

Created `VidiStudio/StudioIcon.icon` in Apple's bundled Icon Composer with the original transparent 1024-pixel artwork as a foreground layer. Default appearance uses System Light and the dark specialization uses System Dark. Both previews were visually inspected in Icon Composer. Debug and Release target settings now select StudioIcon; the Release asset compiler processed the .icon document and emitted StudioIcon.icns plus the asset catalog. Release packaging, strict signature verification, and DMG checksum verification passed. Icon appearance follows macOS icon appearance preferences; the app's own theme selector does not override the Dock icon.

Implemented the native macOS 26 SwiftUI app in the existing plain-app Xcode project. The live logged-in website was reviewed read-only for the project list, video preview, timed description editor, narration status and export workflow. The website repository was not modified.

## Delivered

- Native project sidebar, video preview with Apple's AVKit controls, thumbnail and cue timeline, transcript/summary panels, description editing, processing inspector, Settings, keyboard menu shortcuts, and accessible control labels.
- System Liquid Glass sidebar/toolbars/buttons, SF Symbols, system typography, and macOS icon assets generated from the website's original 1024px PNG.
- Local project folders, atomic JSON writes, project-confined paths, OS write locks, pre-operation history snapshots and remembered project selection.
- Portable Python CLI for import, metadata, thumbnails, extraction, Gemini Files API transcription/summary/descriptions, macOS/Windows system narration, optional Gemini TTS, cue saving and final FFmpeg exports.
- Self-contained Python 3.14.6 engine with google-genai 2.22.0; bundled FFmpeg/FFprobe 9.0.1 plus 19 dependency libraries. No external non-system Mach-O dependencies found across 106 binaries in the inspected bundle.
- No Firebase, Firestore, authentication or cloud-storage runtime dependency.
- Xcode engine-bundling build phase, Codex Run action, build/run script, Windows engine packaging script, and Release ZIP/DMG packaging.

## Validation evidence

- `script/build_and_run.sh --verify`: Debug build and launch passed.
- `VIDISTUDIO_CONFIGURATION=Release script/build_and_run.sh --verify`: Release build and launch passed.
- `script/package.sh`: Release app, ZIP and DMG produced.
- Source engine tests: 4 passed. Packaged Debug engine tests: 4 passed. Packaged Release engine tests: 4 passed. Logs in `build/test-results.log`, `build/packaged-engine-tests.log`, `build/release-engine-tests.log`.
- Engine integration test creates a real video, copies it into a project, generates eight thumbnails, extracts audio, saves a cue, synthesizes actual macOS speech, and renders and probes an MP4. It verifies stale narration and missing API-key failures. Additional tests check timing/dialogue overlap and path traversal.
- Native UI: imported generated VidiStudio Demo video; created a timed cue; saved through the engine; generated macOS narration; exported an MP4; reopened saved project in Release. Settings and playback controls appear in the accessibility tree.
- `codesign --verify --deep --strict`: passed for final Release bundle.
- `hdiutil verify dist/VidiStudio-macOS-arm64.dmg`: passed; log in `build/dmg-verification.log`.
- Release-only SwiftUI VideoPlayer overlay crash was diagnosed from the crash report and fixed with a narrow native AVPlayerView representable. Native player view has no intrinsic video-pixel width and oversized restored windows are constrained to the screen.

## Artifacts

- `build/DerivedData/Build/Products/Release/VidiStudio.app`
- `dist/VidiStudio-macOS-arm64.dmg`
- `dist/VidiStudio-macOS-arm64.zip`

The app and installers contain the Python engine and media binaries. They target Apple Silicon and macOS 26+. Signatures are ad hoc for local use. Public distribution notarization was not performed.

## Remaining validation limits

- Gemini analysis and premium TTS are implemented against the official SDK but were not live-tested: no Gemini key was entered into desktop Settings during this task. The app requires a user-supplied key/model configuration for those actions.
- Windows paths and System.Speech implementation are present; no Windows runtime test or Windows executable build was performed on this Mac.
- Accessibility labels and native keyboard controls were inspected, but a complete manual VoiceOver audit was not performed.
- This is the initial local workflow requested, not full feature parity with the web app: YouTube ingestion, paused-frame Gemini OCR, AI cue rewrite/auto-fit, undo UI, subtitle export, and synchronized AD preview are not included. Existing local cue text and timing can be edited and narration can be previewed individually; final mixed videos can be played after export.

## 8 September 2026: online parity expansion

Added local YouTube projects/player, per-stage Gemini model and prompt configuration, API version selection, light/dark/system appearance, Material Symbols font, transcript auto-follow, synchronized narration, frame OCR review, rewrite, cue undo/redo, subtitle/text/JSON exports, narration-only export, changed-cue synthesis, native project search/rename/Trash, and cancellation. YouTube final muxing accepts an attached matching local video.

Validation: six source and six packaged-release engine tests passed, covering real FFmpeg media operations and macOS speech; Xcode Release build and DMG/ZIP packaging passed; packaged signature verification passed. Native accessibility inspection confirmed settings fields, requested model IDs, and editor commands. YouTube playback rendered the reference video in the native application. The accompanying FEATURE_PARITY.md records the implementation map and verification limits.

Live Gemini calls from the desktop remain unverified because its personal key is not configured. Windows runtime behavior and notarization remain unverified. The web backend fixes were deployed separately to ai-video-accessibility; Cloudflare frontend publication is being completed with the user-approved connection.

### Keyboard access — 2026-09-08

Added native Playback/Project Editor menu commands using focused scene actions, Help window, and full shortcut reference in Settings. Editor actions are disabled during processing and editing sheets. Debug build passed and Command+2 was verified through the native accessibility tree. Help uses Command+Option+/ to avoid the macOS Help-search binding. Release package rebuilt for local installation.

Final packaged-app accessibility verification: Command+Option+/ opens Help; each shortcut exposes its action and key combination; Escape closes Help; Command+Comma opens Settings with the shortcut reference.

### AD views and native narration settings — 2026-09-08

Added AD Transcript and AD Overview with counts and audio-generation actions; Command+4/5 and Help reference updated. Replaced the single settings form with a native sidebar and detail layout. Voice selection now uses the same macOS speech inventory as engine synthesis, preserves enhanced voice names, filters language/region, searches, previews, and refreshes. Added on-device live narration without saved audio alongside generated-audio playback.

Debug build passed. Native accessibility inspection verified Settings categories, voice names and language labels, AD Overview and generation actions. Actual Allison (Enhanced) synthesis produced a valid 2.308-second AIFF. Gemini premium calls remain untested without a personal key. Deployment/public distribution remains deferred.

Final verification: six packaged engine regression tests passed (real media, system speech, export, subtitles/history, URL/path guardrails). Release build, DMG/ZIP creation, strict deep signature check passed. Final accessibility tree exposes overview metric names with their values.

### Engine-specific Settings voice previews — 2026-09-08

Added Gemini sample generation through project-independent Python `preview-tts`, sharing the same synthesis routine as AD generation. Native preview handles loading, stop/cancel, empty/error responses, session caching, and temporary credential cleanup. Settings switches between offline and Gemini sample controls; offline now also previews the selected/default voice. Gemini list mirrors the nine online voice choices and allows a custom ID. Three preview contract tests passed for model/voice routing, WAV output without a project, validation, and no-audio failure cleanup. CLAR was explicitly withdrawn by the user.

Final validation: Release build, installer packaging and strict signature verification passed. Nine tests passed, including packaged media/system-speech integration and three mocked Gemini preview contract tests. Native UI verified offline Play/Stop controls, conditional Gemini controls, and an accessible missing-key message. No live Gemini preview was generated because desktop Settings has no API key; original offline-engine selection was restored after UI testing.

### YouTube names and panel alignment — 2026-09-08

Desktop import uses the oEmbed display title and a generic offline placeholder without the URL ID; explicit CLI names are retained. Player metadata repairs old placeholder names and preserves custom names. Verified the existing project now displays I wish I knew this in my 20s and 30s. Three title regression tests pass. Settings uses a compact native window toolbar verified visually with sidebar control aligned beside window buttons; Save Settings lives in the toolbar, Check Engine in Storage. Editor uses balanced bounded sidebar sizing, sidebar-local search, compact controls and explicit action placements. Window fitting reapplies after content updates without changing fullscreen windows.

### Collapsible and full-screen preview — 2026-09-08

Added Show/Hide Preview and Full-Screen Video controls, Playback menu commands and shortcut documentation. Hidden preview remains loaded and is excluded from accessibility navigation. Fullscreen uses an isolated native container and prevents editor layout from resizing its video surface; Escape restores the original parent and frame. Native YouTube UI verified: collapse expands editor, full-screen fills the display, and Escape restores the embedded player. Local AVKit uses the same presentation mechanism.

### Fixed side panels — 2026-09-08

Replaced the resizable NavigationSplitView/inspector with fixed-width project and inspector panels around a geometry-constrained editor. Removed horizontal panel splitters and added independent show/hide toolbar controls. Long project names wrap in explicit multiline rows. Added Open in Project Folder and Delete context actions; deletion uses existing macOS Trash implementation and is disabled during processing. Reduced minimum window size and allowed central tools to scroll on narrow layouts without pushing panels outside the window. Native screenshots confirmed full side panels and the full project name; accessibility inspection confirmed no side resize handles and both show/hide transitions.

### Segment timing and project location — 2026-09-08

Renamed user-facing cue actions to segments throughout the Description editor and keyboard reference. The manual Add Segment editor now provides separately labeled hours, minutes, seconds, and milliseconds controls for both start and end times, displays the resulting timecodes, and validates the segment against the video duration before Save Segment is enabled.

Changed the new-project default to `~/Documents/VidiStudio Projects`. Settings → Storage now presents the current default folder with a native Browse button. Existing saved settings that still contain the former built-in Movies default are moved to the Documents default; the project list does not scan the old Movies location.

Validation: `git diff --check` and the Debug Xcode build passed. Native accessibility inspection confirmed Add Segment, all eight Start/End time component labels, the audio-description text editor, and Save Segment. Settings was visually verified with the Documents path and Browse control. The final Release package completed; four source and four packaged-Release engine tests passed, strict deep code-signature verification passed, and the DMG checksum verified successfully.

### Unified New Project chooser — 2026-09-08

Replaced separate desktop creation actions with a native New Project sheet available from the empty state, toolbar, File menu, and Command-N. The sheet clearly selects either Video File or YouTube Video. Video File requires a chosen local movie; YouTube Video presents a labeled URL field. Create Project remains disabled until the selected source has the required input, and both paths continue through the existing local engine and configured project folder.

Validation: the Debug Xcode build passed. Native accessibility inspection confirmed the New Project heading, both radio choices, source-specific file and URL controls, and disabled/enabled Create Project validation. Command-N reopened the same chooser.

### Gemini model menus — 2026-09-08

Simplified Settings → Gemini API by removing the editable API version and video-processing implementation choices. The required Gemini API version remains an internal engine setting. Replaced every free-form model ID field with a labeled native menu for speech transcription, YouTube transcription, summaries, audio descriptions, on-screen text, rewrites, and Gemini narration.

Added the project-independent `list-models` engine command. It calls Gemini's authenticated models endpoint, keeps Gemini models that support content generation, and returns display names plus stable API IDs to SwiftUI. The app filters transcription and TTS choices by purpose, preserves valid saved selections, and replaces unavailable selections with an available compatible model. Catalog requests use a unique owner-only temporary configuration file that is deleted when the request finishes.

Validation: all 13 source engine tests passed, including the model-catalog contract and real macOS speech/media pipeline; the Debug and Release Xcode builds passed. Native accessibility inspection confirmed the concise copy, API key field, catalog-loading control, and seven disabled native model menus before credentials are provided. The Release ZIP and DMG were rebuilt, strict deep code-signature verification passed, and the DMG checksum verified successfully. Live catalog retrieval remains pending a user-provided Gemini API key.

### Simplified project sidebar footer — 2026-09-08

Removed the permanent On this Mac and local-workspace status copy, leaving only the accessible Settings gear in the project sidebar footer. Processing messages, progress, and Cancel remain available only while an operation is running. Debug and Release builds passed; native accessibility inspection confirmed the two idle labels are absent and Settings remains exposed. The signed ZIP and verified DMG were rebuilt.

### Empty-project inspector behavior — 2026-09-08

The Project Inspector and its toolbar control are now hidden whenever no project is selected, allowing the welcome view to use the full available editor width. Selecting a project restores the inspector according to the user's previous open or closed preference. Debug and Release builds passed; native accessibility inspection confirmed that neither the inspector content nor its toolbar button exists in the empty-project state. The signed ZIP and verified DMG were rebuilt.

### Engine health indicator — 2026-09-08

Check Engine now tests the paths currently displayed in Storage through an owner-only temporary configuration, so unsaved FFmpeg and FFprobe overrides can be verified. The button shows progress while checking, a green checkmark and Engine ready on success, or a red attention state with the exact configuration error on failure. Changing either override clears the previous result. Debug and Release builds passed; the native success state and VoiceOver description were verified, and the signed ZIP and verified DMG were rebuilt.

### App version and About menu — 2026-09-08

Added bundle-backed version information to Settings → Help and the separate VidiStudio Help window. Replaced the application-info command with an explicit About VidiStudio menu item that opens the native macOS About panel, including the app icon, marketing version, and build number from the Xcode bundle. Debug and Release builds passed; native accessibility inspection confirmed App version, Version 1.0 (1) and the About VidiStudio application-menu command. The signed ZIP and verified DMG were rebuilt.

### Removed automatic window tabs — 2026-09-08

Changed the main editor scene to a single Window and disabled AppKit automatic tabbing, including the main window's tabbing mode. Projects continue to open through the list/grid browser. Native UI inspection confirmed that Show Tab Bar and Show All Tabs are absent from View and that the main toolbar retains New Project without a tab bar. Debug build passed; Release packaging refreshed.

### Project browser layouts and panel shortcuts — 2026-09-08

Added View-menu commands for Command-B (project sidebar), Command-Shift-B (inspector), Command-Option-1 (list), and Command-Option-2 (grid). Commands use the focused main window and inspector controls require a selected project. The toolbar offers a persistent list/grid choice. The adaptive thumbnail grid opens projects and retains Rename, Open in Project Folder, and Delete actions. It uses saved local thumbnails, YouTube preview images, and a movie placeholder when no thumbnail exists. Help documents all four shortcuts.

Debug and Release builds passed. Native UI verified sidebar toggling, both layout shortcuts, the empty grid state, toolbar selection, and View-menu commands. No populated project was available during the UI check, so thumbnail rendering and the selected-project inspector shortcut were not exercised live in this pass. Release installers were rebuilt.

### FFmpeg and FFprobe path choosers — 2026-09-08

Settings → Storage now provides aligned native path fields and Choose buttons for the FFmpeg and FFprobe executables. Each picker starts in the saved executable's folder, or Homebrew's binary folder when available, and rejects non-executable files. Empty overrides continue to use the media tools bundled with VidiStudio. Debug and Release builds passed, the Storage layout was inspected visually, and the signed ZIP and verified DMG were rebuilt.

### Google AI Studio API-key link — 2026-09-08

Settings → Gemini API now includes an accessible Open API Keys in Google AI Studio button beneath the key field. It opens the general `https://aistudio.google.com/api-keys` page so each user can create or manage keys for their own Google project; no VidiStudio or developer project is preselected. Debug and Release builds passed, native accessibility inspection confirmed the button and browser-destination hint, and the signed ZIP and verified DMG were rebuilt.

### Offline narration voice controls — 2026-09-08

Settings → Narration now shows native Speech rate, Pitch, and Speech volume sliders plus Restore Defaults whenever Apple on-device voices are selected. The controls disappear when Gemini TTS is selected. Apple voice samples and synchronized on-device narration use AVSpeechSynthesizer with the selected controls. Saved offline narration uses the chosen rate during system synthesis and applies pitch and volume through the bundled FFmpeg, with matching support in the Windows System.Speech path. Narration now records its engine, voice, model, and voice-control signature so changing any of them marks previous audio for regeneration.

Validation: all 13 source and all 13 packaged Release engine tests passed, including real macOS speech synthesized with non-default rate, pitch, and volume. Debug and Release Xcode builds passed. Native accessibility inspection confirmed all three named sliders at 100 percent, Restore Defaults and its help text, voice browsing and samples, and verified that the controls are absent under Gemini TTS. The Release app passed strict deep signature verification; the ZIP and DMG were rebuilt. DMG SHA-256: `bc4daf9189582f1282b1423f60f7a542a2e59455a2a6ac10cdd66905527cf032`.

### Voice search field — 2026-09-08

Redesigned Settings → Narration voice search as a compact native search bar with a magnifying-glass icon, an explanatory Search by voice or language placeholder, Escape-to-clear behavior, and a clear button that appears only while a query is present. VoiceOver announces the field as Search voices, describes what it filters, and exposes the clear action separately. Debug and Release builds passed; native visual and accessibility inspection verified live filtering and clearing. The signed Release app, ZIP, and DMG were rebuilt. DMG SHA-256: `c85f586503fbe0823600808553f3d4f36daa39074ca5d9c9236b40ec21e40727`.

### Clearer narration playback choices — 2026-09-08

Renamed the Narration during playback choices to Play synthesized narration and Preview segment text with Apple Speech. Updated the supporting description to explain that synthesized narration uses saved audio for timing and exports, while Apple Speech provides an immediate preview without creating audio files. Debug and Release builds passed; native accessibility inspection confirmed both renamed menu choices and the updated explanation. The Release ZIP and DMG were rebuilt.

### Simplified Gemini voice settings — 2026-09-08

Removed the visible Custom Gemini voice ID field from Settings → Narration. The saved voice identifier and engine support remain intact, including compatibility with previously stored custom identifiers; users now choose from the supported Gemini voice menu. Debug and Release builds passed. Native accessibility inspection confirmed Gemini voice, Sample text, and preview controls remain while Custom Gemini voice ID is absent. The signed Release ZIP and DMG were rebuilt.

### Large processing indicator — 2026-09-08

Processing now replaces the lower editor content with a large, continuously spinning native activity indicator so it remains visible beside the inspector and within the transcript area. Removed the small footer spinner and determinate progress bar. VoiceOver exposes the large indicator as Processing and reads the current operation as its value. The status and cancellation controls were later moved from the footer into the dedicated center-pane bar documented below. The Debug Xcode build passed.

### Add Segment timing alignment and pause capture — 2026-09-08

Redesigned the Add Segment timing section as one vertical column, with Start time followed by End time. Hours, Minutes, Seconds, and Milliseconds now appear once above consistently sized, aligned fields; the repeated labels, timecode summaries, and section footers below the controls were removed. A larger right-aligned duration readout sits between Start and End and updates in seconds with millisecond precision. The existing field-specific VoiceOver labels remain intact, and the duration has its own accessible label.

Opening Add Segment now pauses native or YouTube playback, stops synchronized narration, captures the paused playhead as the default start, and sets the default end three seconds later (bounded by the video duration). Both the visible button and Command-Shift-N shortcut use the same path.

Validation: `git diff --check` and `script/build_and_run.sh --verify` passed. In the running Debug app, native playback was started before Add Segment; the sheet opened at 00:00:06.398–00:00:09.398. After cancelling, waiting, and reopening the sheet, it remained at the same values, confirming playback had paused. Visual inspection confirmed the vertical layout and single row of unit headings; the accessibility tree exposed all eight time component fields with distinct Start/End labels.

### Transcript playback and combined AD transcript — 2026-09-08

Transcript and AD Transcript rows now have Material Symbols play buttons labeled with their segment type, precise start/end times, and text. Playback seeks to the selected start and plays the video; native playback waits for the precise seek to finish. Choosing an audio description also enables synchronized narration using the existing narration settings. Playback continues beyond the selected segment.

AD Transcript combines dialogue and descriptions in chronological order using type-prefixed row identities. Blue Transcript labels with dialogue icons and purple Audio description labels with speaker icons distinguish the sources independently of color. Follow tracking uses the combined row identities.

Validation: the Debug build and launch verification passed; the running transcript displayed play icons and the accessibility snapshot contained the dynamic segment labels. Full interactive playback and populated mixed AD rows were not verified in this pass; the inspected project had no descriptions. No live YouTube or Gemini calls were made.

### Confirm replacement before analysis — 2026-09-08

Superseded by the scoped regeneration behavior below: individual stages now preserve unrelated content and export listings.

The shared analysis command handler now checks the saved project before Run All Analysis, transcription, summary generation, or AD generation. Existing transcription, summary, AD segments, or SRT/VTT exports trigger a native warning identifying the content and the command's replacement effects. Subtitle files remain on disk but the warning explains that export listings reset and old subtitles may no longer match. Cancel is the default; only Continue Analysis starts the engine. Empty projects bypass confirmation. A failure to read the current project prevents processing and reports the error.

Validation: `script/build_and_run.sh --verify` and `git diff --check` passed. Native UI verification on the existing transcribed project confirmed the warning, content identification, Continue Analysis and default Cancel controls. Cancelling returned to the editor without starting analysis. No paid analysis was run; empty-project bypass and confirmed execution were checked in source.

### Scoped regeneration and Regenerate All — 2026-09-08

Individual transcription, summary, and AD generation replace only their own content. Other project content and exported files/listings remain intact. Confirmation checks only the selected stage's existing content. Run All Analysis replaces the three analysis outputs while retaining other generated files. Regenerate All is a separate inspector action with explicit destructive confirmation: it clears generated folders and edit history, retains the source/project, regenerates local metadata/thumbnails when available, and runs transcription, summary, and AD generation from the beginning. Narration and exports are generated separately, as stated in the inspector and warning. Failure after clearing does not restore old data.

Validation: focused mocked analysis tests passed for all three individual stages, checking unrelated project fields, narration files, and subtitles. The Regenerate All ordering/reset test and source-preserving clear test passed. The bundled engine rebuilt and `script/build_and_run.sh --verify` passed; `git diff --check` passed. Native UI exposed Regenerate All and its explanation, and the transcription-only warning was inspected and cancelled. No live Gemini generation or destructive regeneration of user data was run.

### Grouped menus and regeneration shortcuts — 2026-09-08

Consolidated Playback and Project Editor into a Project menu containing Playback, Editor Sections, Segments, and Analysis & Regeneration submenus. Added Command-Option-Shift shortcuts: A for all analysis, T for transcript, S for summary, D for AD segments, and R for Regenerate All. These use the existing focused editor routing and confirmation handler, and are unavailable during processing or editing sheets. Existing shortcuts remain assigned; Help/Settings shortcut reference includes the new actions.

Removed SwiftUI's default textEditing and textFormatting command groups and disabled Writing Tools behavior/affordances in the main editor. Undo/Redo and clipboard command groups remain. Build and launch verification and `git diff --check` passed. Live menu verification was blocked by repeated computer-use/AppleEvent timeouts, including after relaunch; rendered menu contents and shortcut activation remain unverified.

### Formatted summary — 2026-09-08

Summary now uses Foundation Markdown parsing and native SwiftUI block rendering for headings, bullets, numbered lists, inline emphasis, links, and paragraph spacing. Headings expose the VoiceOver header trait and text remains selectable. Stored Markdown remains unchanged. `script/build_and_run.sh --verify` passed and launched the updated Debug app; visual and VoiceOver interaction were not separately verified in this pass.

### Project processing and reset menu — 2026-09-08

List and grid context menus now offer Process Video for fresh projects or Reprocess Video for projects with analysis attempts or results. Both run the sequential analysis pipeline. Delete Generated Content requires a native confirmation and clears metadata, thumbnails, transcripts, summaries, descriptions, narration, exports, and undo/redo history while preserving project identity and source media. Delete Project is a separate action. Reset rejects generated folders that are symlinks or contain the source. The focused preservation test and packaged engine reset smoke test passed; the bundled Debug app built and launched through the verify script.

### Settings and menu iconography — 2026-09-08

Added native symbol labels to settings navigation and appearance/narration choices, app-owned File/View/Playback/Project Editor/Help commands, list and grid context actions, segment actions, and export menus. Rename, clear generated content, and delete project now have distinct symbols. Existing text, shortcuts, enabled states, and destructive roles remain intact. The Debug build and launch verification passed; menu visuals were not independently inspected in this pass.

### Read Frame Text in Add Segment — 2026-09-08

Added Read Frame Text directly above the Add Segment description editor. It captures the frame at the segment start time and places recognized screen text into the description automatically; an empty recognition result keeps the existing description and reports that no readable text was found. The existing editor-toolbar Read Frame Text review flow remains unchanged. The Add Segment toolbar action now stays at the far right of the same editor-controls line instead of moving with the horizontally scrolling controls.

Validation: `git diff --check` and `script/build_and_run.sh --verify` passed. In the launched Debug app, visual inspection confirmed Add Segment at the right edge of the toolbar and Read Frame Text above the dialog's description field. The accessibility tree exposed Add Segment separately from the controls scroll area and exposed the dialog button as Read Frame Text with help text explaining that it replaces the description using text found at the segment start time. A live Gemini frame-recognition request was not submitted during verification.

### Segment timing conflict validation — 2026-09-08

The Add/Edit Segment dialog now validates timing continuously against the project's transcript and every other audio description. Transcript overlaps and AD-to-AD overlaps appear as blocking red Timing errors with the conflicting segment's millisecond-precision range and a concise text excerpt. Invalid ranges, including an end time equal to or earlier than the start time, display a direct error. Save Segment remains disabled until timing is valid; adjacent boundaries are allowed. The validation summary and repair guidance are combined into a VoiceOver-readable element, and the disabled Save button explains that timing errors must be resolved.

Validation: `git diff --check`, the two focused engine boundary/overlap tests, and `script/build_and_run.sh --verify` passed. An isolated temporary project confirmed the running Debug UI reports transcript overlap at 00:00:01.000–00:00:03.000, reports overlap with an existing AD at 00:00:03.000–00:00:06.000, and reports “End time must be after start time” when Start is 00:00:04.000 and End is 00:00:03.000. The final check used a non-empty description and confirmed Save Segment remained disabled specifically because of the invalid timing. Moving the segment to the clear 00:00:03.000–00:00:06.000 range removed the transcript warning and enabled Save after text was entered. The temporary test profile was removed without modifying the user's project library.

### Relocated processing cancellation control — 2026-09-08

Removed the processing footer that spanned beneath the editor and inspector. While work is active, the center editor now shows a dedicated bar immediately below the video/timeline preview, with the live status on the left and a prominent red Cancel Processing button fixed to the top-right of the main editor pane. The button and status have explicit VoiceOver labels, and the cancellation hint explains that completed results remain saved. The existing large processing indicator remains below the editor controls.

Validation: `git diff --check` and `script/build_and_run.sh --verify` passed. A running isolated Debug app with a local mock processing task visually confirmed that the status and Cancel Processing control remain entirely inside the center pane and do not overlap the inspector. The accessibility tree exposed “Processing status: Preparing isolated validation media” followed by “Cancel Processing” with the stop-operation hint. Activating the relocated button terminated the task and produced the existing “Processing stopped. Your previously completed results are saved.” result. The temporary app/profile were removed without modifying project data.

### Transcript-first editor navigation — 2026-09-08

Projects now open on Transcript instead of Descriptions. The editor picker and Project → Editor Sections menu use the same order: Transcript, Summary, Descriptions, AD Overview, then AD Transcript. The AD views remain adjacent and AD Transcript is last. Command-number shortcuts now follow the visible order: Command-1 through Command-5 respectively. Updated the in-app Help and README to distinguish spoken-dialogue Transcript, authored AD Descriptions, coverage/narration-readiness AD Overview, and the combined chronological AD Transcript.

Validation: `git diff --check` and `script/build_and_run.sh --verify` passed. In the launched Debug app, opening the existing project exposed the Editor section picker with Transcript selected and displayed transcript rows. Opening the picker showed Transcript, Summary, Descriptions, AD Overview, and AD Transcript in order. Project → Editor Sections exposed Show Transcript, Show Summary, Show Descriptions, Show AD Overview, and Show AD Transcript in the same order.

### Synchronized editor timeline playhead — 2026-09-08

The thumbnail timeline below the video now has an editor-style playhead spanning the video thumbnails and AD cue lane. It follows the native or YouTube playback position, and clicking or dragging anywhere on the thumbnail strip seeks to that exact relative position. The timeline header shows the current and total duration with millisecond precision. Its accessibility representation is an adjustable Video timeline slider with the same precise value and a seek hint; individual AD cue buttons remain separately actionable.

Validation: `git diff --check` and `script/build_and_run.sh --verify` passed. In the launched Debug app, the playhead was visually present over both timeline lanes. The accessibility tree exposed a settable Video timeline slider with `00:00.000 of 05:36.396`, and during native playback its value advanced from `00:04.200` to `00:11.100` while the visible playhead moved. Playback was paused after verification. Pointer dragging and live YouTube synchronization were implemented but not independently exercised in this pass.

### Contextual editor generation actions — 2026-09-08

Transcript, Summary, and Descriptions now show their own generation action at the far right of the editor controls. Descriptions places Generate/Regenerate Descriptions beside Add Segment; Summary and Transcript show their corresponding action in the same position. Labels switch to Regenerate whenever that content already exists. These buttons use the same scoped replacement confirmation and processing commands as the inspector. The inspector's Transcript, Summary, and Descriptions labels now follow the same Generate/Regenerate state so both surfaces stay consistent.

Validation: `git diff --check` and `script/build_and_run.sh --verify` passed. In the launched Debug app, Transcript exposed Regenerate Transcript, Summary exposed Regenerate Summary, and Descriptions visibly placed Generate Descriptions and Add Segment together at the right edge. The accessibility tree reported each control with its complete dynamic name and replacement/generation hint. The inspector simultaneously showed Regenerate Transcript, Regenerate Summary, and Generate Descriptions for the same project state. No generation action was activated and no live Gemini call was made.

### Reliable Read Frame Text processing — 2026-09-08

Read Frame Text now pauses playback and captures the selected playhead position before starting AI processing. If the playhead is exactly at the video duration, the UI and engine independently normalize it to the final valid frame 100 milliseconds earlier instead of rejecting it with “Choose a frame inside the video.” Invalid out-of-range timestamps remain errors. While work is active, the existing processing bar and large progress indicator report “Processing text from the selected frame…”. Any frame-text-specific failure uses the alert title “Read Frame Text Processing” rather than the generic “VidiStudio needs attention”; successful completion opens the existing Screen Text review.

Validation: the focused boundary and mocked end-to-end capture tests passed in the project Python environment. The latter submitted an exact-duration timestamp, verified normalization from `10.000` to `9.900` seconds, reached the mocked AI text-processing call, emitted the recognized screen text, and closed the client. `script/build_and_run.sh --verify` rebuilt the bundled engine and launched the Debug app, and `git diff --check` passed. The running accessibility tree exposed Read Frame Text in the rebuilt app. No live Gemini request was submitted during verification.

### View-menu preview recovery and Format cleanup — 2026-09-08

Moved the dynamic Hide Preview / Show Preview command to the standard View menu and retained Command-Shift-V. The command remains available after the preview and timeline are collapsed, while Project → Playback keeps the remaining playback controls without duplicating the preview action. Removed the unused top-level Format menu; because SwiftUI recreates empty standard menu shells during command rebuilding, a narrow AppKit observer removes only the main-menu item titled Format whenever it is reinserted.

Validation: `script/build_and_run.sh --verify` completed with `BUILD SUCCEEDED` outside the restricted compiler sandbox, and `git diff --check` passed. In the rebuilt running app, the accessibility menu bar contained VidiStudio, File, Edit, View, Project, Window, and Help with no Format item. Opening View exposed Hide Preview. Command-Shift-V removed the preview and timeline and changed the surviving editor control to Show Preview; invoking the shortcut again restored the video timeline and its accessible slider.

### Description segment action indicator — 2026-09-08

The description-row Segment actions menu now hides SwiftUI's separate disclosure chevron and displays only the ellipsis action icon. The same contextual actions, disabled processing state, and Segment actions accessibility label are preserved.

Validation: `script/build_and_run.sh --verify` completed with `BUILD SUCCEEDED`, and `git diff --check` passed. In the rebuilt running app, the populated Descriptions row exposed one Segment actions control without a separate disclosure control in the accessibility tree. No segment action was invoked and project data was unchanged.

### Visible editor controls with preview hidden — 2026-09-08

Replaced the zero-height `VSplitView` collapse state, which left the editor controls in the accessibility hierarchy but visually clipped them above the window. The preview now stays mounted inside a persistent vertical layout and collapses to zero without moving the editor. The section picker, in-place Show Preview button, playback/editor controls, contextual Generate or Regenerate action, Add Segment when applicable, and the segment list remain visibly aligned from the top. The replacement preview divider remains pointer-draggable and exposes an adjustable Resize video preview control to VoiceOver.

Validation: `script/build_and_run.sh --verify` completed with `BUILD SUCCEEDED`, and `git diff --check` passed. A screenshot of the rebuilt app with the preview hidden visibly showed the Transcript controls and Regenerate Transcript across the top with transcript rows directly underneath; the video and timeline were absent. Show Preview restored the native video and timeline. The accessible divider successfully adjusted from 413 to 453 points and back. No project content or processing action was changed.

### Description origin labels and counts — 2026-09-08

Added persisted origin metadata to AD segments and shared Material Symbols icon/text labels in Descriptions and AD Transcript. Categories are AI-generated, AI-generated · modified, Manually added, and Origin unknown. AD Overview shows separate counts for each category with the same icons and accessible labels. Legacy segments without provenance remain unknown rather than being inferred from IDs or narration files.

AI generation and frame-text capture record AI origin. Saving changes to an existing AI segment's text or timing marks it modified; manual edits retain manual origin. New frame-text descriptions edited before first save are marked modified using the captured text baseline. Rewrite to Fit marks known AI descriptions modified and records newly AI-rewritten manual/unknown text as AI-generated. Existing undo/redo snapshots preserve the metadata alongside other segment fields.

Per the user's explicit instruction, no tests, build, launch, or UI verification were performed for this change. The user will test manually; the running app must be rebuilt to include these changes.

### Video volume reduction during narration — 2026-09-08

Added soundtrack ducking for saved narration playback and live Apple Speech. While narration is playing, the native video's volume is reduced to 20% of the user's selected volume; the original volume is restored when narration ends, the cue ends, playback pauses, narration is disabled, seeking occurs, or the editor stops playback. Missing/nonplaying narration does not trigger ducking. Volume changes made during narration are retained as the new baseline, and mute state is untouched. The YouTube player uses the same relative reduction and restoration through its JavaScript player controls. Existing playback-position updates check actual narration playback/speech state, including completion before the segment end.

Code changes only, following the user's manual-testing preference: no tests, builds, app launches, or listening checks were performed. Rebuild before manually checking both narration modes.

### Time component steppers — 2026-09-08

Replaced the Add/Edit Segment start/end time text fields with native numeric steppers for hours, minutes, seconds, and milliseconds. Values retain leading zeros and aligned unit headings. Each focused control handles Up/Down Arrow to increment/decrement by one and exposes its start/end unit label and numeric value to accessibility. Hours are bounded to 0–99, minutes/seconds to 0–59, and milliseconds to 0–999, with the existing video bounds and timing validation preserved.

Code changes only. No tests, builds, launches, or UI verification were performed, per the user's manual-testing preference.

### Live Apple Speech settings fidelity — 2026-09-08

Source inspection confirmed live speech already applies the configured Apple speech rate, pitch, and volume. Fixed silent default-voice fallback: voice resolution now prioritizes exact identifiers and respects Enhanced/Premium quality when matching names. An unavailable selected voice reports a visible error instead of speaking with an unrelated default voice; the system default is used only when explicitly selected. Settings voice samples share the same resolution and error behavior.

Live playback now keys utterances on the Apple settings signature independently of the saved-audio engine, so changing Apple voice/rate/pitch/volume restarts the active narration even when Gemini is selected for synthesis. Settings exposes Apple voice controls whenever live Apple playback is selected, including alongside Gemini synthesis settings, with an explanation of which settings apply. Speech volume continues to use the configured 0–1 value (default 1); soundtrack ducking is separate.

No tests, build, launch, or listening checks were performed, per the user's manual-testing preference. Findings are based on code inspection, not confirmation of the specific voice heard on the user's Mac.

### Per-segment synchronized audio status — 2026-09-08

Descriptions and audio-description rows in AD Transcript now show a shared icon and text status: Synchronized audio generated, Synchronized audio needs regeneration, or Synchronized audio not generated. Generated status requires a saved audio file that still exists and matches both the current segment text and narration settings; edited text, changed narration settings, or other stale metadata reports regeneration required. Missing files report not generated. Transcript-only rows do not display an AD audio status.

AD Overview now derives its ready, stale, and missing counts from the same shared resolver, keeping overview totals consistent with row labels. Each visible status combines its Material Symbols icon with explicit text and a unified accessibility label. No tests, build, launch, or UI verification were performed, following the user's manual-testing preference.

### Text-only description generation and required context — 2026-09-08

Confirmed in source that Generate/Regenerate Descriptions invokes only the timed-text video analysis stage; neither that stage nor the analysis pipeline invokes narration synthesis. Added inspector wording explaining the separate Synthesize Narration step. Generated AD results now retain only fresh IDs, text, times, and AI-origin metadata, preventing model-supplied audio paths or stale synthesis fields from marking new text as generated audio.

Description requests now append mandatory project context independently of customizable prompt placeholders: the full transcript, summary, video duration, and dialogue-free ranges computed from merged transcript coverage. Instructions require visual grounding in the attached video, attention to untranscribed speech/important sounds, short text that fits the gap, and non-overlapping segments. Existing engine validation rejects transcript overlaps, AD overlaps, and invalid times before replacement is assigned. Agentic video processing remains governed by the configured processing mode; actual narration duration is checked separately during explicitly requested synthesis.

No tests, builds, launches, or live Gemini requests were performed, per the user's manual-testing preference. Code inspection confirms the routing and validation; live model output and listening quality remain unverified.

### Confirm incomplete narration before video export — 2026-09-08

Export Final Video now rereads the saved project and shows a warning if AD narration is missing/outdated or there are no AD segments. The dialog reports the affected count, explains that unavailable descriptions will be omitted and no narration is synthesized automatically, and offers default Cancel or Export Anyway. Fully generated projects proceed normally.

Only confirmation supplies the engine's new allow-incomplete-narration option. With it, the final video includes current available narration and omits missing/stale audio; a project without any usable narration exports its original soundtrack (or silence for a silent source). Without the option, incomplete narration remains blocked. Existing timing validation and narration-duration checks remain enforced. Narration-only export retains its strict behavior.

No tests, builds, app launches, or exports were run, following the user's manual-testing preference.

### Confirm incomplete narration before audio export — 2026-09-08

Extended the shared incomplete-narration confirmation to Export Narration Audio. Both export commands reread saved segments, show missing/outdated counts, default to Cancel, and pass the explicit incomplete-export flag only after Export Anyway. Audio-specific wording explains that unavailable descriptions are omitted and an export with no usable narration will be silent. The audio export engine now honors that opt-in; normal audio exports still reject missing/stale narration. This supersedes the earlier note that narration-only export is always strict.

Code changes only; no tests, builds, launches, or exports were performed, per the user's manual-testing preference.

### Distinct AD indication sounds and Narration settings routing — 2026-09-08

Bundled the two user-supplied WAV files in VidiStudio/Sounds. Narration settings now have independently persisted, default-enabled switches: Boink3 indicates entering an AD segment with narration disabled; ascend indicates entering a segment with narration enabled and synthesized playback selected but saved audio missing or outdated. Live Apple Speech has no additional cue. Indications do not alter video volume, repeat on periodic playback updates, or create exported audio. Pausing stops the sound; seeking permits a new entry indication. Disabling either option stops its indication, and disabling both silences all such cues.

AD Overview's Voice and Narration Settings action now sets shared settings navigation to Narration before opening the native Settings scene, including when the settings window already exists. Native controls and explicit shared section selection follow the macOS SwiftUI settings guidance.

Code and asset changes only. No tests, builds, app launches, or listening checks were run, as requested.

### Generic player sound wording — 2026-09-08

Replaced the two indication sound names in Narration settings descriptions with "player sound". Sound assets, distinct conditions, and speech voice selection remain unchanged. No tests or builds run.

### Duck video for AD player sounds — 2026-09-08

Both short AD indication sounds now request the same relative soundtrack ducking as narration: the native or web video volume falls to 20% of the user's current level only while the indication is playing, then returns to the prior level. Separate narration and indication duck requests prevent one audio path from prematurely restoring the soundtrack while the other remains active. Stopping playback, leaving the segment, or disabling the applicable sound restores the video volume.

Validated with `./script/build_and_run.sh --verify`: the Debug app compiled, signed, launched, and passed process verification. The only build diagnostic was the expected App Intents metadata skip because the target does not link AppIntents. Both PCM WAV resources were present in the built app. Exercised the current saved project at its 05:00 AD segment with Narration off; playback entered the cue without a crash. Accessibility automation cannot capture or quantify physical speaker output, so the perceived loudness balance remains a manual listening check.

### Address Xcode editor type-check and playback capture diagnostics — 2026-09-08

Split ProjectEditor's long body modifier chain into opaque view expressions for project, playback, and voice updates, and extracted the focused shortcut action construction into a separately typed property. This reduces the expression complexity reported by Xcode while preserving the handlers. Nested main-actor tasks in the periodic time observer, frame-time capture, and seek completion now explicitly capture weak self rather than referencing the enclosing callback's captured variable, addressing the reported Swift concurrency warnings.

Source changes only; no builds, tests, or launches were run under the user's manual-testing preference. Compiler success remains unverified pending the next Xcode build.

### Gate description generation on completed transcript and summary — 2026-09-09

Generate/Regenerate Descriptions is now disabled in the project inspector, the Descriptions editor action, and Project → Analysis & Regeneration until the project has a completed transcription artifact and a non-blank summary. Editor-section navigation remains independent, so Transcript, Summary, Descriptions, AD Overview, and AD Transcript stay available. The focused shortcut action and `StudioModel.execute` enforce the same rule, and the Python engine retains a final prerequisite check. A completed empty transcript is accepted for a silent video because completion is based on the saved transcript artifact rather than requiring spoken segments.

Validation: the focused engine prerequisite regression test passed, `git diff --check` passed, and `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` completed with `BUILD SUCCEEDED` and launched the Release app. In the running Release app, the saved project with completed prerequisites exposed Regenerate Descriptions in the inspector, and the editor picker successfully navigated to AD Transcript while retaining all five section choices. No Gemini generation action was invoked. The disabled appearance for a deliberately incomplete project was covered by shared-state logic and the focused prerequisite test, but was not exercised by altering the user's saved project.

### Granular generated-content deletion — 2026-09-09

The inspector now places accessible delete buttons beside Regenerate Transcript, Regenerate Summary, and Regenerate Descriptions. Each opens a destructive confirmation specific to that component. The project list and grid context menus now open a native selection sheet instead of immediately deleting all generated content. The sheet provides Select All plus independent Transcript, Summary, AD Descriptions, Narration Audio, Thumbnails, Exports, and Edit History checkboxes; unavailable categories are disabled with an explanatory accessibility hint. Transcript and AD-description copy explains how each affects the derived AD Transcript view. The project and original local video or YouTube link are always retained.

The engine's new `delete-generated` command deletes only the selected component paths and project fields. Deleting AD descriptions also removes their narration and cue edit stacks; deleting narration alone keeps AD text/timing and rewrites cue metadata without audio fields. Path containment and symbolic-link safeguards protect original media. Existing whole-project generated-content clearing remains available internally for compatibility.

Validation: focused selective-deletion and description-prerequisite tests passed, including original-video preservation and independent deletion of summary/narration followed by transcript/descriptions/thumbnails/exports/history. `git diff --check` passed. `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` completed successfully and launched the Release app. In the running Release app, accessibility inspection confirmed adjacent Delete Transcript, Delete Summary, and Delete AD Descriptions inspector buttons; the Summary action opened the expected Cancel-first confirmation and was cancelled. The project-row context menu opened the granular deletion sheet, exposed all seven labeled checkboxes, selected every available category with Select All, enabled Delete Selected, and was cancelled without changing project data. No generated or user project content was deleted during UI validation.

### Content-aware Export Text options — 2026-09-09

Export Text now disables each content submenu when it cannot produce the named output. Transcript requires at least one transcript row, Descriptions requires at least one AD segment, and Combined requires both transcript and AD rows so it represents a genuine combined export rather than duplicating one section. The parent Export Text menu remains available, allowing disabled choices and their explanatory help text to remain discoverable.

Validation: `git diff --check` passed and `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt and launched the Release app. In the saved project containing both transcript and AD rows, accessibility inspection exposed enabled Transcript, Descriptions, and Combined submenus with the expected export help text and all four formats. The disabled states for missing content are enforced by the shared project-content predicate but were not exercised by deleting or modifying the user's saved project.

### Prevent silent narration-only exports — 2026-09-09

Export Narration Audio is now enabled only when at least one AD segment has an existing synchronized audio file whose text and narration-settings signature are current. AD text without synthesized audio, missing files, and outdated narration therefore do not enable the action. The disabled control explains that narration must be generated for at least one AD segment. The export confirmation path and Python engine independently enforce the same minimum, so incomplete-export permission can omit some unavailable segments but can no longer create an entirely silent narration file.

Validation: focused all-silent narration rejection and selective-deletion tests passed, `git diff --check` passed, and `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt and launched the Release app. In the running Release app, the current project had an AD segment without generated narration; accessibility inspection confirmed Export Narration Audio was disabled with the help text “Generate narration audio for at least one AD segment first.” No export was started and no project data changed.

### Per-segment narration preview button — 2026-09-09

Each row in Descriptions now displays a dedicated Play Narration icon immediately before Edit. The action uses the shared synchronized-audio resolver and is enabled only when that specific AD segment has an existing audio file matching its current text and narration settings. Missing or outdated audio leaves the icon visible but disabled with the help text “Generate synchronized audio for this AD segment first.” Starting another preview stops the previous one, and playback failures use the existing app alert.

Validation: `git diff --check` passed and `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt and launched the Release app. In the running Release app, the current AD row reported Synchronized audio not generated and visibly showed the dimmed Play Narration icon directly beside Edit; accessibility inspection included Play Narration in the row. No narration was synthesized or played, so the enabled/audio-output path remains unexercised in this saved project.

### Consistent AD segment wording in narration warnings — 2026-09-09

User-facing narration validation, synthesis progress, and export errors now say “AD segment” instead of “cue”. The duration warning shown when synthesized narration does not fit its available gap now reads, for example, “AD segment 1 takes 14.8s but has 10.4s. Shorten its text or extend its gap.” Internal cue variable names and portable project-data keys remain unchanged for compatibility.

Validation: the focused narration-fit wording regression test passed, `git diff --check` passed, and `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt and launched the Release app successfully. The alert itself was not live-triggered because doing so would synthesize narration and modify the user's saved project.

### Back to all projects from the editor — 2026-09-09

The project editor now begins with a native Back to Projects button. Activating it clears the selected project, closes the inspector, and clears the search filter so every project is available. It opens a new full-width All Projects page rather than relying on the editor sidebar. The page has its own search field, persistent List View/Grid View switcher, project count, New Project and Open Project Folder actions, and the same per-project context actions available from the sidebar. The user's chosen list or grid layout is preserved between the dedicated page and sidebar. The back button has an explicit “Back to All Projects” accessibility label and help text.

The currently open project's right-click menu also includes Close Project in both sidebar layouts. It performs the same safe return to All Projects without deleting or changing the project.

Validation: `git diff --check` passed and `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt and launched the Release app successfully. The new `ProjectBrowserPage.swift` was compiled into the Release executable. A live accessibility pass was attempted, but the UI controller could not attach because multiple running VidiStudio bundles share the same bundle identifier and attachment timed out even with the exact Release app path; the Back/List/Grid/Close interactions therefore remain visually unverified in this run.

### XcodeBuildMCP for Codex — 2026-09-09

Registered the global Codex MCP server `xcodebuildmcp` using `/usr/local/bin/npx -y xcodebuildmcp@latest mcp`. Added `.xcodebuildmcp/config.yaml` with VidiStudio project, scheme, Debug configuration, and macOS platform defaults, enabling the macOS, project-discovery, debugging, and utilities workflows. Startup verification loaded XcodeBuildMCP 2.7.0, found the repository configuration, hydrated all four defaults, registered 26 tools plus four resources, and reported that the stdio server started successfully. Codex must reload its MCP servers in a new task or app session before the tools appear in the active tool catalog.

### Finder-style project opening and grid sizing — 2026-09-09

All Projects is now the persistent browser window. A single click selects a project without replacing the browser; double-clicking a list row or grid tile opens that project in its own repeatable Project Editor window. Each editor owns an independent `StudioModel`, so opening another project does not retarget an existing editor. The accessible Open Project action, Return key, and context-menu command provide equivalent non-pointer paths. The editor's Back to All Projects button brings the browser forward and closes only that editor window.

Grid View now has a Finder-inspired bottom-right Project icon size slider, flanked by small and large grid symbols. It resizes both adaptive project tiles and their thumbnails from 140 to 300 points in 10-point increments, exposes its size and help to accessibility, and persists the chosen size across launches.

Validation: `git diff --check` passed. The first Release verification attempt was blocked by the restricted sandbox because Xcode's Observation macro plugin server could not run there. Re-running `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` outside that restriction succeeded. In the exact Release bundle, accessibility inspection confirmed the All Projects browser, the selected project tile's “Double-click to open this project in a new window” hint and Open Project action, and the Project icon size slider. A single click left All Projects open; a double-click opened `project-editor-AppWindow-1` with the project title, independent inspector, and Back to All Projects button. Back returned to the intact All Projects window. Incrementing the slider changed its live accessible value from 180 to 190 points. A final Release rebuild after command-routing cleanup also passed and launched process 27402.

### Finder-style open, rename, and unique project windows — 2026-09-09

All Projects now follows Finder's keyboard conventions. Command-O opens the selected project in its editor, while Command-Shift-O opens the external project-folder chooser. Return or Enter starts renaming the selected project in both List and Grid View. Double-click remains the pointer path for opening. The shortcut reference documents all three commands.

Project editor windows remain keyed by project ID through the value-based `WindowGroup`. Every opening path sends the same stable project ID, so opening a project that is already open activates its existing editor rather than creating another instance. Different project IDs can still own independent editor windows.

Validation: `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` passed and launched the final Release process 28351. In the exact Release app, Command-O opened the selected project as `project-editor-AppWindow-1`. After returning to the still-open All Projects window and invoking Command-O for the same selected project again, the app reactivated `project-editor-AppWindow-1`; no `AppWindow-2` was created. In the final Release build, pressing Return on the selected project opened the rename sheet in List View and again in Grid View, with the existing project name selected and Cancel/Rename actions present. Both checks were cancelled, so the user's project name and files were unchanged.

### Settings gear on All Projects — 2026-09-09

All Projects now includes a native Settings gear at the leading edge of its bottom footer in both List and Grid views. In Grid View it balances the Finder-style project-size slider on the opposite side. The control uses `SettingsLink`, preserving the app's dedicated Settings scene and standard Command-Comma behavior, with the accessibility label “Settings” and help text “Open VidiStudio Settings.”

Validation: `git diff --check` passed and `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt and launched the Release app as process 28871. Accessibility inspection of the exact Release bundle confirmed a Settings button with the `gearshape` identifier and the expected help text beside the 190-point Project icon size control. The dedicated Settings scene was also opened in the running Release app and exposed its Appearance window.

### Project navigation and browser action placement — 2026-09-09

Moved the project editor's Back to All Projects action from the editing strip below the video into the upper-right native window toolbar. It now renders as only the `chevron.backward` icon while retaining the accessible name “Back to All Projects” and the help text “Return to all projects.” The inspector toggle remains beside it. Removed the duplicate New Project and Open Project toolbar icons from All Projects; the prominent blue New Project button and Open Project Folder button remain in the page header, along with their existing menu and keyboard access.

Validation: `git diff --check` passed. The project-provided Release shell verification was blocked by the restricted host's Swift macro sandbox, so the configured Xcode integration built and launched the same Release scheme successfully as process 29913. Live accessibility inspection of that Release app confirmed that All Projects contains only the in-page New Project and Open Project Folder actions, with no corresponding title-bar toolbar items. Opening the saved project exposed an icon-only `chevron.backward` toolbar button named “Back to All Projects” beside Hide Inspector, and activating it returned to the intact All Projects window.

### Transient narration playback and Read & Speak voice resolution — 2026-09-09

Narration during playback is now deliberately transient. Every newly opened project starts with Play synthesized narration, and Save Settings persists that default instead of remembering a project's temporary Preview segment text with Apple Speech choice. Saving Settings still broadcasts the current transient choice and all voice controls to already-open project windows, so live preview can be selected and used for the current editing session without becoming the next project's default. The Narration pane explains this behavior.

System default Apple speech now explicitly resolves the current-language voice from macOS Accessibility → Read & Speak for both live `AVSpeechSynthesizer` playback and Python-engine `/usr/bin/say` narration generation. The Narration pane displays the resolved voice name. An explicit VidiStudio voice override remains higher priority. The effective Read & Speak identifier is included in the narration-settings signature so an explicit Generate Missing or Changed Audio action can identify files created with earlier settings; the preservation rule documented below keeps those files playable and exportable until their segment text changes.

Validation: two focused resolver/override tests passed, followed by all 15 engine tests against the bundled Release engine. Xcode integration rebuilt and launched the Release app. On this Mac, direct preference resolution returned `com.apple.voice.enhanced.en-US.Nathan`, and the live Narration pane displayed “Selected: System default (Nathan (Enhanced)).” The system-default sample action ran without an app error. Allison Enhanced was then restored and saved; the configuration retained `systemVoice: Allison (Enhanced)` while persisting `narrationPlayback: generated`. A config containing the prior `device` choice was loaded into a newly opened editor and visibly reset to Play synthesized narration. For the current open editor, Preview segment text with Apple Speech was selected and saved, Narration was enabled at the 00:04 AD segment, and playback ducked the video from 100% to 20% while live speech was active without playing the missing-synthesized-audio path. The final Release app was restarted as process 32316 so the editor is again paused with Narration off and its playback choice reset to Play synthesized narration. No project narration was synthesized and no project content was modified during the live check.

### Preserve generated narration across voice changes — 2026-09-09

Existing WAV/MP3 narration is now considered synchronized whenever its saved text still matches the AD segment and its file exists. Its recorded voice/settings signature remains provenance and continues to control whether the explicit Generate Missing or Changed Audio action regenerates it, but changing the current Apple or Gemini voice no longer disables playback, labels the existing file as stale, triggers the missing-audio sound, or omits it from video and narration-only exports. Newly generated or explicitly regenerated narration still uses the latest saved voice, rate, pitch, and volume. Live Apple Speech continues to use those latest saved settings immediately and creates no project audio file.

AD Overview now displays the resolved Read & Speak voice in the same form as Settings, such as “System default (Nathan (Enhanced)).” It also explains that the overview shows the last saved voice because the Settings window is an editable draft until Save Settings is activated. Saved settings notifications now synchronize in both directions: Settings updates open project windows, and settings saved by an editor-side generation action update the All Projects/Settings model. Saving the system-default selection was observed updating the open project from Allison to System default without modifying narration files.

Validation: added a regression proving an earlier-voice file remains usable while changed description text does not, and strengthened the real media pipeline to change speech settings after synthesis before export. All 16 tests passed against the packaged Release engine with macOS speech access. The configured Xcode integration rebuilt and launched the final Release scheme successfully as process 34442. The user's current project has no generated narration files, so live old-voice file playback/export was not exercised against that project; the packaged engine regression covers the export rule without creating or replacing user project audio.

### Automatic settings and project narration preference — 2026-09-09

Removed the Settings window's Save Settings button, Command-S help entry, draft-state concept, and forced Play synthesized narration reset. Every app-wide setting now writes the complete configuration atomically as soon as its SwiftUI value changes and broadcasts the update to all open windows without notification loops. This covers appearance, follow behavior, narration engine/playback/sounds, Apple and Gemini voices, voice controls, API/model/prompt fields, storage, and media-tool paths. The Settings window now states that changes save automatically, and AD Overview no longer invokes or asks for an explicit save before synthesis.

Added a project-specific Narration during project playback switch to Settings → Narration. It names the selected project, uses that project's stable ID for durable storage, and mirrors the editor's Narration button through a dedicated change notification. Each project therefore restores its own Narration on/off choice when reopened without changing generated narration or project media.

Validation: `git diff --check` passed and the configured Xcode integration built and launched the final Release app as process 35559. Live accessibility inspection confirmed the Settings toolbar contains only Hide Sidebar, the page says “All settings changes are saved automatically,” and there is no Save Settings action. Toggling Follow off immediately wrote `followTranscript: false` to the configuration and updated the live control; it was restored to true. The current project's Narration button was turned on, the editor closed, and reopening the project restored Narration on. The new Settings → Narration switch then displayed that project by name, changing it updated the editor button immediately, and the original off value was restored after validation. No project content or generated media was changed.

### Open-project playback settings — 2026-09-09

Removed the automatic-save status message from Settings while retaining immediate persistence for every app-wide control. Added a Projects destination to the Settings sidebar. It lists only projects with an open editor window, groups controls under each project name, and currently exposes both project-specific playback preferences: Narration during playback and Follow synchronized transcript. Both switches mirror the matching editor controls immediately and persist by stable project ID, so their values return when the project is reopened. Closing an editor removes its project from the visible Settings list without deleting those saved values.

Validation: `git diff --check` passed and Xcode integration built and launched the Release scheme successfully as process 36123. In the running Release app, Settings → Projects displayed Dilemma S2 Episode 3 Thre Trade with Narration off and Follow on, matching the open editor, and the automatic-save message was absent. Closing the editor changed the page to “No Open Projects.” Reopening the project restored both the project entry and its Narration-off/Follow-on values. The app was left with the project open, and no project content or generated media was changed.

### Stateful Apple voice sample control — 2026-09-09

Replaced the separate always-enabled Stop Sample action in Settings → Narration with one stateful Apple voice sample control. It displays Play Sample while idle and changes to Stop Sample only while `AVSpeechSynthesizer` reports active playback; natural completion or cancellation returns it to Play Sample. Use system default voice, Play/Stop Sample, Refresh Voices, and Open macOS Voice Settings now appear together beneath the voice list.

Validation: `git diff --check` passed and the configured Xcode integration built and launched the Release app without warnings as process 37189. Live accessibility inspection confirmed the consolidated bottom action row. Activating Play Sample changed the same control to Stop Sample during speech; activating it again stopped playback and restored Play Sample. The selected voice and other settings were not changed.

### Apple Help Book — implementation and build evidence, 2026-09-09

Added an offline 13-page Help Book with a persistent table of contents, focused topics, Home and previous/next navigation, semantic headings/tables, keyboard access, and system-adaptive light/dark styling. Content covers onboarding, projects, all editor sections, description authoring, processing and deletion, narration modes and voices, exports, settings, shortcuts, troubleshooting, privacy, and glossary. Editor shortcut rows are extracted from the app's authoritative shortcut definitions at build time.

`script/build_help.py` assembles the bundle, validates every internal topic link/anchor, and creates an Apple Help search index using hiutil. The Xcode engine-resource build phase now includes this book. Help menu and Settings both call the shared NSHelpManager registration/anchor route; the obsolete short SwiftUI Help window was removed. Explicit Config/Info.plist metadata is merged with Xcode's generated app metadata because custom INFOPLIST_KEY build settings did not appear in the initial built plist.

Validation: all 13 generated pages passed internal-link validation; the Release app includes the 31 KB search.helpindex and both CFBundleHelpBookFolder and CFBundleHelpBookName keys. `VIDISTUDIO_CONFIGURATION=Release script/build_and_run.sh --verify` succeeded (PID 39140); `git diff --check` passed. The first sandboxed build could not execute Swift observation macros; the authorized unsandboxed build succeeded. Runtime Help Viewer navigation, native search, and light/dark rendering remain unverified: computer access reports the Mac is locked. Do not treat this as completed Help Book QA until the Mac is unlocked and those paths are exercised.

Runtime follow-up after unlock: the Help menu and Settings → Help → Open VidiStudio Help both opened the registered offline book in macOS Tips/Help Viewer. Verified table-of-contents navigation to Narration, Next to Exports, Previous back to Narration, and the in-page Home link. Native search for “narration” returned a VidiStudio Help group with 13 results; selecting its narration result opened narration.html#narration. Dark rendering was visually inspected at the current wide window size. Accessibility exposes semantic headings, the named contents navigation, links, and description lists. Option-Tab focused the visible Skip to topic link and Return navigated to #topic. This is AX/keyboard evidence, not a claim of a full spoken VoiceOver listening audit. Light-mode visual inspection awaits permission to briefly change system appearance (Help Viewer does not follow the app-only theme).

Added script/verify_help.py to check the packaged app registration, expected topic files/anchors, navigation links, stylesheet, and nonempty search index. It passes against the Release bundle and now runs from build_and_run.sh before signing/launch. Documentation sources remain under docs/help; the generated keyboard table follows StudioShortcut.editor.

### Illustrated Help and neutral navigation — 2026-09-09

Captured six actual application screenshots using Computer Use: All Projects, the editor/Transcript with inspector, and Narration settings, each in Light and Dark appearance. Saved the unaltered captures under docs/help/images and embedded adaptive images with captions and alternative text in eight relevant Help pages, including Home. Restored the app's original System appearance after capture; no project content, voice, or narration preferences were changed.

Help links now inherit black/white text without underlines, with neutral hover backgrounds and a visible keyboard-focus outline. Image assets are bundled and checked by the build verifier. Updated app version to 1.0.1 (2) and Help registration to the illustrated v2 book: the existing Help Viewer cache continued serving the old book even after a normal version update, while the revision-specific book identifier loaded the new content correctly without deleting user caches.

Validation: Release build-and-run --verify passed (PID 42004), including packaged checks. Live Computer Use inspection of the registered v2 Help home confirmed the editor screenshot, accessible image description/caption, and white non-underlined table-of-contents links. Both theme image sets are bundled; current native Help rendering was verified in Dark mode.

### Stable editor title bar during playback — 2026-09-09

Reproduced the reported menu/title-bar flash in the Release app: a five-frame Computer Use capture during playback showed the project title disappearing for an individual frame and returning. Code review found that ProjectEditor applied a second `navigationTitle(project.name)` inside the subtree observing the playhead every 150 milliseconds, while ProjectEditorWindow already owns the stable window title. Removed the redundant inner modifier so playback invalidation no longer writes window chrome.

Validation: the configured Release build and packaged Help checks passed, and the new app launched as PID 45817. An eight-frame Computer Use capture over roughly seven seconds of active playback retained “Dilemma S2 Episode 3 Thre Trade” in the title bar in every frame while the video, playhead, and transcript-follow state advanced normally. Playback was paused after the check. This directly contrasts with the pre-fix capture, where the same title disappeared in one of five frames.

### Final-video narration ducking — 2026-09-09

Final described MP4 exports now match the editor's narration balance. The export filter keeps the original soundtrack at its normal level between descriptions and reduces it to 20% only for the actual duration of each usable saved narration file. Existing WAV/MP3 narration remains unchanged and is mixed as generated; no narration is regenerated merely to apply ducking.

Validation: the focused ducking-filter regression passed. A stereo signal fixture measured the source channel at -20.6 dB outside narration and -34.6 dB during narration, a 14.0 dB reduction matching a 20% volume multiplier. The packaged Release engine then passed its real eight-second import, system-speech synthesis, and final-MP4 export pipeline. `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt the packaged engine and app, passed all 13 Help Book checks, and launched the final Release app as process 47267. The broader in-process engine suite had one expected restricted-environment failure because macOS system speech produced no audio; that same speech-dependent pipeline passed against the packaged engine with OS speech access.

### YouTube URL export boundary — 2026-09-09

YouTube projects now consistently remain URL-backed viewing projects. They always use the embedded YouTube player and never expose Attach Local Video Copy or Export Final Video in the inspector. The Project menu has no final-video command. A direct app command and the Python engine both reject final combined-video export for every project whose source type is YouTube, including older projects that may retain a legacy attached source file. Transcript, description/combined text, Markdown summary, and generated narration-audio exports remain available.

Added Summary to Export Text as a Markdown-only export. Its generated `.md` file contains a Summary heading and the project summary; timed transcript/description exports retain their existing SRT, VTT, TXT, and JSON formats. Updated the Projects and Exports Help topics to explain URL-only playback and the export boundary.

Validation: focused YouTube rejection, ducking, and Markdown summary tests passed, followed by the complete parity test class. Help generation validated all 13 pages and their internal links. `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt and launched the final Release app as process 49883 with the packaged engine and Help checks passing. A temporary YouTube URL project created through that packaged engine returned exit status 1 with “Final video export is unavailable for YouTube URL projects. Export text or narration audio instead.” No user project was created or modified for this check.

### Descriptive export filenames and deletion — 2026-09-09

All newly generated exports now use a portable descriptive filename containing the project name, export type, and local export date/time: `Project Name - Export Type - YYYYMMDD-HHMMSS.ext`. Export types include Final Video, Narration Audio, Transcript, Summary, Descriptions, and Combined Text. Invalid cross-platform filename characters are replaced, long project names are bounded, and a numeric suffix prevents collisions when the same export type is created twice within one second. Existing exports retain their current names.

Every item in the inspector's Exports list now has its own icon-only Delete Export action with an accessible name and filename-specific help. Deletion asks for confirmation, removes the item from the project, and moves the file to the project's internal `metadata/trash` folder rather than immediately erasing it. The Help Book explains both naming and removal behavior.

Validation: focused filename, collision, text/summary export, YouTube restriction, ducking, and delete tests passed. The Release build repackaged the engine, passed all 13 Help Book checks, and launched as process 51141. The packaged end-to-end pipeline then synthesized narration, exported and probed a correctly named final MP4, deleted it through the packaged `delete-export` command, confirmed its removal from the exports list and original path, and confirmed recovery content in the internal Trash folder. Live accessibility attachment to the rebuilt app timed out, so the exact rendered delete-row layout was not separately observed; Swift Release compilation and the engine lifecycle are verified.

### Segment and bulk narration-audio deletion — 2026-09-09

Each row in Descriptions now keeps Preview Narration visible but disables it whenever synchronized audio is unavailable. Its Segment actions menu adds Delete Segment Audio, enabled whenever the segment has an audio reference. After confirmation, this stops active preview/narration, removes only that generated audio file and its synchronization metadata, and preserves the segment's ID, text, timing, and origin. Synthesize This Segment can recreate the audio afterward.

The inspector now places a narration trash action beside Synthesize Narration whenever any segment has generated audio. It uses the existing Narration Audio generated-content operation to delete every segment audio file and clear only audio metadata; all description rows and timing remain. The Descriptions Help topic documents both deletion scopes.

Project → Segments now also contains Delete All Narration Audio… with Command-Option-Delete. The command is disabled while processing or when no segment has generated audio, uses the same confirmation and bulk deletion path as the inspector, and broadcasts a project-scoped stop event so active preview or synchronized narration stops before either bulk or segment-specific audio deletion. The generated keyboard reference includes the menu command and shortcut.

Validation: focused selective and bulk deletion regressions passed along with narration-usability coverage. `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt the packaged engine and Release app, passed all 13 Help Book checks, and launched process 52712. After the Project-menu addition, the same Release verification passed again and launched process 53251; the packaged Help Book contains Delete All Narration Audio… and Command + Option + Delete in its generated keyboard table. The packaged end-to-end engine pipeline generated a segment's narration, deleted only that audio, verified the description text and row data remained while the file and audio metadata disappeared, regenerated the segment, completed a final-video export, and finally bulk-deleted narration while again verifying the edited description remained. Computer Use could enumerate the running Release process but timed out attaching to its accessibility tree, so rendered menu/control inspection remains unverified; Release compilation, generated shortcut evidence, and both packaged deletion paths are verified.

### Stateful description narration controls — 2026-09-09

Every description row now presents a stateful Play/Pause/Resume Narration control plus a separate Stop Narration control. Starting a segment replaces Play with Pause; pausing replaces it with Resume without losing the current position; Stop resets the preview and returns the primary control to Play. Only the active or paused segment has Stop enabled, starting a different row stops the previous preview, natural completion clears the active state, and unavailable synchronized audio disables Play/Pause. The Segment actions menu mirrors the same state and controls.

Validation: Help generation passed all 13 pages and internal links, and `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` built, packaged, signed, and launched Release process 54463. Live Computer Use inspection of that exact Release app opened the saved project and Descriptions view. Accessibility exposed Play Narration and Stop Narration against all 18 segments. On the first segment, Play changed to Pause during audio, a second activation changed it to Resume, and Stop returned it to Play; the control was left stopped. This check only played existing narration and did not modify project files or segment data.

### Stable menu focus during playback and top-level Playback menu — 2026-09-09

Moved the editor's playback commands out of Project → Playback and into a dedicated top-level Playback menu. It contains Show or Hide Preview, Full-Screen Video, Play or Pause, five-second backward/forward seeking, and Toggle Narration with the existing keyboard shortcuts. Project now contains only Editor Sections, Segments, and Analysis & Regeneration.

The focused menu-command bridge is now one stable observable reference owned by `ProjectEditorWindow`, above the subtree that redraws for every playhead update. The editor updates that bridge only when command availability or project content changes. Previously, `ProjectEditor` constructed a new focused value, including new closures, whenever its body was invalidated by the 150-millisecond playback timer; SwiftUI could consequently rebuild an open menu and move focus into AVPlayer controls. Keeping the bridge identity stable prevents playhead ticks from replacing the focused command set.

Validation: Computer Use reproduced the remaining pre-fix focus movement during playback: while the playhead advanced, accessibility focus moved to the native player's Mute control without user input. `VIDISTUDIO_CONFIGURATION=Release script/build_and_run.sh --build-only` then built the final Release bundle successfully, the packaged Help verifier passed all 13 pages, and `git diff --check` passed. A post-fix live playback/menu check could not be completed because the fresh app launch blocked inside `StudioModel.reload()` while macOS was opening `/Users/personal/Documents/VidiStudio Projects`; a process stack sample located the wait in `FileManager.contentsOfDirectory`. The blocked verification process was stopped, so no hung VidiStudio instance was left running. This filesystem-access stall is independent of the compiled menu-command change and must clear before rendered menu stability can be re-observed.

### Duplicate source project prevention — 2026-09-10

New Project now rejects a local video when its case-insensitive filename matches the source filename of any existing local project known to the app. It rejects a YouTube video when its canonical 11-character video ID matches an existing YouTube project, including equivalent watch, short-link, Shorts, embed, live, and privacy-enhanced URL forms. The native preflight keeps the New Project sheet open, selects the existing project, and presents a “Project Already Exists” alert directing the user to continue with that project or delete it before continuing. The packaged Python engine independently scans every project in the selected library before probing, copying, fetching a title, or creating a project folder, so command-line and stale-view paths cannot bypass the rule.

Validation: two new regressions cover case-insensitive local filenames and equivalent canonical YouTube URLs; all 31 Python tests passed with macOS speech access. `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt the packaged engine and Release app, passed all 13 Help Book checks, and launched process 62567. In that exact Release bundle, selecting the existing project's source movie and choosing Create Project visibly presented “Project Already Exists” with the requested continue-or-delete instruction, kept the sheet open, and left the library at one project. An initial check accidentally attached to a stale pre-build Release bundle and created one duplicate folder; that exact folder was moved to Trash as `VidiStudio-duplicate-validation-9b75eef2`, and the library was confirmed restored before the successful fresh-Release check. The YouTube path was verified by automated canonical-URL regression rather than by creating a disposable live YouTube project in the user's library.

Follow-up YouTube creation coverage now explicitly uses `https://youtu.be/4fYlQtcm6qY` and `https://www.youtube.com/watch?v=4fYlQtcm6qY`. Both inputs create the same canonical URL-backed project representation, fetch the YouTube title, and attempt to download the validated video's JPEG thumbnail into `thumbnails/youtube-thumbnail.jpg`; that relative file path is stored in `project.json` so the portable project grid uses the local image first. The download is restricted to YouTube's thumbnail host, JPEG content, a validated 11-character video ID, a ten-second request timeout, and a 5 MB response limit. A failed thumbnail request does not prevent offline project creation; the existing remote-image and film-icon fallbacks remain available.

Validation: all 33 Python tests passed, including exact shared-link/watch-link normalization, title/project creation, saved-thumbnail bytes, and cross-format duplicate rejection. `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` rebuilt and launched process 64665 with packaged Help checks passing. The packaged Release engine imported the full watch URL into an isolated temporary library, fetched the title “No Cost EMIs (Exposed),” stored the canonical URL, and saved a valid 480×360 JPEG. Importing the copied short link into that same temporary library then exited with the required existing-project error. Separate source-engine imports also succeeded for each URL format in independent temporary libraries. No project was added to or changed in the user's configured VidiStudio library.

### YouTube project preview before creation — 2026-09-10

The YouTube branch of New Project now requires an explicit Fetch Details step before Create Project becomes available. Fetch Details validates the link, rejects an existing project before making network requests, retrieves the YouTube title and a bounded JPEG thumbnail concurrently, and displays the thumbnail, proposed project name, and canonical watch URL directly below the URL field. Editing the URL clears the preview and disables Create Project until the new value is fetched. Creation passes the reviewed title to the engine, which independently stores the canonical URL and downloads the portable project thumbnail.

The preview has accessible names for its URL field, Fetch Details button, fetch progress, errors, thumbnail, project name, and confirmation text. Fetch failures remain inside the sheet with actionable link/network guidance. The dialog grows only for the YouTube flow; the local-video dialog retains its prior compact height. The offline Help Book now documents the fetch-and-review requirement.

Validation: the Swift changes compiled in Release and `VIDISTUDIO_CONFIGURATION=Release ./script/build_and_run.sh --verify` passed packaged Help verification and launched process 65071. In that exact Release app, the supplied full watch URL displayed Fetch Details, the real 480×360 thumbnail, project name “No Cost EMIs (Exposed),” canonical URL, and enabled Create Project. Replacing it with `https://youtu.be/4fYlQtcm6qY` immediately removed the preview and disabled Create Project; activating Fetch Details restored the same name, thumbnail, canonical URL, and enabled action. The sheet was cancelled afterward, leaving the configured library at its original one project.

### Local video 2 GB creation limit — 2026-09-10

The native macOS app now accepts local videos up to and including 2,000,000,000 bytes and rejects anything larger immediately after the file chooser returns, before the selection is retained in New Project or Create Project becomes available. The reusable native import entry point repeats the preflight so menu and stale-dialog paths cannot bypass it. Oversized-file and unreadable-file alerts have specific accessible titles and actionable instructions.

The packaged Python engine independently applies the same limit before probing, copying, or creating an imported project; the legacy local-copy attachment command validates before probing or copying; local-video analysis validates again before Gemini upload; and the shared Gemini upload adapter refuses any over-limit file before making a network request. These changes are only in VidiStudio Mac and its packaged engine; VidiStudio Online was not modified. The Projects Help topic documents the local limit and the YouTube alternative.

Validation: three focused regressions passed for the inclusive boundary, byte 2,000,000,001, import-before-project-creation ordering, and upload-before-network ordering. The complete 36-test source suite passed 35 tests; only the existing real system-speech pipeline failed because restricted macOS speech returned no audio. The Release app and updated packaged engine rebuilt successfully with all 13 Help pages, registration, anchors, links, stylesheet, and search index verified. The packaged Release engine rejected a sparse 2,000,000,001-byte movie with the intended 2 GB message and did not create the isolated library path. An initial live New Project check exposed that URL resource metadata was unsuitable for this sparse boundary fixture, so the native policy was corrected to use the filesystem `.size` attribute; an isolated Swift execution then reported the logical byte count correctly. A post-correction live dialog pass could not be completed because the Mac locked and automatic unlock was unavailable, so the final rendered alert remains unobserved even though the corrected Swift code compiled in Release and the identical packaged boundary was exercised.

### Ephemeral YouTube thumbnail preview — 2026-09-10

Fetch Details still retrieves the YouTube name and thumbnail needed for confirmation, but now uses an explicitly ephemeral URL session with no URL cache and a reload-ignoring-cache request policy. The preview image exists only in New Project view state and is discarded when the URL changes or the sheet closes. No thumbnail file is written locally before creation. The packaged engine remains the sole owner of durable thumbnail download: `import-youtube` creates the project folders, downloads the validated JPEG into `thumbnails/youtube-thumbnail.jpg`, and records that relative path in `project.json`. The Projects Help topic now makes this lifecycle explicit.

### All Projects table and generated-content indicators — 2026-09-10

List View on All Projects is now a native multi-column table rather than a combined text row. Its columns show project name, duration, AD segment count, transcript status, summary status, AD status, final-video export status/count, and narration-audio export status/count. Grid cards show the same five generated-content indicators beneath their existing duration and description count. The shared indicator model treats an existing empty transcript or AD artifact as generated, distinguishes an unavailable final-video export for URL-backed YouTube projects, and recognizes the app's MP4 and narration-audio export formats.

Every status icon has a generated, not-generated, or unavailable badge, pointer help, and a complete VoiceOver label. Table cells expose their column value directly; each grid card's combined accessibility label includes duration, transcript, summary, AD segment count, final-video exports, and narration-audio exports. Grid keeps the numeric AD count in the existing metadata line rather than repeating it in the compact icon strip. Double-click/primary action, selection, Rename-on-Return, contextual project actions, and the Grid-only project-size slider remain available. The Projects Help topic explains both layouts and the status badges.

Validation: `VIDISTUDIO_CONFIGURATION=Release OTHER_SWIFT_FLAGS=-disable-sandbox ./script/build_and_run.sh --build-only` compiled the final native app and passed packaged registration plus all 13 Help pages, anchors, links, stylesheet, and search-index checks. Live Computer Use inspection of that exact Release bundle exposed the native table with all eight requested headers and a row whose VoiceOver description included the generated transcript, generated summary, 18 AD segments, and both not-generated export states. Grid View visibly showed the five evenly spaced artifact icons without wrapping, while its accessible project-card description included the same status details. A table-row double-click opened the existing project editor successfully; Back to All Projects returned to the table. The original List View preference was restored after testing, and no project data was changed.
