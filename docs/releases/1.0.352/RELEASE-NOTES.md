# VidiStudio 1.0.352 — Mac Apple Silicon

**Draft / publication pending.** This is a Release build, Apple Development signed and **unnotarized**. Corresponding-source/notices review and public-distribution checks are still open; this draft is not a publicly trusted Mac release.

Requires **macOS 26.4+ on Apple Silicon**. Download the `UNNOTARIZED.dmg`; the ZIP is an alternative. The Safari, Share and Finder extensions are embedded and version matched.

## What is included

VidiStudio is a local desktop video-accessibility editor for transcripts, summaries, timed audio descriptions, narration and described-media/caption exports. Projects live in local folders; online processing uses your own applicable service credentials.

## Changes in 1.0.352

- Audited bundled dependencies and aligned the app/package OS requirements with the binaries that actually ship.
- Set the Mac application and all three native extensions to macOS 26.4 minimum, Apple Silicon only.
- Kept Windows x64 at Windows 10 1809/build 17763; require Windows 11 21H2/build 22000 on ARM64 for the bundled x64 helper tools.
- Updated offline Help, setup/download requirements and cross-platform installation guidance.
- Added build/package checks that reject native dependencies or package contracts exceeding the advertised minimums.

The release includes the previously completed shared inspector language workflow and matching Settings Help/About updates. Browser code keeps its independent version **1.0.349**; native Mac extension bundle versions follow the app.

## Validation

Release builds and package checks passed. The build's focused source regressions and 20 installed packaged-engine CLI tests per desktop passed. Minimum-OS declarations are based on the dependency audit; actual runtime acceptance on macOS 26.4, Windows 10 1809 x64 and Windows 11 21H2 ARM64 remains pending. Full Windows rendered acceptance and native x64 hardware execution are not claimed.

## Installation

Requires **macOS 26.4 or later on Apple Silicon (M-series)**. Intel Macs are not supported by this download.

## Download and install

1. Download `VidiStudio-1.0.352-macOS-arm64-UNNOTARIZED.dmg` from this release. The ZIP is an alternative containing the same application build.
2. Optionally verify the download using `shasum -a 256 <downloaded-file>` and compare it with `SHA256SUMS.txt`.
3. Quit VidiStudio, open the DMG, and drag VidiStudio into Applications. Replace the previous copy. Eject the DMG, then open VidiStudio from Applications.
4. Keep a backup of important project folders before updating. Installing the app does not bundle or move your projects.

## Signing status

This is a **Release configuration build**, signed with the existing Apple Development team `LLVWNNUV26`. It is **not Developer ID signed or notarized**. macOS may block or warn when it is downloaded from the internet. If you trust this publisher and verified download, attempt to open it, then review **System Settings > Privacy & Security > Open Anyway** if macOS offers that choice. Follow the system confirmation yourself; do not disable Gatekeeper or remove security protections globally. An Apple Development signature does not guarantee installation on a clean Mac. Public Developer ID/notarization and clean-machine acceptance remain pending.

## Included extensions

The Safari Web Extension, Share extension and Finder extension are embedded in the app at 1.0.352/build 352. Enable the Safari extension in **Safari > Settings > Extensions** and grant website access as needed. Finder/Sharing extensions may require enablement in System Settings. These permissions are not silently enabled by installation. An existing container-identity warning may need a one-time user approval; do not delete app containers to suppress it.

Chrome and Edge extensions require separate browser installation/consent. Store review/draft status is not a published store listing. No desktop auto-update feed is provided by this GitHub release.

## Runtime requirements

Python, FFmpeg/FFprobe, local processing tools and the offline Help book are bundled. Optional voice models need downloading. Online processing needs internet and your own applicable API keys/accounts. Keep macOS media components and system voices installed.

## Publication status

This release is staged as a draft while the exact FFmpeg/dependency source collection and notices are reviewed. Read `SOURCE-REVIEW.md` and `PLATFORM_COMPATIBILITY.md`. Passing package checks does not establish runtime acceptance on the oldest supported OS. Do not treat this draft as a publicly trusted/notarized release.

## Source revision

Mac: `24ef841b1becfa9a033773ece5f77d0d60be8f14`. Assets and SHA-256 checksums are attached. The source-review file distinguishes collected material from unresolved requirements.
