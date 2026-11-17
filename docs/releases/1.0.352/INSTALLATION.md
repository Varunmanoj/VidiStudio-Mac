# Install VidiStudio 1.0.352 on Mac

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
