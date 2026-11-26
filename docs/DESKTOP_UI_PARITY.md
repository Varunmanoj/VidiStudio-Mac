# Desktop UI layout parity

Both desktop Help windows load the published /docs page on every open. The website controls its navigation, content, images and styling. A native header provides loading progress and Open in Browser. An unavailable connection displays “Documentation requires internet.” Retry appears immediately before Open in Browser after a page-load error. Starting a retry clears the error and restores the loading spinner.

Mac is the reference for shared organization and workflows. Use native SwiftUI/AppKit and WinUI controls; visual parity does not mean replacing native window chrome or copying OS-specific pixels.

| Paired surface | Shared layout contract | Source owners |
| --- | --- | --- |
| Settings pages | Compact named groups, common section order, aligned labels/fields, adjacent related actions, concise copy | Mac SettingsView and feature views; Windows SettingsDialog partials |
| Gemini, Sarvam and ElevenLabs credentials | Masked key, inline accessible status before trash; check/dashboard actions together below when they fit | GeminiAPISettingsView / SarvamVoiceSettingsView; SettingsDialog.Gemini / Sarvam / SpeechLayout |
| New Project | Source, source details, AD choices/assets and project location in compact groups | Mac project creation views; Windows NewProjectDialog |
| Open from Finder, File Explorer, or browser | Announce and display progress while opening the project. Keep All Projects available behind the separate editor and return focus to it on close. | Mac shared-video progress panel / window lifetime. Windows shared-video progress row / project library routing. |
| All Projects to project editor | New editors fill the usable display without entering full screen. Keep All Projects separate and preserve its normal, maximized or minimized state and existing bounds on open and close. Normal opening reuses the matching editor. | Windows uses native Maximize. Mac uses display-aware placement and receives project URLs without the system’s default window reopen behavior. On Windows, saved private projects open without the owner account and retain the separate authorization for online actions. Mac keeps its existing private-project account behavior. |
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

Window-state acceptance covers normal, maximized and minimized All Projects in the installed apps. On Mac, run `script/test_editor_window_state.sh "/path/to/saved/local/test/project"` with All Projects open, Accessibility access granted to the test shell, and the designated test editor closed. Use a uniquely named local project already in the library. The harness exercises the real project handoff, including when the library cannot receive clicks, and restores the library geometry afterward. On Windows, run `script/test-windows-ui.ps1 -ShellOpenOnly -RequirePackage -FrozenEngine -AppDirectory <installed-directory>` against the installed Debug package. It uses isolated fixtures and also checks editor reuse and saved private projects with and without a local copy, leaving remote analysis blocked without the owner.

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

Settings Help uses one Help and keyboard shortcuts group on both desktops: Open VidiStudio Help followed by a collapsed Keyboard shortcut reference, with a checked context-menu toggle (`settings-shortcut-reference`). The expanded reference presents matching accessible headings for Projects and Windows, Editor Navigation, Video Playback, Transcript Overlay, Summary Reading, Segment Editing, Generation and Narration, Import and Export, and YouTube Browser. Each section starts collapsed and expands independently with a native disclosure and a matching checked context-menu action. A named Search shortcuts field sits above Expand All and Collapse All. The same visible hint sits beside it on both platforms, wraps at compact widths, and is exposed as field help for screen readers. Searching by action or key displays matching rows and opens their sections automatically. Each new query opens its matches. Both platforms announce the settled result count, including zero and a single result. A new query or another captured key generates its own announcement even when the count is unchanged. While the field has focus, native key events insert the pressed shortcut and show exact key matches without running the command. Typing, editing and Tab navigation keep their normal behavior. Clearing search restores the previous expansion. The bulk commands apply to the visible sections and disable when nothing can expand or collapse. Expand All opens the reference when needed, and Collapse All leaves the parent in its current state. The parent context menu includes matching bulk and search commands. Command+F on Mac and Ctrl+F on Windows open the reference and focus its search field while Settings Help is selected, including when the reference is collapsed. Command+Q on Mac and Alt+F4 on Windows close the active Settings window from every page or close the standalone Help window, including from either window’s search field. The Settings window keeps the query and disclosure choices when switching pages or closing the parent disclosure. Each action and its key stay together. Both references include Jump to Time. About has VidiStudio, FFmpeg, Piper voices and Third-party notices in the same order. It does not include a separate shortcut section; Windows no longer has Other components. App versions use three parts. FFmpeg has a concise release and separate license row; Windows values align to the right, and bundled media metadata comes from the bundled executable. Development builds without that executable identify the configured/PATH version as Installed version.

