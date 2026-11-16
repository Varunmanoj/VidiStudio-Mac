# Desktop UI layout parity

Mac is the reference for shared organization and workflows. Use native SwiftUI/AppKit and WinUI controls; visual parity does not mean replacing native window chrome or copying OS-specific pixels.

| Paired surface | Shared layout contract | Source owners |
| --- | --- | --- |
| Settings pages | Compact named groups, common section order, aligned labels/fields, adjacent related actions, concise copy | Mac SettingsView and feature views; Windows SettingsDialog partials |
| Gemini and Sarvam credentials | Masked key, inline accessible status before trash; check/dashboard actions together below when they fit | GeminiAPISettingsView / SarvamVoiceSettingsView; SettingsDialog.Gemini / Sarvam / SpeechLayout |
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
