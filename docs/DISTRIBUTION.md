# VidiStudio desktop release guide

Checked 17 November 2026. Build tools are **Xcode** on Mac and **Visual Studio** on Windows; VidiStudio itself has no build or certificate-creation screen.

## Recommended distribution

Publish an Apple Silicon (`arm64`) DMG and separate Windows `x64` and `ARM64` MSIX download ZIPs on GitHub Releases. x64 means 64-bit Intel/AMD; 32-bit x86 is not a supported app target. The Windows ZIPs must retain their runtime dependencies and installation instructions. An MSIX is an installer containing the app's EXE; a separately downloadable EXE installer is not currently implemented.

**Release configuration and certificate trust are separate.** A Release binary can still be signed with a development or self-signed certificate. Those signatures do not make it a publicly trusted download.

| Channel | Recommended signature | What users do |
| --- | --- | --- |
| Mac direct download | Apple-issued Developer ID Application; notarized and stapled | Open DMG, drag app into Applications, open app; enable desired extensions |
| Windows direct download | Publicly trusted code-signing identity or eligible Azure Artifact Signing identity | Install matching dependencies and signed MSIX |
| Windows private evaluation | Self-signed code-signing certificate | Administrator explicitly trusts the public CER before installing Release MSIX |
| Microsoft Store | Store submission/signing | Install through Store; this is an alternative to GitHub |

A self-signed Mac certificate is not a substitute for Developer ID or notarization. Do not ship the current development-signed DMG as though it is a notarized public release. On Windows, self-signed Release packages can be shared for controlled evaluation, but every recipient must establish certificate trust. Do not ask general customers to disable Gatekeeper, SmartScreen, or security protections.

## Mac: certificates and Xcode

1. Enroll in the Apple Developer Program using the publisher account. Keep the existing bundle identifiers and team (`LLVWNNUV26`) unless you intentionally plan a publisher migration.
2. In **Xcode > Settings > Accounts**, select the Apple Account and team, then **Manage Certificates > + > Developer ID Application**. The account must have the required certificate-management role. Alternatively create a certificate signing request in Keychain Access, then issue/download the Developer ID Application certificate from Apple's developer account and import it into the same login keychain with the private key.
3. Confirm `security find-identity -p codesigning -v` lists **Developer ID Application** with its private key. A `.cer` by itself is insufficient. A Developer ID Installer certificate is for signed `.pkg` installers; the proposed `.app`/DMG route uses Developer ID Application.
4. Back up the signing identity securely using Keychain Access's export of the identity and private key to a password-protected `.p12`. Keep the backup and its password outside Git and release downloads. Do not revoke or replace the existing development identity just to make a release.
5. Open `VidiStudio.xcodeproj`. Select the **VidiStudio** scheme. Inspect the app, Safari, Share, and Finder extension targets. Use the same team for all four targets, retain each extension's canonical entitlements, and keep all versions/build numbers equal.
6. For the app and all three extensions, set **Build Settings > Architectures > Architectures** for Release to **arm64**. Archive with **Build Active Architecture Only = No**. The Python engine, FFmpeg, FFprobe, Deno, and native libraries must also support arm64; an arm64 Swift executable alone is insufficient. Prepare the engine on Apple Silicon, outside Rosetta. Do not add an Intel slice.
7. Check the actual minimum system version before advertising compatibility. The inspected 1.0.350 bundle declares **macOS 27.0**, despite older repository descriptions saying macOS 26. Changing that minimum requires separate compatibility work. This is the inspected 1.0.350 artifact, not a promise about subsequent releases.
8. In **Product > Scheme > Edit Scheme > Archive**, use **Release**. Choose the Mac archive destination and **Product > Archive**.
9. In **Window > Organizer > Archives**, select the archive and **Distribute App > Direct Distribution** (or the custom **Developer ID** route in Xcode versions using that label). Export a Developer ID signed, notarized app. Resolve any signing, provisioning, hardened-runtime, or notarization diagnostics before proceeding. Ensure embedded targets use Skip Install as appropriate so this is an app archive, not a generic archive.
10. Xcode must include and distribution-sign every nested native dependency: Python, native modules, media executables/libraries, and the three extensions. The repository's local script uses recursive development signing and is **not a production notarization pipeline**. Do not assume changing `VIDISTUDIO_SIGNING_IDENTITY` alone makes its output distribution-ready. Follow Apple's inside-out signing guidance if the archive exporter cannot sign a dependency.

