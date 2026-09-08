# Build and validation — 8 September 2026

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
