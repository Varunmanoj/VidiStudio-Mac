# VidiStudio for macOS

A native SwiftUI and AVKit video accessibility editor with a portable Python command-line engine. Requires macOS 26 or later. The app uses local project folders; there is no Firebase, Firestore, sign-in, or cloud storage dependency. The editor is native; a WebKit view embeds only the YouTube player for YouTube projects.

## Build and run

```sh
./script/build_and_run.sh --verify
```

This builds the existing `VidiStudio.xcodeproj` app target, freezes the Python engine and Google GenAI SDK with PyInstaller, bundles FFmpeg/FFprobe and their non-system libraries, signs the bundle for local use, and opens it. Xcode is selected per command using `DEVELOPER_DIR`, without changing global developer settings. Python build dependencies live in `.venv`.

Other flags: `--build-only`, `--debug`, `--logs`, `--telemetry`. `script/package.sh` makes Release local-install ZIP and DMG packages in `dist`. Local signatures are not Developer ID notarization; public distribution requires signing and notarizing all nested code with the owner's distribution credentials.

## Workflow

1. New Project (Command-N) lets you choose a video file or YouTube video. Video files are copied into the project library and receive video details and eight timeline pictures. YouTube videos must be publicly available with visibility set to Public; Private, Unlisted, and every other YouTube visibility setting are rejected because Gemini cannot use them for video understanding. Before creating the project folder, VidiStudio uses the configured Gemini connection to confirm that the URL is usable. The bundled macOS Share extension applies the same validation when it accepts one movie from Finder or a public YouTube video page from Safari and compatible browsers, then creates the project and opens its editor automatically. Enable VidiStudio under System Settings → General → Login Items & Extensions → Sharing if it is not already visible in Share menus.
2. In Settings (Command-comma), save your Gemini API key and model names. System narration works without a key.
3. Choose Analyze Video for the complete AI workflow: transcript, summary, then Audio Description text. To work one stage at a time, choose Generate Transcript, Generate Summary, and Generate Audio Descriptions; once content exists, those labels become Regenerate. Regenerate Video Details & Timeline Pictures refreshes only non-AI preparation. Project Information and Video Information remain at the top of the inspector on every editor section. Project Information shows the complete folder size and location; Video Information reports the local source file or YouTube source and its available quality details. The generation controls below stay specific to the selected section. Project > Analysis and each project's contextual Analysis menu contain the complete and individual workflows.
4. Review transcript and Audio Description segments in view mode, then choose Edit to expose selection checkboxes and pencil controls. While Transcript edit mode is active, choose Add Segment or press Command-Shift-N to insert a new transcript segment at the current video time. Descriptions retains the same Add Segment action for a new Audio Description. Edit one row or select several rows and choose Edit Selected to correct their text and timing together. Project &gt; Segments in the menu bar mirrors Edit/Done, Add Segment, Select All, Deselect All, Edit Selected, Delete Selected, Follow, Undo, and Redo with section-aware availability. Select All, Deselect All, and Delete Selected work in Transcript, Descriptions, and the combined AD Transcript. Deleting selected descriptions also permanently removes their corresponding narration files. The timeline shows labeled Thumbnails, Transcript, and Audio Description tracks with a synchronized playhead and millisecond-precision current/total time. Click or drag the thumbnail strip to seek. Save rejects empty text, invalid ranges, and overlaps between transcript and description segments.
   Transcript, Summary, and Descriptions each expose a right-aligned Generate action, or an explicit Regenerate action when that result already exists. Regenerating Audio Descriptions also removes narration audio associated with the old description segments before generating the new descriptions.
   Read Frame Text pauses on the selected playhead position, shows its AI processing status, and uses the final valid frame when the playhead is at the exact end of the video.
5. Synthesize narration. Text that exceeds its time slot must be shortened or retimed.
6. Open the Export dialog from the inspector, a project's right-click menu, File → Export, or Command-Shift-E while its editor is active. When you add audio or closed captions, VidiStudio keeps the original picture unchanged, including 4K and HDR quality. Open captions become part of the picture, so VidiStudio warns that some original quality or iPhone Dolby Vision information may change and recommends closed captions. In Created Exports, each file has one eye-in-a-circle button that opens its Export Information dialog with Open File, Open Folder, and Delete File actions. Audio exports include original video audio, the final described mix, and narration-only audio. Changed or missing narration blocks described export.

User-facing errors and warnings use plain language, explain what remains safe, and give a next step. Internal engine, media-tool, operating-system, and service details are written only to private diagnostic logs and are never placed in alerts or inline error messages.

Gemini analysis sends a processing copy through the Files API, polls for ACTIVE with a deadline, saves results locally, and deletes the temporary remote file in a finally block. API keys never enter project folders or process command lines. Settings are saved to `~/Library/Application Support/VidiStudio/config.json` with owner-only permissions. This is a local plaintext config, not an encrypted credential vault.

