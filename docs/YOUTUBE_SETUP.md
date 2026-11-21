# YouTube Data API release setup

The desktop apps use a publisher-provided YouTube Data API v3 key to fetch details for public and unlisted video links. This key is separate from the user's Gemini API key.

Place the restricted YouTube Data API key in the gitignored `Config/youtube-release.json` in each desktop checkout. The file needs one property, `apiKey`. Packaging produces a `youtube-config.json` resource with only that property. Restrict the key to YouTube Data API v3 and monitor its usage and quota.

To verify a packaged build, paste a public link and an unlisted link into New Project and fetch their previews. Open a project and refresh its saved details in the editor. Confirm that private or unavailable links return an availability message. Use an original video file to work on a private video.
