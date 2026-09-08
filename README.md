# VidiStudio for macOS

A native SwiftUI and AVKit video accessibility editor with a portable Python command-line engine. Requires macOS 26 or later. The app uses local project folders; there is no Firebase, Firestore, sign-in, or cloud storage dependency. The editor is native; a WebKit view embeds only the YouTube player for YouTube projects.

## Build and run

```sh
./script/build_and_run.sh --verify
```

This builds the existing `VidiStudio.xcodeproj` app target, freezes the Python engine and Google GenAI SDK with PyInstaller, bundles FFmpeg/FFprobe and their non-system libraries, signs the bundle for local use, and opens it. Xcode is selected per command using `DEVELOPER_DIR`, without changing global developer settings. Python build dependencies live in `.venv`.

Other flags: `--build-only`, `--debug`, `--logs`, `--telemetry`. `script/package.sh` makes Release local-install ZIP and DMG packages in `dist`. Local signatures are not Developer ID notarization; public distribution requires signing and notarizing all nested code with the owner's distribution credentials.

## Workflow

1. New Project (Command-N) lets you choose a video file or YouTube video. Video files are copied into the project library and receive metadata and eight thumbnails.
2. In Settings (Command-comma), save your Gemini API key and model names. System narration works without a key.
3. Import a local video or use the toolbar link button for a YouTube project. Run All Analysis transcribes, summarizes, then generates descriptions; each stage is also available separately.
4. Review cues, seek from their timestamps or timeline, and add/edit/delete cues. Save rejects overlaps with dialogue and other descriptions.
5. Synthesize narration. Text that exceeds its time slot must be shortened or retimed.
6. Export Final Video mixes the original audio with narration into a new local MP4. Changed or missing narration blocks export.

Gemini analysis sends a processing copy through the Files API, polls for ACTIVE with a deadline, saves results locally, and deletes the temporary remote file in a finally block. API keys never enter project folders or process command lines. Settings are saved to `~/Library/Application Support/VidiStudio/config.json` with owner-only permissions. This is a local plaintext config, not an encrypted credential vault.

## Project format

Each portable folder contains `project.json` and `source/`, `metadata/`, `thumbnails/`, `transcript/`, `audio-description/`, `exports/`. Paths inside project data are relative and confined to the project folder. Saves replace JSON atomically. OS-level locks prevent concurrent engine writes and release on process exit. Stages preserve completed outputs on failure. Regenerating a transcript invalidates dependent summary/cues/export references; old files are retained on disk.

Open Project Folder (Command-O) opens a project in another location without copying it. New projects default to `~/Documents/VidiStudio Projects`; choose another folder from Settings → Storage → Browse.

## Portable engine

```sh
python3 -m venv .venv
.venv/bin/pip install -r engine/requirements.txt
.venv/bin/python engine/vidistudio_engine.py import-video --video /path/video.mp4 --library /path/projects
.venv/bin/python engine/vidistudio_engine.py transcribe --project /path/project
```

Additional commands: `import-youtube`, `validate-config`, `analyze`, `capture-frame`, `rewrite-cue`, `export-subtitles`, `export-audio`, `rename-project`, `undo-cues`, `redo-cues`, `update-metadata`, `attach-video`, and `delete-export`. Use `--help` for arguments.

Core commands: `doctor`, `import-video`, `probe-video`, `generate-thumbnails`, `extract-audio`, `transcribe`, `generate-summary`, `generate-ad-cues`, `save-cues`, `synthesize-tts`, `export-final-video`. Progress and errors are JSON lines on stdout; failure exit code is 1. Set `VIDISTUDIO_CONFIG` to choose an alternate settings file.

Windows uses Python 3.11+ and FFmpeg/FFprobe on PATH (or configured paths), `%APPDATA%/VidiStudio/config.json`, and PowerShell System.Speech for offline voices. Build Windows executables with PyInstaller on Windows; macOS binaries cannot run there. The macOS UI is deliberately separate from the portable engine.

## Validation

```sh
.venv/bin/python -m unittest discover -s tests -v
```

Tests cover path confinement, malformed/overlapping/dialogue-conflicting cues, and an actual generated video import → thumbnails → extraction → system speech → MP4 export pipeline, plus stale narration and missing-key errors. System speech requires access to the OS speech service; restricted execution environments may produce an empty file.

