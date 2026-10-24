# VidiStudio desktop feature map

Reference: the authenticated accessivideo.pages.dev application and its React/Python source, reviewed 8 September 2026.

| Workflow | Desktop implementation |
| --- | --- |
| Dashboard, project search, rename, delete | Native sidebar, search, context menu; deletion uses macOS Trash |
| Local video import | Copies source into a local project; FFprobe metadata and eight thumbnails |
| YouTube project | Canonical URL validation, oEmbed title, embedded YouTube playback; generated results stay local |
| Project overview and advanced editor | Native split editor with summary, transcript, descriptions, timeline, inspector |
| Staged transcript, summary, descriptions | Individual commands and sequential Analyze Video workflow |
| Retry processing | Individual stage commands, bounded retries, atomic project saves, and existing completed output retained on request failure |
| Dedicated speech model | Extracted mono WAV chunks, word timestamps, speaker grouping |
| YouTube analysis | Separate configured video-understanding model; no audio-only request sent a YouTube URI |
| Transcript synchronization | Active-row highlighting, seek from timestamp, follow toggle |
| AD transcript and overview | Timed AD text, segment/audio counts, narration generation; Command+4/5 |
| Description editing | Add, edit, delete, rewrite to fit, undo and redo |
| Screen-text OCR | Current timestamp for YouTube, captured image for local source; review and add as cue |
| Narration | Offline system voices, optional Gemini TTS, optional Azure Voices (key fields shown only when selected; Windows also lists natural voices from the voice bridge add-on under SAPI 5); one cue, all, or changed cues; optional live on-device playback without files |
| Narration preview | Individual audio preview and synchronized description playback |
| Exports | SRT, VTT, text, JSON; Video Format picker: MKV (default), MP4, MOV, M4V; Audio Format picker: WAV (default), MP3, M4A for original, narration-only, and described audio |
| YouTube audio exports | Original YouTube audio, narration-only audio, then combined YouTube audio/narration, each with WAV (default), MP3, and M4A; bundled yt-dlp/Deno retrieval and temporary cleanup; complete mix for manual YouTube Studio upload |
| YouTube video export | Not available for URL-backed projects; narration and text exports remain available |
| Appearance | Light, dark, system; standard macOS controls and typography; bundled Material Symbols |
| Settings | Two-column native sidebar; searchable language/region voice browser with samples and refresh; personal key, per-stage model IDs, API version, processing mode, prompt pairs, voice and tool paths |
| Accessibility | Named native controls, keyboard access, standard menus, reduced-motion-aware transcript scrolling |
| Storage/auth | Local JSON and files; no desktop Firebase, Firestore, R2, account or sign-in dependency |

## Verification limits

Local media import, metadata, thumbnails, system speech, open and closed Audio Description rendering, URL validation, captions, and edit history have automated coverage. Native editor and settings have been inspected through the macOS accessibility tree. Live Gemini processing requires a configured personal key in desktop Settings. Windows uses the same engine and a packaging script, but Windows runtime validation and a Windows native UI are not completed on this Mac. Public macOS distribution still requires Developer ID signing and notarization.