## Project format

Each portable folder uses `project.json` as the single source of truth for metadata, transcript text, summary, Audio Description segments, undo/redo states, and referenced paths. Local projects keep the imported video in `source/`; `metadata/probe.json` supplies technical video information; `thumbnails/` holds only images referenced by the project; `audio-description/` holds only current synthesized narration; and `exports/` holds only current listed exports. Empty generated folders are removed and recreated when needed. YouTube projects do not create a local `source/` folder. Paths are relative and confined to the project folder, and saves replace JSON atomically. OS-level locks prevent concurrent engine writes and release on process exit.

Processing audio chunks, speech input, captured OCR frames, duplicate transcript/summary/cue JSON files, unreferenced narration or exports, operation snapshots, and internal export trash are automatically removed. `cleanup-project --project /path/project` migrates and cleans an older project folder while preserving its source or YouTube link and all currently referenced content.

Open Project Folder (Command-Shift-O) opens a project in another location without copying it. New projects default to `~/Documents/VidiStudio Projects`; choose another folder from Settings → Storage → Browse.

## Portable engine

```sh
python3 -m venv .venv
.venv/bin/pip install -r engine/requirements.txt
.venv/bin/python engine/vidistudio_engine.py import-video --video /path/video.mp4 --library /path/projects
.venv/bin/python engine/vidistudio_engine.py transcribe --project /path/project
```

Additional commands: `import-youtube`, `prepare-video`, `validate-config`, `analyze`, `cleanup-project`, `capture-frame`, `rewrite-cue`, `export-subtitles`, `export-audio`, `rename-project`, `undo-cues`, `redo-cues`, `update-metadata`, `attach-video`, and `delete-export`. Use `--help` for arguments.

Core commands: `doctor`, `import-video`, `probe-video`, `generate-thumbnails`, `transcribe`, `generate-summary`, `generate-ad-cues`, `save-cues`, `save-segments`, `synthesize-tts`, `export-open-audio-description-video`, `export-closed-audio-description-video`, `export-closed-caption-video`, `export-open-caption-video`, `export-original-audio`, and `export-described-audio`. `save-segments` atomically validates and replaces the editable transcript and Audio Description rows. Described-video commands accept `--captions none|closed|open` with `--content transcript|combined`. The older `export-final-video` and `export-selectable-video` names remain accepted for command-line compatibility. Progress and errors are JSON lines on stdout; failure exit code is 1. Set `VIDISTUDIO_CONFIG` to choose an alternate settings file.

Windows uses Python 3.11+ and FFmpeg/FFprobe on PATH (or configured paths), `%APPDATA%/VidiStudio/config.json`, and PowerShell System.Speech for offline voices. Build Windows executables with PyInstaller on Windows; macOS binaries cannot run there. The macOS UI is deliberately separate from the portable engine.

## Validation

```sh
.venv/bin/python -m unittest discover -s tests -v
```

Tests cover path confinement, malformed/overlapping/dialogue-conflicting cues, and an actual generated video import → thumbnails → extraction → system speech → MP4 export pipeline, plus stale narration and missing-key errors. System speech requires access to the OS speech service; restricted execution environments may produce an empty file.

## Runtime and distribution

This direct-distribution app intentionally runs outside App Sandbox to launch its bundled processing tools and access local project folders. Hardened runtime remains enabled for distribution builds. FFmpeg's bundled Homebrew build includes GPL components; redistribution must comply with the included licenses and corresponding-source obligations. No public release is performed by the build scripts.

API references: https://ai.google.dev/api/files and https://ai.google.dev/gemini-api/docs/generate-content/speech-generation . Website interaction reference: https://accessivideo.pages.dev/ .

AD segment undo and redo states are bounded and stored in `project.json`; the app no longer creates a second, unbounded folder of whole-project snapshots. Windows engine packaging is provided by `script/build_engine_windows.ps1` and must run on Windows. It does not download or silently install media binaries.

Settings exposes model IDs for every stage, API version, processing mode, prompt pairs, voices, and light/dark/system appearance. Initial values come from `engine/ai-defaults.json`; saved user choices override them without removing newly added default stages or fields. Dedicated speech transcription uses extracted audio with automatic multilingual detection and code-switching; YouTube uses its own configurable video-understanding model. The shared Multilingual Media prompt augments transcript, summary, Audio Description, and screen-text understanding for local and YouTube sources without replacing their existing task prompts.

Current delivery evidence and known feature/validation limits are recorded in `PROGRESS.md` and `FEATURE_PARITY.md`.

## Keyboard shortcuts and Help