Piper licensing remains an actual platform exception: Mac bundles OHF piper-tts 1.8.0 (GPL v3+, including g2pW notices); Windows bundles rhasspy/piper 2023.11.14-2 (MIT). Mac has a separate g2pW notice action and Finder folder action; Windows uses File Explorer. Both retain the matching FFmpeg license, notice-index and notice-folder actions and context menus. Windows copies original Python distribution notices into its bundled engine license folder during builds. Native caption buttons remain OS-owned; Windows supplies opaque theme-matched hover/pressed fills to DWM.

The paired source gate and mutation tests reject group/order/label/default drift, removed Jump to Time reference wiring, lost license menus, and information-command gating behind editor processing. Native Windows gallery/settings tests check the reference toggle, release/license rows, accessible grouping/alignment, collapsed default, ordinary/compact scrolling and actual About menu invocation while idle/busy and minimized. Runtime execution evidence is recorded in PROGRESS.md.

## Vertex AI connection and private videos (1.0.362)

Settings > AI groups the provider, authentication method, project ID, bucket and per-task Gemini models. The signed-in account has a green check and a text label. Both cloud fields have adjacent named Copy and Clear actions. Remove Google sign-in asks for confirmation. The Inspector, project menus and source filters expose the cloud video on both platforms.

The signed-in New Project browser shows the current Google Cloud project, source bucket, bucket file, destination and refresh action on both platforms. All project buckets can be listed; file names include their folder paths. Only videos enable creation.

The Vertex AI task pickers on both desktops read the same bundled capability rules. File transcription, speech generation and video understanding have separate choices. The menus retain exact version IDs and disabled empty states.

Start private YouTube projects from My YouTube Videos or Fetch Details in New Project. Saved private projects also reopen from All Projects for local playback and editing. Both desktops share the same native warning, default Cancel and Open Anyway. Screen readers announce the warning and both choices. Analysis commands, shortcuts and generation buttons are disabled for private YouTube projects with Gemini Developer API, Vertex AI with Google sign-in, or Vertex AI Express. The current provider remains selected. Both editors display “Private YouTube video analysis is not supported.” above the editor tabs, readable by VoiceOver and Narrator. The status has no actions. The editor keeps local playback and saved results available. Connection-wide permission errors for supported sources still identify the active provider. Inspector and menu metadata refresh verify the connected owning channel when the saved visibility is stale. The current editor stays open and the Fetched and Visibility rows update after saving. A missing owning-channel connection ends the loading state and keeps the saved details. When the user requests a refresh, both desktops use a native YouTube Sign-In Required dialog to present the sign-in message and focus the dialog.

The Gemini Developer API picker has a Gemini 4 heading on each desktop whenever a compatible model is present.

Open Cloud Videos follows the My YouTube Videos layout. Refresh sits with the source controls, List View and Table View share the Video layout control, and Actions sits beside Open in Editor. List View shows a thumbnail and filename. Table View separates the thumbnail, title, object path, size and modification date into columns. The native Mac table and Windows list with horizontally scrollable columns preserve the selection between layouts. The selected-video details region provides the full Cloud Storage metadata in either layout.

The File menu creation commands share one New Project layout and preselect its source. The Cloud Storage source stays visible in the dialog and is disabled until Google sign-in. The All Projects toolbar presents one New Project button that opens the shared source picker. On Mac the fixed title header retains its top inset while the form scrolls. On Windows the native companion window keeps the same size and position, with a fixed title, project type row, and bottom actions across all three sources and both Cloud Storage modes. Additional fields scroll within the window.

New Project stays in front of the All Projects or editor window that opened it. Mac presents an attached sheet and Windows uses its native companion window. Choose Video… and its context menu item open the system file picker. Open or Enter returns to the same form with the selected filename and moves focus back to Choose Different Video…. Cancel preserves the previous selection. Source and Audio Description radios expose their native roles, labels, and selection states. Offline and service warnings remain readable in place. Routine checks and recovery stay quiet during window changes.

When Google Cloud is signed out, Open Cloud Videos shows a centered sign-in prompt, Sign in with Google and Done. Sign-in loads the browser in place. Settings > Help lists Open Cloud Videos and My YouTube Videos beside the project shortcuts. The Open Cloud Videos dialog has project and bucket selectors, search, sort, List View and Table View, selected-video metadata, and Open in Editor. Choosing an existing video from New Project opens this shared browser with the configured project and bucket selected. The browser shows the access check, byte progress, verification and local preparation. Open editor windows show the same operation in the Mac progress banner or Windows status footer. Both dialogs close after a successful import. Both apps exclude unsupported file types, identify the source project for Vertex AI in the browser and Inspector, and keep the original bucket object when deleting a project imported from it. For app-owned uploads, both platforms hide cloud rename, removal and project deletion while permissions are unverified or denied, and check the object again before mutation. A missing local folder can still be removed from the library after checking its recorded app-owned object.