Validate the exported app (replace the example path):

```sh
RELEASE_APP='/absolute/path/to/export/VidiStudio.app'
codesign --verify --deep --strict --verbose=2 "$RELEASE_APP"
codesign --display --verbose=4 "$RELEASE_APP"
xcrun stapler validate "$RELEASE_APP"
spctl --assess --type execute --verbose=4 "$RELEASE_APP"
lipo -archs "$RELEASE_APP/Contents/MacOS/VidiStudio"
python3 script/verify_extensions.py "$RELEASE_APP"
```

Expect `arm64`, Developer ID authority, the intended team, hardened runtime, and notarized Gatekeeper acceptance. This repository's extension verifier checks app/extension identity, versions, entitlements and browser resources; it does not prove notarization or validate all nested architecture slices. Check each bundled Mach-O with `file`/`lipo`; portable scripts and resources have no CPU architecture.

Keep production export separate from the installed development app. The local installer deliberately enforces the previous designated requirements, so a first transition from Apple Development to Developer ID can require deliberate migration and user approval. Do not weaken identity checks, delete containers, reset permissions, or use ad hoc extension signatures to force that transition.

### Create the public DMG after Xcode export

Run from the Mac checkout. Supply the exported, stapled app and actual Developer ID certificate SHA-1. Store notarization credentials interactively using `xcrun notarytool store-credentials VidiStudio-notary`; do not put passwords in scripts or logs.

```sh
RELEASE_APP='/absolute/path/to/export/VidiStudio.app'
DEVELOPER_ID_SHA1='REPLACE_WITH_DEVELOPER_ID_CERTIFICATE_SHA1'
mkdir -p dist
STAGE_DIR="$(mktemp -d "$PWD/build/public-dmg.XXXXXX")"
ditto "$RELEASE_APP" "$STAGE_DIR/VidiStudio.app"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname VidiStudio -srcfolder "$STAGE_DIR" -ov -format UDZO dist/VidiStudio-macOS-arm64.dmg
codesign --sign "$DEVELOPER_ID_SHA1" --timestamp dist/VidiStudio-macOS-arm64.dmg
xcrun notarytool submit dist/VidiStudio-macOS-arm64.dmg --keychain-profile VidiStudio-notary --wait
# Continue only when the submission reports Accepted.
xcrun stapler staple dist/VidiStudio-macOS-arm64.dmg
xcrun stapler validate dist/VidiStudio-macOS-arm64.dmg
hdiutil verify dist/VidiStudio-macOS-arm64.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 dist/VidiStudio-macOS-arm64.dmg
rm -rf "$STAGE_DIR"
shasum -a 256 dist/VidiStudio-macOS-arm64.dmg
```

Never package an app after making changes that invalidate its accepted signature/ticket. Remove temporary exported/staged app copies after validation and keep one installed copy in `/Applications`. Do not run the app from the mounted DMG. Test a browser-downloaded, quarantined copy on a clean Apple Silicon Mac, including Safari handoff, Share, Finder, project creation, local narration and export.

### Current local packaging command

```sh
./script/package.sh
```

This explicitly builds **Release** and produces `dist/VidiStudio-macOS-arm64.zip` and `.dmg`. With the certificate currently installed on this Mac it uses Apple Development signing and is not notarized. It is useful for local validation, not evidence of public distribution trust. After local packaging, the temporary signed build product remains in `build/DerivedData.noindex`; `./script/build_and_run.sh --verify` replaces the installed app and removes that product. Inspect signatures and extension registration after installation.

If you specifically need a self-signed Mac certificate for an isolated experiment: open **Keychain Access > Certificate Assistant > Create a Certificate**, choose a unique test name, **Self Signed Root**, and **Code Signing**. That certificate is trusted only where explicitly configured; it cannot produce an Apple notarized release, and the project's stable-team extension checks intentionally reject it. Do not substitute it for the current app or extension identity.

## Windows: prepare Release builds

