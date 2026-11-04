# YouTube publisher setup

Target project: `gen-lang-client-0157645022` (Paid Gemini API, number 294575602420).
YouTube Data API v3 was confirmed enabled. A separate key named **VidiStudio YouTube Data API** is restricted to `youtube.googleapis.com`; do not reuse Gemini keys.

Create Desktop app clients named **VidiStudio Mac** and **VidiStudio Windows** under Google Auth Platform > Clients. Configure VidiStudio branding, publisher contact, application home page, privacy policy and terms using the publisher's verified domains. Add `openid`, `email`, `profile`, `youtube.readonly` and `youtube.force-ssl` scopes to Data Access. During testing, add the actual test users. Download the client JSON for each platform.

Supply each platform's ignored `Config/youtube-release.json`:

```json
{"apiKey":"YOUTUBE_ONLY_APPLICATION_KEY","clientID":"DESKTOP_CLIENT_ID","clientSecret":"DESKTOP_CLIENT_SECRET"}
```

Desktop OAuth clients are public clients; client metadata and the application API key are distributed in the app. User refresh tokens belong only in Keychain/Credential Manager and must never be added to this file. Mac's engine bundle phase and Windows' content items copy this release configuration into the app. A build without publisher configuration displays a configuration message; there is no fabricated sign-in.

For public distribution, submit the external OAuth consent configuration for Google's verification with screenshots/video of system-browser sign-in, account/channel selection, private-video rejection, caption selection/import, and local sign-out versus account-wide revocation. Explain that `youtube.force-ssl` is needed for `captions.list` and `captions.download`; the app does not upload, edit or delete YouTube videos. Read-only channel browsing continues to use the Data API. Obtain Google's approval separately from local test sign-in. Testing-mode token expiry and unverified-user limits are not a production release approval.

Signed-out metadata requests share the publisher key's YouTube quota. Upload and playlist browsing uses pagination; caption requests are on demand. No tokens are sent to Gemini or the Python processing engine. The application cannot obtain private video access for Gemini through OAuth. Unlisted videos are attempted as requested; Google currently documents only public YouTube URLs for Gemini, so record actual live results separately.

Validation still needed with real OAuth clients: account/channel selection (including Brand Accounts), scopes granted/denied, refresh/revocation, caption edit permissions and automatic tracks, and live Mac/Windows screen-reader interaction. YouTube Studio delegated access may not be available through the API; use a channel-owner connection when necessary.

Google OAuth client downloads are ignored under both the expected Google API Clients folder and the actual Google Api Clients folder (including a trailing space). Runtime account revocation responses clear the affected saved connections. Startup maintenance expires fetched video snapshots and downloaded caption source caches after 30 days in the configured library; saved editable transcripts remain project content until explicitly removed.
