# VidiStudio Mac agent guide

Native SwiftUI macOS 26 plain app in `VidiStudio.xcodeproj`. `VidiStudio/` owns native UI and engine invocation. `engine/vidistudio_engine.py` owns all project processing and writes. The sibling VidiStudio Online repository is a visual/workflow reference, not a desktop runtime dependency; online fixes are in scope when explicitly requested; preserve unrelated work.

Project data lives in portable local folders with relative paths. Credentials live only in the user config outside projects. No Firebase, Firestore, authentication or embedded website. Gemini runs only in the Python engine; keep API keys out of argv, logs and project JSON. Files API uploads need bounded readiness polling and cleanup.

Use native macOS controls with bundled Material Symbols for application iconography; system-owned chrome retains Apple icons. Shared AI settings use the online model/prompt schema. Preserve labels, keyboard access, visible focus and VoiceOver names. Liquid Glass comes from the system sidebar, toolbar and controls. Avoid painting custom opaque layers over them.

Run `script/build_and_run.sh --verify` for build and launch. Direct Xcode builds run `script/xcode_bundle_engine.sh`. `script/package.sh` creates a local-install ZIP. Python dependency versions used for validation are in `engine/requirements-build.lock`. `tests/test_engine.py` exercises real media processing and system speech; it needs OS speech access outside restricted sandboxes.

Every app fix or new feature must automatically advance the app version before build and validation; do not wait for a separate version-bump request. Increment the patch component of `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION`, keeping Debug and Release settings aligned. Record the resulting user-visible version and build number in `PROGRESS.md` with the change's validation evidence.

Use `VIDISTUDIO_TEST_ENGINE` to test the packaged executable. Do not claim live Gemini or Windows validation without actually running those paths. Record progress and release evidence in `PROGRESS.md`.

## Xcode MCP

This Mac configures Xcode's MCP server for local ChatGPT and Codex clients as `xcode`, using `xcrun mcpbridge`. When the Xcode MCP tools are available in a session, use them as the primary integration for inspecting and controlling the open `VidiStudio.xcodeproj`: Xcode-aware navigation, scheme and target inspection, compiler diagnostics, building, testing, running, debugging, and other capabilities exposed by Xcode belong on this path.

Before using Xcode MCP, verify that `VidiStudio.xcodeproj` is open in Xcode and that Xcode > Settings > Intelligence > Model Context Protocol > Allow external agents to use Xcode tools is enabled. If the server is configured but its tools are absent from the current agent session, report that the local ChatGPT/Codex client needs to restart or begin a new session; do not claim Xcode MCP control from configuration alone.

Xcode MCP complements rather than replaces repository validation. Continue to run `script/build_and_run.sh --verify` for the required packaged build and launch, run packaged-engine tests with `VIDISTUDIO_TEST_ENGINE`, and record the exact evidence in `PROGRESS.md`. Treat Xcode MCP build, run, preview, and diagnostic results as distinct from script packaging, engine tests, live Gemini execution, Windows validation, commit, and push evidence.
