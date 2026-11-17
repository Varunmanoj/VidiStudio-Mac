# Source and publication review — VidiStudio 1.0.352

These unchanged Release application exports are staged as drafts. The source review is not complete.

## Work completed

- All 103 exported Mac media images match compiled machine-code sections of the recorded installed Homebrew versions (80 packages).
- Collected and verified 380 Mac source/resource inputs, including 271 Cargo.lock-pinned rav1e crate archives. Exact recipes, receipts, patches, relocation script, source manifests and provenance are in `VidiStudio-1.0.352-macOS-media-source-review-INCOMPLETE.tar.gz` on the Mac draft.
- FFmpeg 9.0.1 source archive matches its installed recipe SHA-256 `cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635`.
- Recovered the missing GLib and Leptonica notices from matching source archives; see the Mac `NOTICES-SUPPLEMENT.zip`. The application bytes/signatures are unchanged.
- Windows FFmpeg/FFprobe byte-match the vendor's 9.0.1 full archive. Its original README, GPL license, release metadata and exact top-level FFmpeg commit source are in `VidiStudio-1.0.352-windows-FFmpeg-source-review-INCOMPLETE.zip` on the Windows draft.

## Remaining source gaps

1. Mac SRT 1.5.7 archive currently differs from the installed recipe checksum. Expected `fee6aee6b4933f01ba8b7e18d5d9e4896ad604053fdad2ac55df4a4f1561f30a`; retrieved `017cd1e437ef2073a4dd10ddf7b55e86bc3d6ebac0393d13bd22f6a57055d32b`. It was rejected instead of silently substituted.
2. The Tesseract recipe's auxiliary snum.traineddata URL returns 404. Tesseract code is collected and this data is not shipped in VidiStudio, but the recipe gap is retained for review.
3. Final Mac source-closure and build/vendor/environment reconstruction review remains pending. The collection is explicitly marked complete=false.
4. Windows incorporated static libraries' complete source/patch and matching build/toolchain materials are not established by a top-level FFmpeg archive. The supplier asks for an official-email request linking the app. The user requested skipping email; none was sent. Obtain those materials or build a separately controlled replacement and repeat application regressions before public redistribution.

## Other publication checks

Mac is Apple Development signed, not Developer ID signed/notarized. Windows uses a self-signed evaluation certificate. Publicly trusted signing/notarization and clean-machine/oldest-OS acceptance remain pending. See INSTALLATION.md, PLATFORM_COMPATIBILITY.md and FFMPEG-DISTRIBUTION-REVIEW.md. A Release build configuration is distinct from public trust and source-distribution completion.

Supplier guidance: https://github.com/GyanD/codexffmpeg/issues/257
Project checklist at the exported revision: https://github.com/Varunmanoj/VidiStudio-Mac/blob/24ef841b1becfa9a033773ece5f77d0d60be8f14/docs/ffmpeg-distribution.md
