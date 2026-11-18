import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SavedFeeds

struct RedditParserTests {
    @Test func readsEveryKindOfSavedItem() throws {
        let page = try RedditParser.page(from: Data(Fixtures.redditListing.utf8))
        #expect(page.next == "t3_next")
        #expect(page.posts.map(\.id) == ["t3_img", "t3_gal", "t3_vid", "t3_self", "t3_link", "t3_xpost", "t1_com"])

        let image = page.posts[0]
        #expect(image.community == "r/pics")
        #expect(image.title == "A photo")
        #expect(image.text == nil)
        #expect(image.link == nil)
        #expect(image.media == [Media(kind: .image, image: URL(string: "https://preview.redd.it/abc.jpg?width=1080&s=x"), video: nil, width: 1080, height: 1350)])
        #expect(image.permalink.absoluteString == "https://www.reddit.com/r/pics/comments/img/a_photo/")

        let gallery = page.posts[1]
        #expect(gallery.media.map(\.kind) == [.loop, .image])
        #expect(gallery.media[0].video?.absoluteString == "https://preview.redd.it/m2.gif?format=mp4")

        let video = page.posts[2]
        #expect(video.media.first?.kind == .video)
        #expect(video.media.first?.video?.absoluteString == "https://v.redd.it/vid/HLSPlaylist.m3u8")
        #expect(video.media.first?.image?.absoluteString == "https://preview.redd.it/vid.jpg")

        let text = page.posts[3]
        #expect(text.text == "How do I **do** this?")
        #expect(text.media.isEmpty)
        #expect(text.link == nil)

        let link = page.posts[4]
        #expect(link.link?.absoluteString == "https://example.com/story")
        #expect(link.media.count == 1)

        let crosspost = page.posts[5]
        #expect(crosspost.title == "Seen elsewhere")
        #expect(crosspost.media.first?.kind == .loop)

        let comment = page.posts[6]
        #expect(comment.isComment)
        #expect(comment.title == "Question")
        #expect(comment.text == "Use async let.")
    }

    @Test func rejectsSomethingThatIsntAListing() {
        #expect(throws: FeedError.unreadable) { try RedditParser.page(from: Data("<html></html>".utf8)) }
    }

    @Test func feedLinkNeedsItsToken() {
        #expect(RedditSource.feedLink(from: "https://www.reddit.com/user/me/feed=") == nil)
        #expect(RedditSource.feedLink(from: "https://www.reddit.com/user/me/saved.json?feed=&user=me") == nil)
        #expect(RedditSource.feedLink(from: "https://example.com/saved.json?feed=abc") == nil)
        #expect(RedditSource.feedLink(from: " https://old.reddit.com/user/me/saved.json?feed=abc&user=me\n")?.host() == "old.reddit.com")
    }

    @Test func feedLinkGetsPaging() throws {
        let rss = URL(string: "https://www.reddit.com/user/me/saved.rss?feed=abc&user=me&limit=25")!
        let url = RedditSource.pageURL(rss, after: "t3_x")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/user/me/saved.json")
        #expect(components.queryItems == [
            URLQueryItem(name: "feed", value: "abc"),
            URLQueryItem(name: "user", value: "me"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "raw_json", value: "1"),
            URLQueryItem(name: "after", value: "t3_x"),
        ])

        let bare = RedditSource.pageURL(URL(string: "https://www.reddit.com/saved?feed=abc&user=me")!, after: nil)
        #expect(bare.absoluteString == "https://www.reddit.com/saved.json?feed=abc&user=me&limit=100&raw_json=1")
    }
}

struct InstagramParserTests {
    @Test func readsPhotosVideosAndCarousels() throws {
        let page = try InstagramParser.page(from: Data(Fixtures.instagramSaved.utf8))
        #expect(page.next == "QVFE123")
        #expect(page.posts.map(\.id) == ["ig_ABC", "ig_VID", "ig_CAR"])

        let photo = page.posts[0]
        #expect(photo.mediaID == "3141")
        #expect(page.posts[1].mediaID == "3142")
        #expect(photo.author == "photog")
        #expect(photo.text == "Sunset")
        #expect(photo.score == 120)
        #expect(photo.permalink.absoluteString == "https://www.instagram.com/p/ABC/")
        #expect(photo.media == [Media(kind: .image, image: URL(string: "https://scontent.cdninstagram.com/big.jpg"), video: nil, width: 1080, height: 1350)])

        let reel = page.posts[1]
        #expect(reel.text == nil)
        #expect(reel.media.first?.kind == .video)
        #expect(reel.media.first?.video?.absoluteString == "https://scontent.cdninstagram.com/v.mp4")

        let carousel = page.posts[2]
        #expect(carousel.media.map(\.kind) == [.image, .video])
    }

