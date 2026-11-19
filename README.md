# SavedFeeds

Your saved Reddit and Instagram posts: side by side on the Mac, one feed at a time on iPhone.

## Build

```sh
xcodegen generate && open SavedFeeds.xcodeproj
```

Schemes: **SavedFeeds** (Mac) and **SavedFeedsiOS** (iPhone; pick your phone as the destination).

## iPhone

The iPhone app uses the Mac app's sign-ins: after a feed loads on the Mac, the Mac app saves that session to iCloud Keychain, and the iPhone app picks it up when it opens. Sessions are made on the Mac (Safari, passkeys) and copied to the phone; if one expires, sign in again on the Mac. The ⋯ menu has a sign-in on the phone itself as a backup (no passkeys there).

The feeds run to the top of the screen; a glass bar at the bottom switches between Reddit and Instagram (Instagram first), and so does a swipe sideways. Tap the feed you're on to go back to its top. On iPhone:

- **Feeds**: whole posts (Instagram like the Instagram app, Reddit as cards), a compact Reddit list, or a 3-across grid for either (Reddit's text posts become tiles in their subreddit's color). Pick in the ⋯ menu. Pull to refresh; older posts load as you scroll.
- **Posts**: tap one to open it with its comments: threads collapse with a tap, Reddit comments sort (Best, Top, New…), Instagram replies load in place. Tapping a comment count opens the post at its comments. The Reddit and Instagram buttons on posts open them in their apps.
- **Pictures**: tap one in a post for full screen: swipe between them, pinch or double-tap to zoom, swipe down to close, share or Save Image.
- **Search** (⋯ → Search) looks through titles, captions, authors, subreddits and flair, and can reach further back into older saved posts.
- **Links**: Reddit and Instagram links open their apps; other links open in Safari inside the app. Long-press a post to preview it, open it, share or copy its link.

For the iOS Simulator (no accounts there), a Debug build takes `-demoData <folder>` with `reddit.json` and `instagram.json` (the feed cache's format) to show sample posts; see `Core/DemoData.swift`. `SavediOSUITests` drives the app on those posts (switching feeds by swiping and from the bar, search, layouts, opening posts):

```sh
xcodebuild test -scheme SavedFeedsiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
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
- `Core/SitePage.swift`: both are fetched from a hidden tab on the site itself. Reddit blocks bare requests and Instagram bounces them, even with the session.
- `Core/InstagramSource.swift`: `/api/v1/feed/saved/posts/`, the endpoint instagram.com's Saved page uses, with the web session.
- Sign-ins run in a web view (`UI/SignInSheet.swift`) or come from Safari via the extension (`SafariExtension/`, `Core/SharedSessions.swift`, through an App Group). The hidden tabs share those cookies (`Core/WebSession.swift`).
- The feed link is kept in the Keychain. The last loaded posts are cached in Application Support.

## Caveats

Instagram has no official API for saved posts. The Instagram feed is unofficial, against Instagram's terms, and may break or get the account flagged. Keep this a personal build.
