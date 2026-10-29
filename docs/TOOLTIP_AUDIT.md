# Tooltip and automation audit

Status for the existing-asset, provenance, Markdown, narration-source, and export work.

## Rules

- Native menu-bar items do not support hover tooltips; their labels and shortcuts are the discoverability mechanism. This is a documented OS limitation.
- System alerts and confirmation sheets use native buttons; they keep their standard titles because AppKit does not display custom hover tooltips for alert buttons.
- Every custom button, icon button, toggle, picker, and progress action added or changed for this feature set carries `.help(...)` and an accessibility label/hint where the control needs one.
- Disabled controls explain the missing prerequisite in the tooltip.
- Markdown toolbar buttons include their shortcut in the tooltip.

## Checked areas

| Area | Status |
| --- | --- |
| Project → Import Existing Assets… and editor import button | Tooltip present |
| New Project source, existing-assets pickers, AD transcript/audio modes, Create & Combine | Tooltips and accessibility labels present |
| TXT timing editor: distribute, Gemini timing, save, per-field help | Present |
| Import report: review actions, close, conflict/omission rows | Present |
| Description rows: provenance, overlap, narration preview, More Options, context menu | Present for new controls |
| Add/Edit Segment provenance picker and timing/save actions | Present |
| Summary empty state, Markdown toolbar, preview, Markdown Help, provenance picker | Present |
| AD Overview narration sources/warnings, narration issues/voices dialogs | Present |
| Export dialog: source picker, save/cancel, described-export gating | Present |
| Settings, project browser, playback, narration, integrity | Existing controls audited; new controls have help text |

## Static checks

- Windows XAML buttons for imports, summary Markdown, and source selection are checked in `tests/test_import_assets_ui.py`.
- The Mac Markdown and import harnesses exercise the transformation and model logic; visual tooltip rendering requires an interactive accessibility session.

## Exceptions

- Menu-bar items (native OS).
- Native alert/confirmation buttons (AppKit).
- Progress overlays use text status plus accessibility labels rather than hover-only explanation.
