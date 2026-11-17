# Desktop OS and dependency compatibility audit

Audited 17 November 2026 for VidiStudio 1.0.352. These are the lowest defensible **technical minimums with the current shipped dependency set**, not a certification that every workflow has been exercised on the oldest OS. Apple Silicon remains the only Mac CPU target; Windows ships x64 and ARM64, not 32-bit x86.

| Download | Minimum OS contract | Limiting requirement |
| --- | --- | --- |
| Mac arm64 | **macOS 26.4** | The bundled `libtesseract.5.dylib` requires 26.4. Most of its FFmpeg media dependency closure requires 26.0. |
| Windows x64 | **Windows 10 version 1809, build 17763** | Windows App SDK 2.5.1 and its runtime MSIX require 17763. |
| Windows ARM64 | **Windows 11 version 21H2, build 22000** | The package runs x64 frozen Python, FFmpeg/FFprobe, Deno and Piper helpers through Windows 11 x64 emulation. Windows 10 on ARM supports only x86 emulation. |

Use an OS edition receiving vendor updates. A compatibility floor does not extend Microsoft's or Apple's support lifecycle.

## Evidence and dependencies

| Component | Audit result and OS impact |
| --- | --- |
| Native Mac SwiftUI/AppKit/AVKit/WebKit app | Compiles at 26.4 against the installed macOS 27.2 SDK. `.glassProminent` needs macOS 26; the 27-only `NSMenuItem.preferredImageVisibility` usage is availability guarded. The SDK version is not the runtime minimum. |
| Mac Safari, Share and Finder extensions | All three targets and their Info.plist minimums follow 26.4. Each is arm64 and uses the app's signing team. No separate higher extension deployment requirement was found. |
| Mac media tools and native libraries | Inspected all 250 Mach-O images in the actual app, including executables, dylibs and Python extension modules. Before the change, four app/extension binaries declared 27.0, 100 media binaries declared 26.0, Tesseract declared 26.4, 129 images declared 11.0, Deno declared 12.0, and 15 native images declared 14.0. After compilation, the app/extension images declare 26.4 too. |
| Mac frozen Python 3.14.6 | The engine bootloader, Python framework and collected native modules are included in the binary scan. Their minimums do not exceed the media closure's 26.4. |
| Mac NumPy 2.5.4 / ONNX Runtime 1.31.0 / Piper 1.8.0 | The native wheels were scanned, rather than inferred from Python package names. The NumPy native images declare 14.0. Piper's native speech dependencies are covered by the complete Mach-O scan. Downloaded voice models are data, not a separate OS runtime. |
| Mac FFmpeg/FFprobe | Bundled from the current Homebrew media installation with non-system dylibs relocated into the app. The current media build, including its linked OCR library, is the reason macOS 26.0 is insufficient. Do not lower a Mach-O version header to pretend a newer binary works on an older OS. |
| Windows WinUI 3 / Windows App SDK 2.5.1 | The exact installed runtime MSIX manifests for x64, ARM64, ARM64EC and x86 declare `Windows.Universal` MinVersion `10.0.17763.0`. The application itself uses a Desktop-only device-family contract. Newer optional SDK AI/ML features are not called by this application; the unused `systemAIModels` capability was removed. |
| Windows .NET 8 app and speech host | Release packages include the .NET runtime. Both projects explicitly declare their minimum runtime OS by CPU. Their Windows SDK target is 22000 so the ARM64 supported minimum is not higher than the compile target; x64's supported minimum remains 17763. A TFM's SDK version alone does not require that OS when SupportedOSPlatformVersion is explicitly lower. |
| Windows Python 3.12.14 and PyInstaller runtime | The current frozen x64 runtime can run on Windows 10 x64; Python 3.12 itself supports Windows 8.1 and newer, below the app's 1809 floor. Running that x64 runtime on ARM64 requires Windows 11 emulation. |
| Windows FFmpeg/FFprobe 9.0.1 full build | The shipped Gyan build is for x64 and requires Windows 10 or later. It is included beside the frozen engine. Native Windows 10 x64 is allowed; the ARM64 package uses Windows 11 emulation. |
| Windows Piper 2023.11.14-2 and ONNX Runtime | The pinned, SHA-256 verified `piper_windows_amd64.zip` ships x64 code on both Windows targets. ONNX Runtime supports Windows 10 1809 and later. Its model files are optional downloads. |
| Microsoft Visual C++ v14 runtime on Windows | PE import-table inspection found `MSVCP140.dll`, `VCRUNTIME140.dll` and `VCRUNTIME140_1.dll` imports in Piper/ONNX. The package contains the VCRUNTIME DLLs inside the Python engine, but no MSVCP140.dll; the audited Windows App SDK framework also supplies no MSVCP140/VCRUNTIME140 DLLs. Install Microsoft's supported **x64 Visual C++ v14 Redistributable** for Piper on both x64 and ARM64. This external prerequisite is not embedded in the current MSIX. The current redistributable supports Windows 10/11 and its x64 installer also carries ARM64 libraries. |
| Deno 2.9.7 / yt-dlp 2026.8.19 / yt-dlp-ejs 0.8.0 | Deno's Windows baseline is Windows 10 1709 (IsWow64Process2), below the x64 app floor. The actual Mac Deno binary declares 12.0. yt-dlp and its EJS solver use the included Python and JavaScript runtimes. No separate user-installed JavaScript runtime is needed. |
| Google GenAI, Sarvam, ElevenLabs HTTP integration | Python HTTP/JSON clients run in the bundled interpreter. Their native TLS/cryptography dependencies are included in the Mac image scan and Windows frozen runtime. They do not add a newer UI/OS requirement; they require network access and the user's appropriate API key/account for the requested service. |
| Other locked Python dependencies | All packages in `engine/requirements-build.lock`, including cryptography, cffi, pydantic-core, Brotli, Pillow, NumPy and ONNX native modules, ship inside the scanned Mac engine. Pure Python dependencies follow the bundled interpreter. Windows's frozen runtime is rebuilt and checked separately; its requirements are in `engine/requirements.txt`. |
| WebView2 on Windows | The app's HTML Help and YouTube player require the Evergreen WebView2 Runtime. It is included with Windows 11 and commonly installed on Windows 10, but the current MSIX ZIP does not embed the browser runtime. Install Evergreen if it is missing. Its supported Windows baseline does not exceed the app's x64 floor. |
| OS media and system voices | Local playback uses AVKit on Mac and Windows media APIs on Windows. Keep system media components and speech voices installed. Online processing does not replace these playback components. Some codecs/media editions may need the OS vendor's optional components. |
| Safari/Chrome/Edge browser extensions | Safari's native component ships with the Mac app. Chrome and Edge use architecture-independent browser code and their own store/browser requirements. The browser extension is optional for local projects; it does not raise the core desktop OS floor. Independent browser release remains 1.0.349. |
| Credentials and local storage | Existing Keychain/Credential Manager and local-folder APIs do not raise these floors. Keys remain outside project folders; changing the minimum OS does not move or reset existing data. |

