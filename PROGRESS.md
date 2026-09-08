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

Processing now replaces the lower editor content with a large, continuously spinning native activity indicator so it remains visible beside the inspector and within the transcript area. Removed the small footer spinner and determinate progress bar; the footer retains the current status text and Cancel Processing action. VoiceOver exposes the large indicator as Processing and reads the current operation as its value. The Debug Xcode build passed.

### Formatted summary — 2026-09-08

Summary now uses Foundation Markdown parsing and native SwiftUI block rendering for headings, bullets, numbered lists, inline emphasis, links, and paragraph spacing. Headings expose the VoiceOver header trait and text remains selectable. Stored Markdown remains unchanged. `script/build_and_run.sh --verify` passed and launched the updated Debug app; visual and VoiceOver interaction were not separately verified in this pass.

### Project processing and reset menu — 2026-09-08

List and grid context menus now offer Process Video for fresh projects or Reprocess Video for projects with analysis attempts or results. Both run the sequential analysis pipeline. Delete Generated Content requires a native confirmation and clears metadata, thumbnails, transcripts, summaries, descriptions, narration, exports, and undo/redo history while preserving project identity and source media. Delete Project is a separate action. Reset rejects generated folders that are symlinks or contain the source. The focused preservation test and packaged engine reset smoke test passed; the bundled Debug app built and launched through the verify script.

### Settings and menu iconography — 2026-09-08

Added native symbol labels to settings navigation and appearance/narration choices, app-owned File/View/Playback/Project Editor/Help commands, list and grid context actions, segment actions, and export menus. Rename, clear generated content, and delete project now have distinct symbols. Existing text, shortcuts, enabled states, and destructive roles remain intact. The Debug build and launch verification passed; menu visuals were not independently inspected in this pass.
