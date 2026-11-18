# SavedFeeds

Your saved Reddit and Instagram posts side by side. macOS now, iOS later (`Core/` is platform-neutral).

## Build

```sh
xcodegen generate && open SavedFeeds.xcodeproj
```

## Connect

**Reddit**, either:
1. Open [old.reddit.com/prefs/feeds](https://old.reddit.com/prefs/feeds/), copy the JSON link for your saved links, and paste it in Settings (⌘,). No API key needed.
2. Or click **Sign In…** in the Reddit column and log in on reddit.com.

**Instagram**: click **Sign In…** in the Instagram column and log in on instagram.com.

**Passkeys**: apps can't use passkeys for other sites in their web views; Apple reserves that for browsers. So sign in in Safari, and the bundled **SavedFeeds Session** Safari extension hands the session to the app:
1. Run SavedFeeds once. Then open Safari › Settings › Extensions (or SavedFeeds › Settings › Open Safari Extensions…).
2. Turn on **SavedFeeds Session** and allow it on reddit.com and instagram.com.
3. Visit reddit.com / instagram.com in Safari while signed in. SavedFeeds picks the session up right away.

Without the extension, you can paste the session cookie by hand (`reddit_session` / `sessionid`) under **Settings › Paste a session from Safari**.

## How it works

- `Core/RedditSource.swift`: the private feed link, or `/user/<you>/saved.json` with the reddit.com session.
- `Core/InstagramSource.swift`: `/api/v1/feed/saved/posts/`, the endpoint instagram.com's Saved page uses, with the web session.
- Sign-ins run in a web view (`UI/SignInSheet.swift`) or come from Safari via the extension (`SafariExtension/`, `Core/SharedSessions.swift`, through an App Group). Feed requests reuse those cookies (`Core/WebSession.swift`).
- The feed link is kept in the Keychain. The last loaded posts are cached in Application Support.

## Caveats

Instagram has no official API for saved posts. The Instagram feed is unofficial, against Instagram's terms, and may break or get the account flagged. Keep this a personal build.
