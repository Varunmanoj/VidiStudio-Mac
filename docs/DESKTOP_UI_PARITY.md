# Desktop UI layout parity

Both desktop Help windows load the published /docs page on every open. The website controls its navigation, content, images and styling. A native header provides loading progress and Open in Browser. An unavailable connection displays “Documentation requires internet.” Retry appears immediately before Open in Browser after a page-load error. Starting a retry clears the error and restores the loading spinner.

Mac is the reference for shared organization and workflows. Use native SwiftUI/AppKit and WinUI controls; visual parity does not mean replacing native window chrome or copying OS-specific pixels.

| Paired surface | Shared layout contract | Source owners |
| --- | --- | --- |
| Settings pages | Compact named groups, common section order, aligned labels/fields, adjacent related actions, concise copy | Mac SettingsView and feature views; Windows SettingsDialog partials |
| Gemini, Sarvam and ElevenLabs credentials | Masked key, inline accessible status before trash; check/dashboard actions together below when they fit | GeminiAPISettingsView / SarvamVoiceSettingsView; SettingsDialog.Gemini / Sarvam / SpeechLayout |
| New Project | Source, source details, AD choices/assets and project location in compact groups | Mac project creation views; Windows NewProjectDialog |
| Import and timing | Group language/text/audio; choose/remove next to filenames; retain timing tables and errors | ImportAssetsView; ImportAssetsDialog / TextTimingDialog |
| Export | Category sidebar, grouped format/content/audio/caption choices, aligned saved-result selectors and native actions | ExportOptionsMenu; ExportDialog / ExportDialog.Tracks |
| Voice management | Group search/filter/sort controls; samples/download/removal with the correct voice; scrolling result list | PiperVoiceCatalog; PiperVoicesDialog / PiperDeleteVoicesDialog |
| Language/results, filters, reviews and small prompts | Inline ordinary fields, grouped form content, related actions together; full-width multiline editors and previews | LanguageResults and segment views; WindowedDialog / CompactDialogLayout and dialog builders |
| Confirmation and validation | Preserve essential counts/errors/consequences, availability, confirmations and native Primary/Secondary/Cancel results | Both native dialog implementations |

Windows companion forms pass through CompactDialogLayout. It preserves control instances, values, Header metadata, event handlers, names and native dialog commands while changing presentation. Dynamic builders must prepare new content as well; Export, language results and segment ranges do this explicitly. Field rows reflow below 360 logical pixels; Settings rows use 480. Related actions measure their content and share a row whenever they fit. Multiline editors, timing tables and previews deliberately retain a full-width presentation. Do not force all text into two narrow columns.

Windows New Project retains Choose Project Location…; Mac uses the configured default folder for new projects.

Genuine exceptions: OS window chrome/file pickers; Command versus Ctrl/Alt; Apple voices versus Windows OneCore/SAPI; platform media-tool locations and actual dependency licenses. My YouTube Videos has a dedicated toolbar/list layout, separately covered by native browser/account checks. These exceptions do not justify unrelated stacking, loose spacing or light fills in dark mode.

## Automated checks

Run in **each** desktop checkout with the combined workspace present:

```
python3 script/check_desktop_ui_parity.py
python3 -m unittest tests.test_desktop_ui_parity
python3 script/check_menu_parity.py
python3 -m unittest tests.test_menu_parity
```

The mirrored UI checker runs before desktop builds and commits. Mutation tests reject dropping Mac grouped forms or horizontal key/timing actions, bypassing Windows shared forms, inheriting narrow native style width caps, fixed-light card fills, missing responsive layout/accessible groups and removal of native geometry/value checks. Keep the checker/tests mirrored. A standalone checkout reports an explicit skip rather than breaking its build; a skip is not paired validation. They guard the source architecture; they do not prove rendered visual parity.

Windows installed runtime acceptance uses script/test-windows-ui.ps1 separately with -DialogsOnly, -GallerySettingsOnly and any affected focused suite, -RequirePackage -FrozenEngine and the installed -AppDirectory. Dialog coverage includes rendered field/button bounds, dark fills, Header/value/event preservation, import mode gating, filter/sort and timing validation, content growth, cancel-before-show, keyboard lifetime and Primary/Secondary/Cancel results. Tests use stable control identities rather than old parent nesting. Cancel-only layout cases must leave project data unchanged.

Mac acceptance must inspect actual installed settings/sheets with native UI tests or native accessibility/screenshots, including adjacent actions, light/dark appearance, ordinary/compact bounds, accessible labels and cancellation. Run tests.test_segment_dialog_layout when segment sizing changes; it compiles and exercises the production Mac sheet-sizing code. Record exact runtime evidence and blockers in PROGRESS.md on both desktops. Never substitute source checks or an app launch for a native visual check. No finite test suite guarantees identical future screenshots; new or changed surfaces must extend this matrix and their relevant regression coverage.

