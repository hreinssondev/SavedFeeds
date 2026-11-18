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

## How it works

- `Core/RedditSource.swift`: the private feed link, or `/user/<you>/saved.json` with the reddit.com session.
- `Core/InstagramSource.swift`: `/api/v1/feed/saved/posts/`, the endpoint instagram.com's Saved page uses, with the web session.
- Sign-ins run in a web view (`UI/SignInSheet.swift`). Feed requests reuse its cookies (`Core/WebSession.swift`).
- The feed link is kept in the Keychain. The last loaded posts are cached in Application Support.

## Caveats

Instagram has no official API for saved posts. The Instagram feed is unofficial, against Instagram's terms, and may break or get the account flagged. Keep this a personal build.