In Settings > AI, both AI providers use the same Local video and YouTube video groups, each with its own task choices. The Cloud Storage video group appears under Vertex AI with Google sign-in. Express mode shows compatible tasks. Shared model definitions and capability checks drive the aligned pickers and their icon-bearing checked context menus.

## Project Overview

The final editor section follows AD Transcript. Project details span the editor. Transcript and Summary appear side by side when space allows, followed by Audio description details and Description origins. Each pair stacks in a compact editor. Create narration audio follows the statistics. Each group has a visible heading and an accessible name. Counts and summary availability use the selected saved results in the viewing language.

## Editor generation shortcuts and Cloud Storage

The Project menu and editor buttons share the same generation actions, eligibility checks and regeneration confirmations. Use Command+Option+Shift on Mac or Ctrl+Alt+Shift on Windows with T in Transcript, S in Summary, D in Descriptions and N in Descriptions, AD Transcript or Overview. Windows mouse-hover tooltips on editor buttons include their matching shortcut where available in the active section. Accessible control names remain descriptive, and Windows also exposes the shortcut through UI Automation.

The editor Project menu includes Cloud Storage only when the project is linked to a video in a bucket. The All Projects menu retains access to cloud upload.

## Inspector YouTube source copying

Video Information exposes Copy YouTube Video ID and Copy YouTube URL beside their corresponding values, with icon buttons, tooltips, screen-reader names and matching row context commands. Copying uses the same action from either control and preserves the full saved URL. These actions require a corresponding value in a YouTube project.

## Editor Projects sidebar layout

Both editors show the layout icons only while the Projects sidebar is open. Mac uses an icon-only List View and Grid View segmented control at the bottom of the sidebar. Windows uses an icon button that describes the layout it will switch to and shows the matching shortcut. Closing the Windows sidebar while its layout button has keyboard focus returns focus to the sidebar toggle. View menu actions and keyboard shortcuts can open the sidebar in either layout.

## Editor preview toolbar

Preview and full-screen video are icon buttons with tooltips and accessible names on both desktops. The toolbar, View and Playback preview controls collapse or restore the preview area, including the timeline. The timeline follows its separate View setting when the preview returns. On Windows the packaged editor smoke test checks both tooltip states, video and timeline collapse, reclaimed editor space and the timeline setting at regular and compact widths in both appearances.

The Windows native editor smoke test checks tooltip text for app-owned buttons across the five editor sections in light and dark appearances, at normal and compact widths. The test also moves the mouse over Generate, Add, and Edit and checks that their native tooltip popups open. Generate has a hover target when AI is unavailable.

## AI connection availability and oversized videos

On both desktops, AI controls and their existing commands share connection availability. A compatible saved connection can be used after confirmation when the selected connection cannot run the task. The confirmation identifies the connection and the Cloud project for signed-in Vertex. Local narration and manual editing have their own availability.

New Project and direct video opening check the file size before importing. Above 2 GB, the native warning gives the size, a smaller-video choice and Cancel. With a saved Google sign-in and a configured Cloud project and bucket, a video within the Cloud Storage analysis limit also offers Upload to Cloud Storage. This selects the Cloud Storage source in New Project and keeps other form values. Direct file opening continues through the cloud import. Both entry points check the saved Cloud setup independently of the selected AI provider. The native dialog exposes its message and buttons to VoiceOver and Narrator. The existing cloud progress UI follows the transfer. In Open Cloud Videos, Open in Editor from the button, keyboard or row menu presents the size warning for a selected object above the Vertex limit before any download. The warning offers Choose a Smaller Video and Cancel and leaves the browser open.

The Cloud and YouTube browsers center the spinner and short status within the video results, with list selection and the action area kept in place. New YouTube projects center the details-fetch spinner in the source card. Cloud imports retain their separate byte progress.

The Actions and video context menus include a checked Select mode on both desktops. List and Table show a checkbox on each video and share one action target. Cloud changes use the selected object’s verified permissions. Opening a new private YouTube video requires the owning channel in YouTube Accounts and confirmation with Open Anyway. A saved private project can reopen from All Projects with the same confirmation and without a YouTube lookup. The two Settings sections each start their own service-specific Google consent and offer a separate, Cancel-default removal from this device.

New Project’s YouTube source opens My YouTube Videos as a picker attached to the form. Choose Video returns the URL and preview in the same form, preserving audio and caption settings. Escape cancels the picker and returns to New Project. The standalone browser uses Open in Editor.