Use Windows with Visual Studio's WinUI/.NET tools, Windows SDK/MSIX tools, and Desktop development with C++ including both ARM64 and x64 toolsets. Keep both desktop checkouts adjacent for parity checks. Build on a local NTFS path; avoid compiling directly from the Mac shared UNC path. A separate checkout/environment per CPU is easiest because `runtime/engine` is shared between builds within a checkout.

1. Open `Vidi Studio Windows.slnx` in **Visual Studio**.
2. In the toolbar/Configuration Manager choose **Release**, then **ARM64** or **x64**. Do not choose Win32/x86.
3. Prepare the matching Python build environment and frozen engine, speech helper, Piper runtime, and FFmpeg/FFprobe. The frozen engine's architecture follows the Python interpreter used to run PyInstaller, not Visual Studio's platform selector. x64 Python can run on Windows 11 ARM through emulation. An ARM64 Python engine will not work in an x64 package on Intel/AMD Windows.
4. From a PowerShell window in the appropriate checkout, prepare dependencies using a Python executable of the intended architecture:

```powershell
.\script\setup-windows.ps1 -Platform ARM64 -Python 'C:\path\to\arm64\python.exe' -FreezeEngine
# In a separate x64 checkout/environment:
.\script\setup-windows.ps1 -Platform x64 -Python 'C:\path\to\x64\python.exe' -FreezeEngine
```

The ARM64 package still uses x64 Piper and, with the current media setup, x64 FFmpeg/FFprobe under **Windows 11 ARM64 emulation**. This is an ARM64 native UI and shell extension, not a claim that every helper is native ARM64. Python and media runtime versions should be pinned and recorded for public reproducibility.

### Create a self-signed certificate for evaluation

The current manifest Publisher is exactly **CN=personal**. This is a development publisher label; select the real long-term publisher before the first public release. A trusted certificate's Subject must match Publisher exactly. Changing Publisher later changes package identity and needs an upgrade/data migration plan.

The new packaging script can create/reuse a self-signed certificate in the current user's Personal store and export **only its public CER**. Its private key is non-exportable. It deliberately does not modify Trusted People or install the app. The `SELF-SIGNED` filename denotes certificate trust, **not Debug configuration**: builds are Release.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\package-release.ps1 `
  -Platform ARM64 -FfmpegDirectory 'C:\path\to\ffmpeg\bin' -CreateTestCertificate

# Run in the independently prepared x64 checkout/environment:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\package-release.ps1 `
  -Platform x64 -FfmpegDirectory 'C:\path\to\ffmpeg\bin' -CreateTestCertificate
```

The execution-policy option applies to this process only. The script bundles FFmpeg/FFprobe beside the frozen engine, restores/publishes with an explicit CPU and ReadyToRun, includes the .NET runtime with SelfContained=true, publishes the matching speech helper before MSBuild evaluates content, runs Release packaging, validates package contents/CPU, signs the MSIX, exports the public certificate and copies Windows App SDK dependency packages. Output is under `dist/release/<four-part-version>/`; upload the per-CPU ZIPs so dependency files remain together.

To create a certificate manually instead (run once and reuse):

```powershell
$cert = New-SelfSignedCertificate -Type Custom -Subject 'CN=personal' `
  -KeyUsage DigitalSignature -HashAlgorithm SHA256 -KeyAlgorithm RSA -KeyLength 3072 `
  -KeyExportPolicy NonExportable -CertStoreLocation Cert:\CurrentUser\My `
  -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.19={text}') `
  -FriendlyName 'VidiStudio TEST package signing' -NotAfter (Get-Date).AddYears(1)
Export-Certificate -Cert $cert -FilePath .\VidiStudio-signing.cer
$cert.Thumbprint
```

Keep the same certificate for both architectures. Do not create a new one every release. Certificate renewal must preserve publisher identity, and self-signed recipients must trust any replacement certificate separately. Only export a password-protected private-key backup when you deliberately create an exportable identity; never put a PFX/private key or its password into GitHub Releases.

### Publicly trusted Windows release

For GitHub downloads, obtain a publicly trusted code-signing certificate or evaluate Azure Artifact Signing eligibility for your publisher/location/account. A private local certificate cannot create that public trust. Microsoft Store submission is an alternative with Store-managed signing. Public signing is not a guarantee of immediate SmartScreen reputation.

Set the manifest Publisher to the exact verified certificate Subject before building. For a certificate with a locally accessible key in `Cert:\CurrentUser\My`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\script\package-release.ps1 `
  -Platform x64 -FfmpegDirectory 'C:\path\to\ffmpeg\bin' `
  -CertificateThumbprint 'REPLACE_WITH_CERTIFICATE_THUMBPRINT'
```