    @Test func stopsWhenNothingMoreIsAvailable() throws {
        let page = try InstagramParser.page(from: Data(#"{"items":[],"more_available":false,"next_max_id":123,"status":"ok"}"#.utf8))
        #expect(page.posts.isEmpty)
        #expect(page.next == nil)
    }

    @Test func spotsAnExpiredSession() {
        #expect(throws: FeedError.signedOut) {
            try InstagramParser.page(from: Data(#"{"message":"login_required","status":"fail"}"#.utf8))
        }
    }
}

struct SafariHandoffTests {
    @Test func cookiesKeepTheirAttributes() throws {
        // HTTPCookie caps expiry at 400 days out, so stay inside that.
        let expiry = (Date.now.timeIntervalSince1970 + 30 * 86_400).rounded()
        let json = #"{"cookies":{"instagram":[{"name":"sessionid","value":"abc","domain":".instagram.com","path":"/","secure":true,"httpOnly":true,"expirationDate":\#(expiry)},{"name":"rur","value":"x","domain":"www.instagram.com","path":"/","secure":false,"httpOnly":false}]},"userAgent":"Safari"}"#
        let handoff = try JSONDecoder().decode(SharedSessions.Handoff.self, from: Data(json.utf8))
        #expect(handoff.userAgent == "Safari")
        let cookies = try #require(handoff.cookies["instagram"]).compactMap(\.httpCookie)
        #expect(cookies.count == 2)
        #expect(cookies[0].name == "sessionid" && cookies[0].domain == ".instagram.com")
        #expect(cookies[0].isSecure && cookies[0].isHTTPOnly)
        #expect(abs((cookies[0].expiresDate?.timeIntervalSince1970 ?? 0) - expiry) < 1)
        #expect(cookies[1].expiresDate == nil && !cookies[1].isSecure)
    }
}

struct CommentParserTests {
    @Test func redditThreadsWithMoreStubs() throws {
        let json = #"""
        [{"kind":"Listing","data":{"children":[{"kind":"t3","data":{"name":"t3_p","title":"Post"}}]}},
         {"kind":"Listing","data":{"children":[
           {"kind":"t1","data":{"name":"t1_a","author":"ann","body":"Top **one**","score":12,"created_utc":1700000000,"is_submitter":true,
             "replies":{"kind":"Listing","data":{"children":[
               {"kind":"t1","data":{"name":"t1_b","author":"bob","body":"Reply","score":3,"created_utc":1700000100,"replies":""}},
               {"kind":"more","data":{"count":4,"children":["x","y"]}}]}}}},
           {"kind":"t1","data":{"name":"t1_c","author":"cat","body":"Top two","score":-2,"created_utc":1700000200,"replies":""}},
           {"kind":"more","data":{"count":17,"children":["z"]}}]}}]
        """#
        let page = try RedditComments.page(from: Data(json.utf8))
        #expect(page.comments.map(\.id) == ["t1_a", "t1_c"])
        #expect(page.more == 17)
        #expect(page.next == nil)
        let top = page.comments[0]
        #expect(top.isSubmitter && top.score == 12 && top.text == "Top **one**")
        #expect(top.replies.map(\.author) == ["bob"])
        #expect(top.moreReplies == 4)
        #expect(page.comments[1].replies.isEmpty)
    }

    @Test func instagramCommentsPageAndReplies() throws {
        let json = #"{"comments":[{"pk":"111","text":"Nice","created_at":1700000000,"user":{"username":"ann"},"comment_like_count":5,"child_comment_count":3,"preview_child_comments":[{"pk":222,"text":"Agreed","created_at":1700000100,"user":{"username":"bob"}}]},{"pk":"333","text":"Wow","user":{"username":"cat"}}],"comment_count":48,"has_more_comments":false,"has_more_headload_comments":true,"next_min_id":"{\"cursor\":1}","status":"ok"}"#
        let page = try InstagramComments.page(from: Data(json.utf8))
        #expect(page.comments.map(\.id) == ["111", "333"])
        #expect(page.next == #"{"cursor":1}"#)
        #expect(page.total == 48)
        #expect(page.comments[0].replies.map(\.id) == ["222"])
        #expect(page.comments[0].moreReplies == 2)

        let replies = try InstagramComments.replies(from: Data(#"{"child_comments":[{"pk":"444","text":"Later","user":{"username":"dan"}}],"has_more_tail_child_comments":false,"status":"ok"}"#.utf8))
        #expect(replies.comments.map(\.author) == ["dan"])
        #expect(replies.next == nil)
    }
}

enum Fixtures {
    static let redditListing = #"""
    {"kind":"Listing","data":{"after":"t3_next","children":[
      {"kind":"t3","data":{"name":"t3_img","permalink":"/r/pics/comments/img/a_photo/","created_utc":1700000000.0,"author":"alice","subreddit_name_prefixed":"r/pics","title":"A photo","selftext":"","url":"https://i.redd.it/abc.jpg","is_self":false,"post_hint":"image","score":1234,"num_comments":56,"edited":false,"media":null,"secure_media":null,
        "preview":{"enabled":true,"images":[{"source":{"url":"https://preview.redd.it/abc.jpg?width=1080&s=x","width":1080,"height":1350},"resolutions":[],"variants":{}}]}}},
      {"kind":"t3","data":{"name":"t3_gal","permalink":"/r/cats/comments/gal/cats/","created_utc":1700000100,"author":"bob","subreddit_name_prefixed":"r/cats","title":"Cats","selftext":"","url":"https://www.reddit.com/gallery/gal","is_self":false,"is_gallery":true,"score":10,"num_comments":2,"edited":1700000200.0,
        "gallery_data":{"items":[{"media_id":"m2","id":2},{"media_id":"m1","id":1}]},
        "media_metadata":{"m1":{"status":"valid","e":"Image","m":"image/jpg","s":{"u":"https://preview.redd.it/m1.jpg","x":800,"y":600}},"m2":{"status":"valid","e":"AnimatedImage","m":"image/gif","s":{"gif":"https://i.redd.it/m2.gif","mp4":"https://preview.redd.it/m2.gif?format=mp4","x":400,"y":400}}}}},
      {"kind":"t3","data":{"name":"t3_vid","permalink":"/r/videos/comments/vid/clip/","created_utc":1700000200,"author":"carol","subreddit_name_prefixed":"r/videos","title":"Clip","selftext":"","url":"https://v.redd.it/vid","is_self":false,"is_video":true,"post_hint":"hosted:video","score":5,"num_comments":0,
        "secure_media":{"reddit_video":{"hls_url":"https://v.redd.it/vid/HLSPlaylist.m3u8","fallback_url":"https://v.redd.it/vid/DASH_720.mp4","width":1280,"height":720,"is_gif":false}},
        "preview":{"images":[{"source":{"url":"https://preview.redd.it/vid.jpg","width":1280,"height":720}}]}}},
      {"kind":"t3","data":{"name":"t3_self","permalink":"/r/swift/comments/self/question/","created_utc":1700000300,"author":"dan","subreddit_name_prefixed":"r/swift","title":"Question","selftext":"How do I **do** this?","url":"https://www.reddit.com/r/swift/comments/self/question/","is_self":true,"score":3,"num_comments":4}},
      {"kind":"t3","data":{"name":"t3_link","permalink":"/r/news/comments/link/story/","created_utc":1700000350,"author":"erin","subreddit_name_prefixed":"r/news","title":"Story","selftext":"","url":"https://example.com/story","is_self":false,"post_hint":"link","score":99,"num_comments":12,
        "preview":{"images":[{"source":{"url":"https://external-preview.redd.it/story.jpg","width":1200,"height":630}}]}}},
      {"kind":"t3","data":{"name":"t3_xpost","permalink":"/r/gifs/comments/xpost/seen_elsewhere/","created_utc":1700000370,"author":"gina","subreddit_name_prefixed":"r/gifs","title":"Seen elsewhere","selftext":"","url":"/r/funny/comments/orig/","score":1,"num_comments":0,
        "crosspost_parent_list":[{"name":"t3_orig","permalink":"/r/funny/comments/orig/","created_utc":1690000000,"url":"https://v.redd.it/orig","is_self":false,
          "media":{"reddit_video":{"hls_url":"https://v.redd.it/orig/HLSPlaylist.m3u8","width":480,"height":480,"is_gif":true}}}]}},
      {"kind":"t1","data":{"name":"t1_com","permalink":"/r/swift/comments/self/question/com/","created_utc":1700000400,"author":"frank","subreddit_name_prefixed":"r/swift","link_title":"Question","body":"Use async let.","score":7}},
      {"kind":"t3","data":{"name":"t3_broken","created_utc":"not a number"}}
    ]}}
    """#

    static let instagramSaved = #"""
    {"items":[
      {"media":{"pk":3141,"id":"3141_99","code":"ABC","media_type":1,"taken_at":1700000000,"original_width":1080,"original_height":1350,
        "image_versions2":{"candidates":[{"url":"https://scontent.cdninstagram.com/small.jpg","width":320,"height":400},{"url":"https://scontent.cdninstagram.com/big.jpg","width":1080,"height":1350}]},
        "caption":{"text":"Sunset"},"user":{"username":"photog","full_name":"P"},"like_count":120,"comment_count":4}},
      {"media":{"pk":"3142","code":"VID","media_type":2,"product_type":"clips","taken_at":1700000100,"original_width":720,"original_height":1280,
        "image_versions2":{"candidates":[{"url":"https://scontent.cdninstagram.com/poster.jpg","width":720,"height":1280}]},
        "video_versions":[{"type":101,"url":"https://scontent.cdninstagram.com/v.mp4","width":720,"height":1280}],
        "caption":null,"user":{"username":"reels"},"comment_count":0}},
      {"media":{"code":"CAR","media_type":8,"taken_at":1700000200,"user":{"username":"carousel"},"caption":{"text":"Two"},
        "carousel_media":[
          {"media_type":1,"image_versions2":{"candidates":[{"url":"https://scontent.cdninstagram.com/c1.jpg","width":1080,"height":1080}]}},
          {"media_type":2,"image_versions2":{"candidates":[{"url":"https://scontent.cdninstagram.com/c2.jpg","width":1080,"height":1080}]},"video_versions":[{"url":"https://scontent.cdninstagram.com/c2.mp4","width":1080,"height":1080}]}]}},
      {"media":{"code":42}}
    ],"num_results":4,"more_available":true,"next_max_id":"QVFE123","status":"ok"}
    """#
}

struct FeedZoomTests {
    @Test func stepsClampAtTheEnds() {
        #expect(FeedZoom.zoomedIn(from: 1) == 1.1)
        #expect(FeedZoom.zoomedOut(from: 1) == 0.9)
        #expect(FeedZoom.zoomedIn(from: 2) == 2)
        #expect(FeedZoom.zoomedOut(from: 0.7) == 0.7)
    }

    @Test func zoomScalesFeedText() throws {
        func size(at zoom: Double) -> CGSize {
            let text = Text("Saved post").zoomedFont(.body).fixedSize().environment(\.feedZoom, zoom)
            return ImageRenderer(content: text).nsImage?.size ?? .zero
        }
        let normal = size(at: 1), double = size(at: 2)
        #expect(normal.height > 0)
        #expect(double.height > normal.height * 1.7)
        #expect(double.width > normal.width * 1.7)
    }
}

struct EscapeKeyTests {
    final class Count { var value = 0 }

    /// Posts a real Esc key-down to a window holding EscapeKey and lets the run loop deliver it.
    private func pressEsc(active: Bool) async throws -> (handled: Int, window: NSWindow) {
        let count = Count()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Color.clear.background(EscapeKey(isActive: active) { count.value += 1 }))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(200))
        let esc = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ))
        NSApp.postEvent(esc, atStart: false)
        try await Task.sleep(for: .milliseconds(300))
        window.orderOut(nil)
        return (count.value, window)
    }

    @Test func escCallsTheActionWhileActive() async throws {
        #expect(try await pressEsc(active: true).handled == 1)
    }

    @Test func escIsLeftAloneWhenInactive() async throws {
        #expect(try await pressEsc(active: false).handled == 0)
    }
}