All Projects uses one Filter Projects button in the toolbar. The native sheet on Mac and owned dialog on Windows group Source, Language, AI Provider and Sort by as aligned fields. Filter applies the choices together. Cancel and Escape leave the gallery unchanged. The AI Provider picker lists All AI Providers and the categories with matching loaded projects. It pairs with the direct View submenu and dialog context menu. The native layout and search controls remain in the toolbar.

Both video browsers use their existing opening action when a video row is double-clicked in List View or Table View. My YouTube Videos from New Project chooses the video for the form. The standalone YouTube browser and the Cloud Storage browser open the editor through their existing workflows. In Select mode, the checked video requires an explicit Choose Video or Open in Editor action. Existing buttons, menus and keyboard access use the same eligibility checks.

## YouTube playback

New Project shows YouTube channel and connected account on both desktops. All YouTube projects can attach a matching playback video from YouTube Information. Private projects also offer the chooser in the preview. The attachment supplies the gallery thumbnail and the native media player. Choose What to Delete includes the attachment as a project-wide checkbox. With a valid copy, Export offers Video and Web Playback. Without a copy, YouTube export shows Audio and Text.

Both editor status areas use byte-based progress for the copy. Public and unlisted projects can switch players without changing the timeline or the video export source.

Each project keeps one local playback copy. Choosing another file opens the native Replace Local Playback Video confirmation on both desktops. Cancel keeps the current copy and thumbnail. Confirming swaps both after the file passes validation and copying finishes.

The inspector puts an accessible trash button beside the filename when a project has a copy. Settings > Projects shows the same controls under Import into this project for the selected YouTube project. Settings labels the chooser Replace Local Playback Video when a copy is saved. The filename, chooser, named trash button and matching context-menu actions use the same availability and confirmations as the inspector. YouTube projects show a Local playback video section at the top of Import Existing Assets. Choose and Clear invoke the same staged actions in the context menu. Import commits the selection using the matching-file check, copy progress and replacement confirmation. Selecting either playback video or original audio disables the other chooser. State text identifies the saved file or staged selection to remove.

A usable playback copy supplies the video’s soundtrack for audio and video exports, while video analysis still uses YouTube. Both platforms require removing a saved playback video before importing original audio, and removing original audio before importing a playback video. The preview, inspector, import dialog and menus share those guards. Older projects containing both files offer removal for either one. The inspector and Settings > Projects > YouTube video place Open in YouTube Studio next to Open in YouTube when a connected channel matches. Both use shared buttons and context menus and reflow the buttons when needed.

Choose What to Delete shows Original Audio File and Local Playback Video under Project attachments for YouTube projects. Each checkbox and its context-menu toggle are enabled when the corresponding attachment exists. These options apply to the entire project regardless of the language filter and share the existing deletion review.

Settings > Projects shows an Imported assets section after Import into this project. Both desktops list saved imported source filenames by content type, language and version, plus project-wide audio and playback attachments. Import controls use a green checkmark and the spoken Imported status for completed imports, including those awaiting review. The inventory labels those versions Review needed. The Settings playback row appears for a saved copy or when an existing audio file blocks the chooser. Choose What to Delete and its context action open the existing deletion review for that project. Windows presents the review from the target editor and returns to Settings after the dialog closes.

Local playback and original audio import warnings show labeled durations in hours, minutes, seconds and milliseconds as applicable. Original audio warnings also show the difference when the video runtime is known. The AD audio import report uses the same readable units. Both desktops preserve their existing import and confirmation rules.

### Import decisions

Mac uses the native AppKit alert and Windows the responsive, theme-aware companion dialog. The warning presents Okay as the default and Import Anyway only for recoverable cases. Details and named actions remain available through the native accessibility tree. The two safe exits are the Okay button and Escape/window dismissal. Windows can open Review Timing directly from a text warning, while Mac exposes the timing editor from the import form. Earlier completed files in a batch are retained.

## Gemini narration voices

Both Narration pages put the Gemini voice browser inside the existing Voices group. The active connection, Language and region, full-width search, style and sort controls, selected voice and scrollable rows use the same order. Voice rows show their group, selected state and an adjacent icon for preview. Choosing a row applies its voice immediately. Row samples use the Narration sample text and the existing one-sample guard. Express shows an unavailable state. Each eligible provider controls its own library search and saved narrator preference.

In Settings > Narration, the selected narration provider’s voice and sample settings precede the separate on-device Summary voice section. This order applies to Gemini Voices, Sarvam Voices, and ElevenLabs Voices on both desktops.

## Processing announcements

Mac announces the current task when processing starts from All Projects or the editor. Windows announces the current task from the foreground Processing card, with one announcement per operation even when Settings and the main window observe the same job. Both keep the status available through accessibility and preserve keyboard focus. File and browser handoff progress uses its own opening announcement.