Repeat for ARM64. The script timestamps these signatures. Azure Artifact Signing and hardware-token certificates may need their provider's SignTool integration instead; the local-thumbprint helper is not an implementation of every remote signing service.

Visual Studio manual alternative: right-click the application project, choose **Package and Publish/Publish > Create App Packages**, choose **Sideloading**, select the intended certificate, and select **Release** configurations for ARM64/x64. Names vary by Visual Studio version. The repository build path is preferable for its parity/runtime checks. `script/build-windows.ps1 -Platform x64 -Configuration Release -Package` creates the package but explicitly disables signing; sign the result afterward. Confirm the native Explorer DLL and matching speech host are included. The MSIX package signature protects the contained native extension; it does not require a separate browser-store submission or separate MSIX for Explorer/Share integration. Additional Authenticode signatures on EXEs/DLLs can be part of the production policy.

### Install and verify on a recipient Windows machine

For a self-signed evaluation only, first verify the certificate fingerprint with the publisher through a trusted channel. Then an administrator explicitly installs the **public** CER:

```powershell
Import-Certificate -FilePath .\VidiStudio-signing.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
```

Install the runtime dependencies from the matching CPU directory (`Dependencies\arm64` or `Dependencies\x64`) and the signed MSIX. Example from inside the extracted CPU folder:

```powershell
$cpu = 'arm64' # use x64 on Intel/AMD Windows
$dependencies = @(Get-ChildItem ".\Dependencies\$cpu" -File | Where-Object Extension -In '.msix','.appx' | ForEach-Object FullName)
$package = Get-ChildItem . -Filter 'VidiStudio-*.msix' | Select-Object -First 1
if ($dependencies.Count) { Add-AppxPackage -Path $package.FullName -DependencyPath $dependencies }
else { Add-AppxPackage -Path $package.FullName }
Get-AuthenticodeSignature $package.FullName
Get-AppxPackage -Name '7b6f5f53-8ba2-429e-a747-0e2393ce9cee' | Select-Object Name,Version,Architecture,Status
```

For developer registration conflicts, back up app data/settings and follow a deliberate replacement installation; do not uninstall a customer's package casually. Do not advertise an upgrade from the current development registration until tested. Verify a clean-machine signed install, one Start entry, Explorer/Share commands, local narration, engine doctor, local import/export, and browser handoff. A package-content check or an emulated x64 run is not proof of native x64 hardware compatibility. GitHub Releases alone do not implement automatic desktop updates; an `.appinstaller` update feed or another updater would be separate work.

## Extensions: what to publish

| Extension | Mac | Windows | Distribution |
| --- | --- | --- | --- |
| Safari Web Extension | arm64 native `.appex` plus shared web resources | Not applicable | Embed in Mac app; Developer ID + notarization supports distribution outside Mac App Store |
| Share extension / Share target | Embedded native Share `.appex` | MSIX manifest/app integration | Ships with desktop installer; user/system enablement applies |
| Finder / Explorer | Embedded arm64 Finder `.appex` | Matching ARM64 or x64 shell DLL in MSIX | Ships with desktop installer; no browser-store listing |
| Chrome | Same JavaScript store ZIP | Same ZIP on x64 and ARM64 | Publish Chrome Web Store listing; user approves installation |
| Edge | Same JavaScript store ZIP | Same ZIP on x64 and ARM64 | Recommend Edge Add-ons listing; user approves installation |
| Firefox | Not presently built/tested | Not presently built/tested | Separate compatibility/testing and Mozilla signing if added later |

Safari can be bundled in the DMG's app; a separate App Store listing is optional for this direct-download route. Users must enable it in Safari Settings and grant website access. Finder/Sharing extensions may also require enablement in System Settings. Bundling and OS registration do not silently grant browser permissions.

