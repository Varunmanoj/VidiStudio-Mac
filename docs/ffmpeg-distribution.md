# FFmpeg distribution review for VidiStudio

This review describes the macOS Release bundle built on 21 September 2026. Recheck every item when the bundled executable or dependencies change. The local build and packaging scripts do not publish the app.

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
