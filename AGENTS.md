# VidiStudio Mac agent guide

Native SwiftUI macOS 26 plain app in `VidiStudio.xcodeproj`. `VidiStudio/` owns native UI and engine invocation. `engine/vidistudio_engine.py` owns all project processing and writes. The sibling VidiStudio Online repository is a visual/workflow reference, not a desktop runtime dependency; online fixes are in scope when explicitly requested; preserve unrelated work.

Project data lives in portable local folders with relative paths. Credentials live only in the user config outside projects. No Firebase, Firestore, authentication or embedded website. Gemini runs only in the Python engine; keep API keys out of argv, logs and project JSON. Files API uploads need bounded readiness polling and cleanup.

Use native macOS controls with bundled Material Symbols for application iconography; system-owned chrome retains Apple icons. Shared AI settings use the online model/prompt schema. Preserve labels, keyboard access, visible focus and VoiceOver names. Liquid Glass comes from the system sidebar, toolbar and controls. Avoid painting custom opaque layers over them.

Run `script/build_and_run.sh --verify` for build and launch. Direct Xcode builds run `script/xcode_bundle_engine.sh`. `script/package.sh` creates a local-install ZIP. Python dependency versions used for validation are in `engine/requirements-build.lock`. `tests/test_engine.py` exercises real media processing and system speech; it needs OS speech access outside restricted sandboxes.

Every app fix or new feature must automatically advance the app version before build and validation; do not wait for a separate version-bump request. Increment the patch component of `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION`, keeping Debug and Release settings aligned. Record the resulting user-visible version and build number in `PROGRESS.md` with the change's validation evidence.

Use `VIDISTUDIO_TEST_ENGINE` to test the packaged executable. Do not claim live Gemini or Windows validation without actually running those paths. Record progress and release evidence in `PROGRESS.md`.
