# FFmpeg distribution review for VidiStudio

This review covers the current 1.0.352 Mac and Windows Release exports checked on 17 November 2026. Recheck every item when bundled executable/dependency bytes change. The local build and packaging scripts do not publish the app. Public source/notices completion is still pending; the GitHub uploads are drafts.

## Verified bundle

- The executable packaged from Homebrew `ffmpeg-full` 9.0.1_1 reports FFmpeg 9.0.1 and GNU GPL version 3 or later from `ffmpeg -L`. The bundled FFprobe reports the same version and license.
- Its configuration includes `--enable-gpl`, `--enable-version3`, `--enable-libx264`, and `--enable-libx265`. It does not include `--enable-nonfree`. FFmpeg's [license page](https://ffmpeg.org/legal.html) explains that GPL components change the license of the FFmpeg build; the [GPL v3 text](https://www.gnu.org/licenses/gpl-3.0.html) sets redistribution conditions.
- VidiStudio runs FFmpeg and FFprobe as separate executables through command-line arguments. The [GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html) treats command-line communication as a common separation mechanism, but says the boundary also depends on how the programs interact. Do not infer the app's own license solely from the FFmpeg executable's GPL status.

## Required before public redistribution

1. Provide the complete corresponding source for the exact FFmpeg and FFprobe binaries and GPL-covered linked components, including applicable patches and build/install scripts, using a GPL v3-compliant distribution method. An upstream homepage or a generic source download link alone does not establish that it matches this Homebrew build. See [GPL v3 section 6](https://www.gnu.org/licenses/gpl-3.0.html#section6) and [FFmpeg's compliance checklist](https://ffmpeg.org/legal.html).
2. Verify the license and source obligations of every bundled non-system dynamic library. The package currently includes x264, x265, xvid, rubberband, and many other libraries. The generated third-party index lists copied notices, but `glib-2.88.3` and `leptonica-1.87.0` currently have no notice file in the installed formula. Obtain and include their exact notices and audit other license texts and source obligations before shipping.
3. Audit licenses for the packaged Python dependencies and Material Symbols font. The build now copies available package notice files and the font's Apache 2.0 license into `Engine/licenses`; the presence of a file does not by itself establish fulfillment of every dependency's terms.
4. Ensure the release download page and any EULA identify FFmpeg and its license and give recipients the required access to corresponding source. FFmpeg's published checklist explicitly calls for About-box attribution, source availability, and clear license terms.
5. Review the final binary, its `-version` configuration and `-L` output, all notices, source archives, and distribution terms together before publishing. If the media build changes to an LGPL-only configuration, redo the analysis; do not reuse this GPL label automatically.

Settings → About exposes the bundled GPL v3 text, a generated third-party notice index, and the copied license folder. These controls make the information accessible in the app; they do not replace the source-distribution work above.

## 17 November 2026 source-collection evidence

All 103 exported Mac media images match the machine-code sections of their recorded installed Homebrew formula versions (80 packages). This compares compiled sections because app bundling changes load paths and signatures. The exact recipes and receipts were preserved; embedded recipe patches and VidiStudio's relocation script are included in the source-review collection.

Collected and verified 380 source/resource inputs, including 271 registry crates pinned by rav1e's release Cargo.lock. The FFmpeg 9.0.1 archive retrieved from `https://www.ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz` matches the installed recipe's SHA-256 `cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635`. Git sources are fetched at exact full commit IDs; archive downloads are rejected on checksum mismatch. Recovered GLib 2.88.3 LICENSES texts and Leptonica 1.87.0's notice from matching source archives and provided them as a separate notices supplement for the unchanged export.

Unresolved Mac inputs:

- SRT 1.5.7: recipe expects SHA-256 `fee6aee6b4933f01ba8b7e18d5d9e4896ad604053fdad2ac55df4a4f1561f30a`; the currently served tag archive hashes to `017cd1e437ef2073a4dd10ddf7b55e86bc3d6ebac0393d13bd22f6a57055d32b`. Do not substitute it or change the expected digest merely to pass collection.
- The Tesseract recipe's `snum.traineddata` URL returns 404. Tesseract code is collected and this auxiliary data file is not shipped in VidiStudio, but the recipe gap is explicitly retained for review.
- Final source-closure, vendor/build recipe and original build-environment reconstruction review remains pending. The collector always marks the collection `complete=false`; successful downloads alone do not certify redistribution completion or a bit-for-bit rebuild.

Windows FFmpeg/FFprobe byte-match the original `GyanD/codexffmpeg` 9.0.1 full-build archive. The vendor identifies FFmpeg commit `bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa`; that source tree, the original README, license and binary hash evidence were collected. The complete sources/patches and build scripts for its incorporated static libraries are not established by this top-level source archive. The supplier asks for an official-email request linking the application ([guidance](https://github.com/GyanD/codexffmpeg/issues/257)). A request was prepared locally, but the user explicitly asked to skip email; no message was sent. Do not represent the Windows source-review ZIP as complete corresponding source.

### Repeat the collection

From the Mac checkout with the exact installed Homebrew versions available:

```sh
python3 script/collect_media_sources.py \
  build/engine/vidistudio-engine/licenses/media-provenance.json \
  build/release-source-352/mac \
  --extra-inputs build/release-source-352/mac/rav1e-0.8.1/cargo-source-inputs.json
```

The extra-inputs JSON is derived from the matching rav1e source's Cargo.lock: each registry crate uses its locked checksum. Do not generate it from a newer upstream lockfile. The included source-review README, manifests and exact recipes document collected files and remaining gaps. Keep private credentials and unrelated local files out of any archive. The review archives and supplemental notices are attached to the draft releases, alongside the unchanged application exports.