Sarvam samples: every catalog voice exposes Play Sample when a Sarvam key is stored through its row and selected-voice action, with matching Play/Stop context menus. Published demos download without synthesis; missing demos generate a fixed, standard-tuning language sample once and persist locally. Both platforms use the shared engine cache and keep sample requests caching after Stop while suppressing stale playback.

All Sarvam sample Play controls and menu commands require a stored Sarvam key and are disabled while one sample prepares or plays. The active row and selected-voice Stop action remain available. Stop during preparation suppresses playback while the pending request finishes caching; Play re-enables after it finishes. V3 always uses its published demo, with no generated fallback.

Voice samples now share immediate Play/Stop labels/icons and an accessible preparation spinner across system/Apple, Piper, Gemini and Sarvam, including independent Summary and Piper catalog/removal windows. A shared native session disables competing Play commands, and failure/completion/Stop releases it. Stop restarts from the beginning on next Play; Windows sample Pause/Resume is removed to match the Mac reference. Both button and context menu use the same guarded actions. Provider-specific key/download requirements remain.

ElevenLabs Narration uses the same key/status/trash and adjacent action rows on both platforms, followed by Account Plan, Models and Voices, Voice Controls, then local Summary Voice. Both use recorded demos only. Account and Voice Library queries retain provider-supported pagination/sorts. Native API-key, account allowance and duplicate-name geometry checks live in SettingsDialog.ElevenLabs.cs; REST/security behavior is covered by test_elevenlabs_tts.py and the paired control/menu contract by test_elevenlabs_ui.py.

ElevenLabs models are dropdown-only. Only Search voices is a search box; Accent, Use case and public Style use native choice controls with provider/catalog metadata and All options on both desktops.

Voice-search fields span the full available browsing row on Windows, as on Mac; they are not ordinary two-column setting fields. ElevenLabs, Sarvam, independent Summary and Piper catalog/removal search retain their accessible names, filtering and menu commands. The shared full-width marker prevents dialog normalization from converting them back to half-width fields. Summary voice has an explicit heading, engine choice, speed/pitch/volume and reset, then voice browsing. Hidden engine groups collapse their headings and painted cards together. Native Settings/dialog checks assert these bounds and Summary ordering.

The YouTube browser handoff shows a native indeterminate spinner and announces “Opening YouTube project…” until the destination editor opens or the app reports an error. Mac displays a floating status panel to stay visible as focus moves from the library to an editor window. Windows displays the status in the existing window as it switches from the library to the editor.


## Shared inspector language (1.0.350)

Mac and Windows put View Project Language (Edit Project Language in Edit mode) before Copy and Translate and Edit. Generation, imports, saved results and review drafts share that project selection. Per-section generation pickers, manual synchronization, import-language selection and review-language filtering are removed. Copy and Translate inherits the project source language and retains only Target Language in its dialog. Native language/result controls, accessible names, edit guards and saved version histories remain. The same controls are reused in Project Settings and Language and Saved Results. Windows native smoke checks cover ordering and rendered bounds across all five tabs at ordinary/compact widths in light and dark themes; runtime results are recorded in PROGRESS.md.

Created Exports and export-readiness counts also follow the shared project language. Inspector export-language controls are removed; version filters list only that language, and multilingual files appear when they contain it.


## 2026-11-17 — Help and About information parity (1.0.351)

Settings Help uses one Help and keyboard shortcuts group on both desktops: Open VidiStudio Help followed by a collapsed Keyboard shortcut reference, with a checked context-menu toggle (`settings-shortcut-reference`). Both lists include Jump to Time. About has VidiStudio, FFmpeg, Piper voices and Third-party notices in the same order. It does not include a separate shortcut section; Windows no longer has Other components. App versions use three parts. FFmpeg has a concise release and separate license row; Windows values align to the right, and bundled media metadata comes from the bundled executable. Development builds without that executable identify the configured/PATH version as Installed version.

Piper licensing remains an actual platform exception: Mac bundles OHF piper-tts 1.8.0 (GPL v3+, including g2pW notices); Windows bundles rhasspy/piper 2023.11.14-2 (MIT). Mac has a separate g2pW notice action and Finder folder action; Windows uses File Explorer. Both retain the matching FFmpeg license, notice-index and notice-folder actions and context menus. Windows copies original Python distribution notices into its bundled engine license folder during builds. Native caption buttons remain OS-owned; Windows supplies opaque theme-matched hover/pressed fills to DWM.

The paired source gate and mutation tests reject group/order/label/default drift, removed Jump to Time reference wiring, lost license menus, and information-command gating behind editor processing. Native Windows gallery/settings tests check the reference toggle, release/license rows, accessible grouping/alignment, collapsed default, ordinary/compact scrolling and actual About menu invocation while idle/busy and minimized. Runtime execution evidence is recorded in PROGRESS.md.