## Runtime and distribution

This direct-distribution app intentionally runs outside App Sandbox to launch its bundled processing tools and access local project folders. Hardened runtime remains enabled for distribution builds. FFmpeg's bundled Homebrew build includes GPL components; redistribution must comply with the included licenses and corresponding-source obligations. No public release is performed by the build scripts.

API references: https://ai.google.dev/api/files and https://ai.google.dev/gemini-api/docs/generate-content/speech-generation . Website interaction reference: https://accessivideo.pages.dev/ .

Engine operations retain pre-operation project snapshots in `metadata/history/` for manual recovery. Windows engine packaging is provided by `script/build_engine_windows.ps1` and must run on Windows. It does not download or silently install media binaries.

Settings exposes model IDs for every stage, API version, processing mode, prompt pairs, voices, and light/dark/system appearance. Initial values come from `engine/ai-defaults.json`; saved user choices override them. Dedicated speech transcription uses extracted audio; YouTube uses its own configurable video-understanding model.

Current delivery evidence and known feature/validation limits are recorded in `PROGRESS.md` and `FEATURE_PARITY.md`.

## Keyboard shortcuts and Help

Open **Help → VidiStudio Help** (Command+Option+/), or **Settings → Help and keyboard shortcuts** for the complete reference. Native Playback and Project Editor menus show available commands and their key equivalents. New Project: Command+N; open folder: Command+O; Settings: Command+Comma; play/pause: Command+Shift+Space; seek five seconds: Command+Option+Left/Right; descriptions/transcript/summary: Command+1/2/3; add segment: Command+Shift+N; follow: Command+Shift+F; narration: Command+Shift+D; segment undo/redo: Command+Option+Z / Command+Option+Shift+Z. Save Settings with Command+S and Save Segment with Return in their respective views. Escape cancels a sheet or closes Help.

Editor commands disable during processing and editing sheets. Standard text undo and VoiceOver Control+Option commands are preserved. Enable macOS Keyboard navigation to Tab through all controls. Windows web shortcuts are documented in the online application; a Windows desktop UI is not yet shipped.

## AD views and narration settings

Use the Editor section menu for Descriptions, Transcript, Summary, AD Transcript (Command+4), and AD Overview (Command+5). The AD transcript lists timed description text; AD Overview reports segment counts, ready/stale/missing audio, and description time, with actions to generate all or missing/changed narration.

Settings now has a native sidebar: Appearance, Narration, Gemini API, Developer prompts, Storage, Help. Narration offers Apple on-device voices or Gemini TTS for saved audio generation. Its language/region filter and search list all voices exposed by macOS speech, including installed enhanced voices; each has a Speak Sample action. Download more voices through macOS Accessibility → Read & Speak, then Refresh Voices. Save Settings preserves the chosen voice and engine.

For playback, choose generated audio or on-device speech without audio files, then enable Narration in the editor. On-device speech restarts the active cue after seeking/resuming and stops at its end; use generated audio for precise timing and final exports. No additional local LLM is required. Gemini premium generation still requires a configured personal API key.

### Voice samples in Settings

Settings → Narration shows samples for the selected speech engine. Apple voices offer Play Selected Voice (including the system default), individual Speak Sample buttons, and Stop Sample. Gemini offers the online voice list plus a custom voice ID, editable sample text, Play Voice Sample, Stop Sample, and Cancel Generation. Gemini previews use current unsaved settings through an owner-only temporary config; they do not change projects or save settings. Samples are cached within the Settings session and removed when leaving the Gemini section. Changing voice or sample stops playback. A Gemini API key is required; requests use the configured TTS model and prompt.

### Preview workspace

Use Show/Hide Preview in the editor or Command+Shift+V to collapse the video and timeline while keeping the player loaded. Full-Screen Video (Command+Option+F) presents the video separately from the editor; Escape restores it. Both controls are also in the Playback menu and keyboard reference.

### Fixed project list and inspector

The project list (252 points) and inspector (272 points) have fixed widths and no resize handles. Their toolbar buttons show or hide them independently; the center editor takes the remaining width. Long project names wrap. Right-click a project for Open in Project Folder, Rename, and Delete; Delete moves the folder to macOS Trash. The center preview/editor divider remains adjustable.
