# VidiStudio desktop feature map

Reference: the authenticated accessivideo.pages.dev application and its React/Python source, reviewed 8 September 2026.

| Workflow | Desktop implementation |
| --- | --- |
| Dashboard, project search, rename, delete | Native sidebar, search, context menu; deletion uses macOS Trash |
| Local video import | Copies source into a local project; FFprobe metadata and eight thumbnails |
| YouTube project | Canonical URL validation, oEmbed title, embedded YouTube playback; generated results stay local |
| Project overview and advanced editor | Native split editor with summary, transcript, descriptions, timeline, inspector |
| Staged transcript, summary, descriptions | Individual commands and sequential Run All Analysis |
| Retry processing | Individual stage commands, saved JSON history, existing completed output retained on request failure |
| Dedicated speech model | Extracted mono WAV chunks, word timestamps, speaker grouping |
| YouTube analysis | Separate configured video-understanding model; no audio-only request sent a YouTube URI |
| Transcript synchronization | Active-row highlighting, seek from timestamp, follow toggle |
| Description editing | Add, edit, delete, rewrite to fit, undo and redo |
| Screen-text OCR | Current timestamp for YouTube, captured image for local source; review and add as cue |
| Narration | Offline system voices, optional Gemini TTS; one cue, all, or changed cues |
| Narration preview | Individual audio preview and synchronized description playback |
| Exports | SRT, VTT, text, JSON; narration M4A; final MP4 with original audio |
| YouTube final video | Attach a matching local copy before muxing; narration/subtitles do not require a copy |
| Appearance | Light, dark, system; standard macOS controls and typography; bundled Material Symbols |
| Settings | Personal key, per-stage model IDs, API version, processing mode, prompt pairs, voice and tool paths |
| Accessibility | Named native controls, keyboard access, standard menus, reduced-motion-aware transcript scrolling |
| Storage/auth | Local JSON and files; no desktop Firebase, Firestore, R2, account or sign-in dependency |

## Verification limits

Local media import, metadata, thumbnails, system speech, final video rendering, URL validation, subtitles, and edit history have automated coverage. Native editor and settings have been inspected through the macOS accessibility tree. Live Gemini processing requires a configured personal key in desktop Settings. Windows uses the same engine and a packaging script, but Windows runtime validation and a Windows native UI are not completed on this Mac. Public macOS distribution still requires Developer ID signing and notarization.