Chrome Web Store is the supported consumer distribution route on Windows/macOS. Chrome's self-hosted extension route is restricted to enterprise policy-managed environments; Load Unpacked is for development. Edge documents external installation mechanisms too, but store distribution is the recommended consumer route. Do not force enterprise policy, alter browser profiles, or promise silent activation as part of a consumer installer. The existing app-managed unpacked Chromium resources are useful for development; their presence does not turn a ZIP into a publicly approved browser extension.

Build store upload packages from the Mac checkout:

```sh
python3 script/package_browser_extension.py
python3 -m unittest tests.test_browser_release
```

Use `dist/browser-extensions/Describe-with-Vidi-Studio-Chrome.zip` for Chrome Web Store and `Describe-with-Vidi-Studio-Edge.zip` for Edge Add-ons. They are architecture-independent upload ZIPs, not double-click browser installers. Register publisher accounts; provide icons/screenshots, accurate description, privacy/support URLs and permission/data-use declarations; upload, test the store version with the installed desktop handoff, then submit for review. The browser stores manage signing for their distributed extensions; a Windows code-signing certificate is not needed for these upload ZIPs. Keep each published extension ID stable and use the existing listing for future updates. Preserve any private extension signing keys outside source control. The browser release has its own manifest version; bump only when browser code/permissions/handoff changes, not merely for a desktop rebuild. Current browser manifest: 1.0.349.

## GitHub release checklist

1. Set the common desktop version using `python3 script/sync_version.py --bump` for future app changes. Build and replace installed copies as required by AGENTS.md. The current artifacts use the updated 1.0.350/build 350 sources. The previous 1.0.349 desktop release artifacts were replaced; the independent browser release remains 1.0.349.
2. Complete `docs/ffmpeg-distribution.md`: exact corresponding source/build scripts and notices for the bundled media binaries/dependencies, plus dependency/font license review. Current packaging does not establish that these public redistribution obligations are complete.
3. Validate the final signed/notarized downloads on clean machines. Verify the intended macOS/Windows minimums, packaged engine/media, extension handoff and actual installed version. Keep all signing keys, credentials, user projects and tokens out of artifacts. Publisher OAuth client configuration is separate from Gemini keys; confirm Google consent/YouTube scope production readiness before promising those features to all users.
4. Draft a release at **GitHub repository > Releases > Draft a new release**. Choose the intended source commit/tag, for example `v1.0.350`. Attach the notarized arm64 DMG and signed x64/ARM64 MSIX ZIPs with dependencies. Add `SHA256SUMS.txt`, installation instructions, supported OS/CPU versions, release notes, and corresponding-source/notices assets as required. Identify any evaluation-only certificate requirements plainly.
5. Browser store ZIPs may be attached for developers, but link customers to published Chrome/Edge listings. Safari/Finder/Share are already inside the Mac app, and Windows Explorer/Share inside MSIX.
6. Publish only after trust, install, license/source, and clean-machine checks are complete. Never upload PFX/P12/private keys, notarization credentials or API tokens. Keep the release draft if prerequisites remain unresolved.

## Primary documentation

- [Apple: Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Apple: create distribution-signed Mac code](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
- [Apple: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: distribute Safari web extensions outside the Mac App Store](https://developer.apple.com/documentation/safariservices/distributing-your-safari-web-extension)
- [Microsoft: self-signed package certificates](https://learn.microsoft.com/windows/msix/package/create-certificate-package-signing)
- [Microsoft: MSIX signing guide](https://learn.microsoft.com/windows/msix/package/sign-msix-package-guide)
- [Microsoft: Windows code-signing options](https://learn.microsoft.com/windows/apps/package-and-deploy/code-signing-options)
- [Chrome: extension distribution](https://developer.chrome.com/docs/extensions/how-to/distribute)
- [Microsoft Edge: alternate extension distribution](https://learn.microsoft.com/microsoft-edge/extensions/developer-guide/alternate-distribution-options)

- [Apple: create a self-signed certificate for local experiments](https://support.apple.com/guide/keychain-access/kyca8916/mac)
- [GitHub: manage and draft releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository?tool=webui)
