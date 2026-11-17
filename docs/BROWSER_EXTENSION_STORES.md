# Describe with Vidi Studio

## Chrome Web Store and Microsoft Edge Add-ons listing

**Name** Describe with Vidi Studio

**Short description** Open a YouTube video from the current page or a link in the VidiStudio desktop editor.

**Description** Open a YouTube video in VidiStudio for Mac or Windows to work on its transcript, captions, or audio description. Choose Describe with Vidi Studio from the browser toolbar while watching a video, or choose it from the context menu on a YouTube video link anywhere on the web. VidiStudio opens the existing project for the video or imports it into a new project. Requires the VidiStudio desktop app.

**Category** Accessibility

**Single purpose** Open the YouTube video the user selects in the installed desktop editor.

**Permissions and privacy** The activeTab permission reads the active page URL when the user invokes the toolbar action. The contextMenus permission adds the page and link commands. Link validation runs locally. The extension hands the canonical YouTube video URL to the operating system using the registered VidiStudio protocol. It stores no history or credentials, injects no page scripts, loads no remote code, and sends no analytics. The desktop app handles import and video availability.

## Packaging and reviewer instructions

Run `python3 script/package_browser_extension.py` from the Mac checkout. The current `Describe-with-Vidi-Studio-Chrome.zip` and `Describe-with-Vidi-Studio-Edge.zip` in `dist/browser-extensions` have manifest.json at the archive root and use the desktop release version. Each build replaces both stable filenames and removes previous versioned VidiStudio extension ZIPs after verifying the replacements. Each contains the VidiStudio icons at 16, 32, 48 and 128 pixels. Extract a ZIP to a permanent folder and use Developer mode → Load unpacked in the target browser for local verification. Safari ships inside the signed VidiStudio Mac application. Enable Describe with Vidi Studio in Safari → Settings → Extensions.

With the desktop app installed, use Describe with Vidi Studio on a public video. Accept the external-app prompt and verify the editor shows that video. Repeat from a link on another site to verify the same project reopens. Repeat with a link to a channel or an unrelated site to hear the invalid-link message. Press Escape or choose Close. On a valid video, declining the browser prompt should leave the desktop library untouched.

The store screenshot is in [browser-extension-store/invalid-link.png](browser-extension-store/invalid-link.png). It shows the actual extension feedback and Close control. Use the 128-pixel PNG from the extension for the store icon. The product privacy page is [VidiStudio Privacy](https://vidistudio.varunmanojkumar.in/privacy).