## Why this does not target an older Mac

The source contains a macOS 26 SwiftUI control style, and 101 shipped media-library images require 26.0 or 26.4. Supporting macOS 15 or 14 would require a different/rebuilt media dependency closure and guarded UI replacements, followed by testing on those systems. Changing only `LSMinimumSystemVersion` would produce an app that installs but may fail to load its processing tools. This task preserves the current dependency versions and functionality.

## Build and release enforcement

- Xcode's deployment target is 26.4 for the app and all three extensions; all builds remain arm64 only.
- `script/check_macos_compatibility.py` scans Mach-O load commands (`LC_BUILD_VERSION` and `LC_VERSION_MIN_MACOSX`), checks the CPU/platform, rejects code requiring a newer OS, and checks app/extension Info.plist minimums. The engine-bundling and signed build scripts run it. A newer Homebrew bottle therefore cannot silently invalidate the advertised floor.
- Windows main/speech projects declare `SupportedOSPlatformVersion` by CPU. The MSIX source names only Windows.Desktop; the SDK writes its minimum from TargetPlatformMinVersion. `script/verify-windows-package.py` requires 17763 on x64 and 22000 on ARM64, preventing a Windows 10 ARM install contract from slipping back in.
- SDK, .NET/Python build-tool and browser versions are build/runtime dependencies, not all separate end-user installations. Release ZIPs retain Windows App SDK dependency packages and installation instructions.
- Canonical Help, generated Windows Help, website guide, landing-page download CTA and download cards use the same published minimums. Technical dependency names/details stay out of the marketing cards.

## Validation limits

The available machines run macOS 27 and Windows 11 ARM64. A successful lower-target compile, matching binary load commands and provider OS requirements justify the declared contract; they do not replace actual runtime acceptance on macOS 26.4, Windows 10 1809 x64 or Windows 11 21H2 ARM64. Those oldest-OS runs remain unverified. Native x64 hardware is unavailable. Release/signing/extension registration and packaged-engine tests are recorded in PROGRESS.md. Public signing/notarization and the existing FFmpeg redistribution obligations are separate from OS compatibility.

## Primary references

- [Microsoft Windows App SDK compatibility](https://github.com/microsoft/WindowsAppSDK)
- [Microsoft: compile targets versus supported minimum OS](https://learn.microsoft.com/dotnet/standard/frameworks#support-older-os-versions)
- [Microsoft: Windows on ARM emulation](https://learn.microsoft.com/windows/arm/apps-on-arm-x86-emulation)
- [Python 3.12 on Windows](https://docs.python.org/3.12/using/windows.html)
- [Deno requirements](https://docs.deno.com/runtime/getting_started/installation/)
- [Gyan FFmpeg build requirements](https://www.gyan.dev/ffmpeg/builds/)
- [ONNX Runtime Windows support](https://onnxruntime.ai/docs/get-started/with-windows.html)
- [Microsoft Visual C++ v14 Redistributable](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist/)
- [WebView2 distribution and runtime prerequisites](https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution)

The exact per-file Mac binary evidence is generated as `build/minimum-os-binaries-352.json`; the report is regenerated against the final installed/release app, rather than treating a prior bundle as proof of a new build.
