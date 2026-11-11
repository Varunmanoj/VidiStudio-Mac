# YouTube publisher setup

Target project: `gen-lang-client-0157645022` (Paid Gemini API, number 294575602420).
YouTube Data API v3 was confirmed enabled. A separate key named **VidiStudio YouTube Data API** is restricted to `youtube.googleapis.com`; do not reuse Gemini keys.

Use the existing Desktop app clients named **VidiStudio Mac** and **VidiStudio Windows** under Google Auth Platform > Clients (see the dated status below). Configure VidiStudio branding, publisher contact, application home page, privacy policy and terms using the publisher's verified domains. Add `openid`, `email`, `profile`, `youtube.readonly` and `youtube.force-ssl` scopes to Data Access. During testing, add the actual test users. Download the client JSON for each platform.

Supply each platform's ignored `Config/youtube-release.json`:

```json
{"apiKey":"YOUTUBE_ONLY_APPLICATION_KEY","clientID":"DESKTOP_CLIENT_ID","clientSecret":"DESKTOP_CLIENT_SECRET"}
```

Desktop OAuth clients are public clients; client metadata and the application API key are distributed in the app. User refresh tokens belong only in Keychain/Credential Manager and must never be added to this file. Mac's engine bundle phase and Windows' content items copy this release configuration into the app. A build without publisher configuration displays a configuration message; there is no fabricated sign-in.

For public distribution, submit the external OAuth consent configuration for Google's verification with screenshots/video of system-browser sign-in, account/channel selection, private-video rejection, caption selection/import, and local sign-out versus account-wide revocation. Explain that `youtube.force-ssl` is needed for `captions.list` and `captions.download`; the app does not upload, edit or delete YouTube videos. Read-only channel browsing continues to use the Data API. Obtain Google's approval separately from local test sign-in. Testing-mode token expiry and unverified-user limits are not a production release approval.

Signed-out metadata requests share the publisher key's YouTube quota. Upload and playlist browsing uses pagination; caption requests are on demand. No tokens are sent to Gemini or the Python processing engine. The application cannot obtain private video access for Gemini through OAuth. Unlisted videos are attempted as requested; Google currently documents only public YouTube URLs for Gemini, so record actual live results separately.

Validation still needed with real OAuth clients: account/channel selection (including Brand Accounts), scopes granted/denied, refresh/revocation, caption edit permissions and automatic tracks, and live Mac/Windows screen-reader interaction. YouTube Studio delegated access may not be available through the API; use a channel-owner connection when necessary.

Google OAuth client downloads are ignored under both the expected Google API Clients folder and the actual Google Api Clients folder (including a trailing space). Runtime account revocation responses clear the affected saved connections. Startup maintenance expires fetched video snapshots and downloaded caption source caches after 30 days in the configured library; saved editable transcripts remain project content until explicitly removed.


## OAuth configuration status — 11 November 2026

The existing project is **External / In production**. Google has verified and published the **VidiStudio** name and existing application logo; the console confirms that branding is being shown to users. Branding is project-wide, shared by the desktop clients.

- Application home: https://vidistudio.varunmanojkumar.in/
- Privacy policy: https://vidistudio.varunmanojkumar.in/privacy
- Product documentation: https://vidistudio.varunmanojkumar.in/docs
- Authorised domain: `varunmanojkumar.in`
- Support and developer contact: `varunmanoj2002@gmail.com` (the existing configured contact).
- Terms of Service: not provided; no corresponding policy page was identified or invented.
- Desktop clients remain **VidiStudio Mac** and **VidiStudio Windows**. Both ignored source release configurations match their respective existing client IDs. The installed Mac `Contents/Resources/youtube-config.json` also matches the Mac client. No client credentials were rotated or recreated.
- Saved scopes match both apps: `openid`, `https://www.googleapis.com/auth/userinfo.email` (the `email` alias), `https://www.googleapis.com/auth/userinfo.profile` (the `profile` alias), `https://www.googleapis.com/auth/youtube.readonly`, and `https://www.googleapis.com/auth/youtube.force-ssl`. Google classifies the two YouTube scopes as **sensitive**, with no restricted scopes declared.

**Sensitive-scope review is not submitted or approved.** The user explicitly deferred submission/review. Production status and verified branding do not remove the unverified-app warning or the lifetime 100-user cap while these scopes remain unapproved. The existing utility client **Codex Google Cloud MCP Desktop** is also in this project and was left untouched. Google's demo field asks for all clients assigned to the project; address that existing client when preparing review, rather than silently deleting it or claiming it is covered by a desktop-only recording.

### Prepared scope justification (895 characters)

VidiStudio is a local video-accessibility editor for macOS and Windows. Users optionally connect Google accounts to browse their YouTube channels, uploads and playlists and import captions as editable local transcripts. youtube.readonly is used for channels.list, playlistItems.list, playlists.list and videos.list; API-key requests cannot identify the signed-in user's library. youtube.force-ssl is used only for captions.list and captions.download (GET) on videos the user has permission to edit. Google does not accept youtube.readonly for these caption methods; youtubepartner is inappropriate for this app. VidiStudio does not upload, edit or delete YouTube videos, ratings, comments or captions. OAuth tokens stay in macOS Keychain or Windows Credential Manager, are not sent to Gemini, and users can sign out locally or revoke access. Imported caption text is reviewed and edited locally.

The console disables Save for this justification until a valid demonstration-video URL is supplied. This paragraph is retained locally for the later submission; it is not a saved Google review request. Record the real English system-browser consent flow with the app name and client ID visible, channel/video browsing, and caption import, covering the required clients. Use an unlisted YouTube video; do not substitute an unrelated video or the website's simulated sound demo. Then save the justification/video and complete Verification centre > Prepare for verification. Do not include keys, refresh tokens, or passwords in the recording or review notes.

Current Google references: [branding](https://support.google.com/cloud/answer/15549049), [production readiness](https://developers.google.com/identity/protocols/oauth2/production-readiness/overview), [sensitive-scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification), [caption download authorization](https://developers.google.com/youtube/data/reference/rest/v3/captions/download).
