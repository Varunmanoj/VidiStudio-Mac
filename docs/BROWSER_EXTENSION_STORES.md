# Describe with Vidi Studio

## Chrome Web Store and Microsoft Edge Add-ons listing

**Name** Describe with Vidi Studio

**Short description** Open a YouTube video from the current page or a link in the VidiStudio desktop editor.

**Description** Open a YouTube video in VidiStudio for Mac or Windows to work on its transcript, captions, or audio description. Choose Describe with Vidi Studio from the browser toolbar while watching a video, or choose it from the context menu on a YouTube video link anywhere on the web. VidiStudio opens the existing project for the video or imports it into a new project. Requires the VidiStudio desktop app.

**Category** Accessibility

**Single purpose** Open the YouTube video the user selects in the installed desktop editor.

**Permissions and privacy** The activeTab permission reads the active page URL when the user invokes the toolbar action. The contextMenus permission adds the page and link commands. Link validation runs locally. For valid videos, the panel requests the title from YouTube’s public oEmbed endpoint using the canonical link, and loads the selected video’s thumbnail from i.ytimg.com. Both requests omit cookies and the referrer. The extension hands the canonical YouTube video URL to the operating system using the registered VidiStudio protocol. It stores no history or credentials, injects no page scripts, loads no remote code, and sends no analytics. The desktop app handles import and video availability.

## Packaging and reviewer instructions

Run `python3 script/package_browser_extension.py` from the Mac checkout. The current `Describe-with-Vidi-Studio-Chrome.zip` and `Describe-with-Vidi-Studio-Edge.zip` in `dist/browser-extensions` have manifest.json at the archive root and use the independent version in BrowserExtension/manifest.json. Advance this version when releasing changed browser resources or adapting to a changed desktop handoff. Packaging replaces changed ZIPs at both stable filenames and removes previous versioned VidiStudio extension ZIPs after verifying the replacements. Each contains the VidiStudio icons at 16, 32, 48 and 128 pixels. Extract a ZIP to a permanent folder and use Developer mode → Load unpacked in the target browser for local verification. Safari ships inside the signed VidiStudio Mac application. Enable Describe with Vidi Studio in Safari → Settings → Extensions.

The desktop app also delivers an unpacked edition for local automatic updates. Its additional alarms permission schedules a local version check. See the Projects Help topic for the app-managed folders. Store ZIPs retain their store update mechanism.

With the desktop app installed, use Describe with Vidi Studio on a public video. Check the selected video title and link, choose Describe with Vidi Studio in the centered panel and accept the external-app prompt and verify the editor shows that video. Repeat from a link on another site to verify the same project reopens. Repeat with a link to a channel or an unrelated site to hear the invalid-link message. Press Escape or choose Close. On a valid video, Cancel dismisses the panel before it sends a request to the desktop. Declining the subsequent browser prompt also leaves the desktop library untouched.

The store screenshots show the extension flyout with a detected video's title, thumbnail, link, and actions, as well as the feedback when no supported link is available. See [detected YouTube video](browser-extension-store/valid-youtube-flyout.png) and [invalid link](browser-extension-store/invalid-link.png). Use the 128-pixel PNG from the extension for the store icon. The product privacy page is [VidiStudio Privacy](https://vidistudio.varunmanojkumar.in/privacy).

Both stores use the same [small promotional tile](browser-extension-store/small-promotional-tile.png) at 440 × 280 and [large promotional tile](browser-extension-store/large-promotional-tile.png) at 1400 × 560. Chrome calls the large tile the marquee promotional image. Both screenshots are 1280 × 800.
