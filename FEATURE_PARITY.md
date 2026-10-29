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
| Narration | Offline Apple system voices, bundled Piper Voices on both desktops, and optional Gemini TTS; one cue, all, or changed cues; optional live on-device playback without files. Windows adds Windows OneCore and SAPI 5. Piper voices are downloaded on demand. Azure Voices and the natural-voice bridge were removed; legacy engine settings migrate to Apple Voices on Mac and Windows OneCore/SAPI 5 on Windows. |
| Narration preview | Individual audio preview and synchronized description playback |
| Narration sources | AD Overview reports generated, imported, and unknown counts and the number of imported files; it warns on mixed AI/imported sources and multiple imported files, labels imported segments with their source file, and shows legacy files without metadata as Unknown voice |
| Existing-asset project import | New Project's existing-assets mode, or Project > Import Existing Assets… / editor import button. Transcript and AD transcript accept SRT, VTT, TXT; summary accepts Markdown or TXT; AD audio accepts WAV, MP3, M4A, AAC, FLAC. AD transcript is narration-only (editable, transcript-validated) or dialogue+AD combined (one caption/export track). AD audio is narration-only (ducked under original) or full AD mix. Create Project & Open Editor and Create Project & Combine; replacements require confirmation; YouTube projects accept text assets only |
| TXT timing editor | Per-line manual times, Distribute Evenly, and optional Gemini timing that is only a proposal; every row reviewed and validated before import |
| Import validation and timing audit | Valid rows imported; out-of-duration and invalid rows omitted with reasons; earlier-transcript overlaps omitted; AD overlaps flagged as needing retiming; zero valid rows preserve existing content; persistent timing banner, per-row Overlap badge, AD Overview count, and described-export blocking |
| Two-track audio | Closed Audio Description provides Original Audio (default) plus English - Audio Description with the visual-impaired flag; open description is an explicit single mix; no silent original track when the source has no audio |
| Summary authoring | Generate, import, or write manually; Markdown toolbar, live preview, Markdown Help, and editor-local shortcuts. Supported Markdown covers headings, lists, task lists, quotes, code, links, tables, and rules; images render as alt text and a link, and math, Mermaid, footnotes, and embedded remote images are excluded. Project List/Grid shortcuts are disabled while the editor is active. Summary provenance is limited to AI-generated, Imported, and Manually added |
| Provenance | Six description labels (AI-generated, AI-generated · modified, Imported, Imported · modified, Manually added, Origin unknown) with manual pickers; summary picker uses the three allowed labels and keeps unknown as the default |
| Per-segment narration import | WAV, MP3, M4A, AAC, or FLAC; audio that fits or is shorter is accepted, longer audio is rejected with both durations and the segment range; replacement confirmation; no API key |
| Generation prerequisites | Transcript for summary generation; transcript and summary for generated descriptions; transcript for manual description authoring; descriptions for narration synthesis; local video and AD audio for combining |
| Project creation | No Gemini API key required for local or YouTube projects; the YouTube Gemini access check runs only when a key is configured |
| AI availability | Quota, credit/billing, permission, and service failures set a persistent AI issue, disable all AI reprocessing across the app, and show Retry AI plus Gemini Settings; existing work and non-AI actions remain available |
| Exports | SRT, VTT, text, JSON; Video Format picker: MKV (default), MP4, MOV, M4V; Audio Format picker: WAV (default), MP3, M4A for original, narration-only, and described audio |
| YouTube audio exports | Original YouTube audio, narration-only audio, then combined YouTube audio/narration, each with WAV (default), MP3, and M4A; bundled yt-dlp/Deno retrieval and temporary cleanup; complete mix for manual YouTube Studio upload |
| YouTube video export | Not available for URL-backed projects; narration and text exports remain available |
| Appearance | Light, dark, system; standard macOS controls and typography; bundled Material Symbols |
| Settings | Two-column native sidebar; searchable language/region voice browser with samples and refresh; personal key, per-stage model IDs, API version, processing mode, prompt pairs, voice and tool paths |
| Accessibility | Named native controls, keyboard access, standard menus, reduced-motion-aware transcript scrolling |
| Storage/auth | Local JSON and files; no desktop Firebase, Firestore, R2, account or sign-in dependency |

## Verification limits

Local media import, metadata, thumbnails, system speech, open and closed Audio Description rendering, URL validation, captions, edit history, existing-asset import validation, TXT timing review, provenance persistence, and the description timing audit have automated coverage. Markdown summary transformations are implemented in native Swift and covered by the native transformer harness. Native editor and settings have been inspected through the macOS accessibility tree. Live Gemini processing requires a configured personal key in desktop Settings. Windows mirrors the shared engine and native feature set, but native Windows build, packaging, and runtime validation require a Windows host and are not claimed from macOS; the Windows checkout's `PROGRESS.md` records its own evidence. Public macOS distribution still requires Developer ID signing and notarization.