Open **Help → VidiStudio Help** (Command+Option+/), or **Settings → Help and keyboard shortcuts** for the complete reference. **File → Export** mirrors the inspector and project right-click Export action; use Command+Shift+E while a project editor is active. View contains the preview, complete timeline, project-list, inspector, and list/grid presentation controls. Project → Analysis contains Analyze Video plus every individual processing stage; the inspector remains page-specific. Analyze Video is Command+Option+Shift+A, with Command+Option+Shift+T/S/D for Transcript, Summary, and Audio Descriptions. New Project: Command+N; open project folder: Command+Shift+O; Settings: Command+Comma; show/hide preview: Command+Shift+V; play/pause video: Command+Shift+Space; seek five seconds: Command+Option+Left/Right; transcript/summary/descriptions/AD overview/AD transcript: Command+1/2/3/4/5. Segment commands use Command+Option+E for Edit/Done, Command+Shift+N to add, Command+Option+A to select all, Command+Option+Shift+A to deselect all, Command+Option+Return to edit selected, and Command+Control+Delete to delete selected. Follow is Command+Shift+F; narration is Command+Shift+D; segment undo/redo is Command+Option+Z / Command+Option+Shift+Z. On Summary, Play or Resume is Command+Shift+P, Pause is Command+Option+P, and Stop is Command+Shift+S.

Editor commands disable during processing and editing sheets. Standard text undo and VoiceOver Control+Option commands are preserved. Enable macOS Keyboard navigation to Tab through all controls. Windows web shortcuts are documented in the online application; a Windows desktop UI is not yet shipped.

## AD views and narration settings

The Editor section opens to Transcript by default and is ordered Transcript (Command+1), Summary (Command+2), Descriptions (Command+3), AD Overview (Command+4), and AD Transcript (Command+5). Descriptions lists authored AD segments; AD Overview reports segment counts, ready/stale/missing audio, and description time, with actions to generate all or missing/changed narration; AD Transcript combines dialogue and AD segments chronologically.

Settings now has a native sidebar: Appearance, Narration, Gemini API, Developer prompts, Storage, Help. Narration offers Apple on-device voices or Gemini TTS for saved audio generation. Its language/region filter and search list all voices exposed by macOS speech, including installed enhanced voices; each has a Speak Sample action. Download more voices through macOS Accessibility → Read & Speak, then Refresh Voices. Save Settings preserves the chosen voice and engine.

For playback, choose generated audio or on-device speech without audio files, then enable Narration in the editor. On-device speech restarts the active cue after seeking/resuming and stops at its end; use generated audio for precise timing and final exports. No additional local LLM is required. Gemini premium generation still requires a configured personal API key.

### Voice samples in Settings

Settings → Narration shows samples for the selected speech engine. Apple voices offer Play Selected Voice (including the system default), individual Speak Sample buttons, and Stop Sample. Gemini offers the online voice list plus a custom voice ID, editable sample text, Play Voice Sample, Stop Sample, and Cancel Generation. Gemini previews use current unsaved settings through an owner-only temporary config; they do not change projects or save settings. Samples are cached within the Settings session and removed when leaving the Gemini section. Changing voice or sample stops playback. A Gemini API key is required; requests use the configured TTS model and prompt.

### Preview workspace

Use **View → Hide Preview** or Command+Shift+V to collapse the video and timeline while keeping the player loaded. The same command changes to **Show Preview**, so the preview can always be restored from the View menu or keyboard. **View → Hide Timeline** collapses the complete timeline section, including thumbnails, seeking, Transcript segments, and Audio Description segments, and changes to **Show Timeline** for restoration. The preference persists across project windows and launches. Project editor opening, preview, timeline, inspector, Settings and Export presentation, and Settings disclosure changes use short native-feeling transitions; macOS Reduce Motion disables this added movement. Close an editor with its standard red window Close button; All Projects remains available in its own window. Full-Screen Video (Command+Option+F) presents the video separately from the editor; Escape restores it. Full-Screen Video remains in **Project → Playback** and both shortcuts are included in the keyboard reference.

### Fixed project list and inspector

The project list (252 points) and inspector (272 points) have fixed widths and no resize handles. Their toolbar buttons show or hide them independently; the center editor takes the remaining width. Long project names wrap. Right-click a project in List or Grid View for an Analysis menu containing non-AI metadata/thumbnail preparation, Analyze Video, and each individual AI stage. The contextual menu also includes project-specific Export, Open in Project Folder, Rename, and Delete. Local projects expose Video, Audio, and Text export submenus; YouTube projects omit Video while retaining available Audio and Text exports. The labeled timeline beneath the preview displays optional thumbnail frames followed by spoken Transcript segments and Audio Description segments.

Targeted Audio Description refinement is available in the Add/Edit segment dialog beside Read Frame Text. Re-Analyze This Segment uses the selected video range and project context, reconciles nearby descriptions, validates timing, and supports Undo. The inspector shows Gemini-checked video availability and a human-readable retention countdown with consistent numeric values for days, hours, minutes, and seconds; the full window is 2 days, and valid uploads are reused.
