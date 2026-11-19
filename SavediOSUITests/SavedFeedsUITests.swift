import XCTest

/// The iPhone app with the demo posts in Demo/ (no accounts needed): switching feeds by swiping and from the bar,
/// search from the ⋯ menu, layouts, and the open-in-app buttons. Screenshots are kept with the results.
final class SavedFeedsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        let demo = Bundle(for: Self.self).resourceURL!.appending(path: "Demo").path
        app.launchArguments = ["-demoData", demo, "-demoLayout", "full"]
    }

    private var reddit: XCUIElement { app.buttons["switcher.reddit"] }
    private var instagram: XCUIElement { app.buttons["switcher.instagram"] }

    func testStartsOnInstagramAndSwipesBetweenFeeds() {
        app.launch()
        XCTAssertTrue(instagram.waitForExistence(timeout: 10))
        XCTAssertTrue(instagram.isSelected, "Instagram comes first")
        keep("Instagram")

        app.swipeRight()
        XCTAssertTrue(reddit.wait(for: \.isSelected, toEqual: true, timeout: 5), "A swipe right goes to Reddit")
        XCTAssertTrue(app.staticTexts["Morning fog rolling through the Dolomites, Italy [OC] [4000x5000]"].waitForExistence(timeout: 5))
        keep("Reddit after a swipe")

        app.swipeLeft()
        XCTAssertTrue(instagram.wait(for: \.isSelected, toEqual: true, timeout: 5), "A swipe left goes back to Instagram")
    }

    func testTheBarSwitchesFeeds() {
        app.launch()
        XCTAssertTrue(reddit.waitForExistence(timeout: 10))
        reddit.tap()
        XCTAssertTrue(reddit.wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertFalse(instagram.isSelected)
        instagram.tap()
        XCTAssertTrue(instagram.wait(for: \.isSelected, toEqual: true, timeout: 5))
    }

    func testSearchIsInTheMenu() {
        app.launchArguments += ["-demoService", "reddit"]
        app.launch()
        XCTAssertFalse(app.textFields["search.field"].exists, "No search field until it's asked for")
        app.buttons["menu"].tap()
        app.buttons["Search"].tap()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("swift")
        XCTAssertTrue(app.staticTexts["What's the cleanest way to run work off the main actor in Swift 6.2?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Morning fog rolling through the Dolomites, Italy [OC] [4000x5000]"].exists)
        keep("Searching Reddit")

        app.buttons["Done Searching"].tap()
        XCTAssertFalse(field.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Morning fog rolling through the Dolomites, Italy [OC] [4000x5000]"].waitForExistence(timeout: 5))
    }

    func testRedditHasAGrid() {
        app.launchArguments += ["-demoService", "reddit"]
        app.launch()
        app.buttons["menu"].tap()
        XCTAssertTrue(app.buttons["Cards"].exists && app.buttons["Compact"].exists)
        app.buttons["Grid"].tap()
        XCTAssertTrue(app.staticTexts["r/AskReddit"].waitForExistence(timeout: 5), "Text posts are tiles with their subreddit")
        keep("Reddit grid")

        app.buttons["menu"].tap()
        app.buttons["Cards"].tap()
    }

    func testPostsOpenInTheirAppsRatherThanShare() {
        app.launch()
        XCTAssertTrue(app.buttons["Open in Instagram"].firstMatch.waitForExistence(timeout: 10))
        reddit.tap()
        XCTAssertTrue(app.buttons["Open in Reddit"].firstMatch.waitForExistence(timeout: 5))
    }

    func testTappingAPostOpensItWithItsComments() {
        app.launchArguments += ["-demoService", "reddit"]
        app.launch()
        let title = app.staticTexts["Morning fog rolling through the Dolomites, Italy [OC] [4000x5000]"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        XCTAssertTrue(app.staticTexts["Comments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open in Reddit"].firstMatch.exists)
        keep("Reddit post")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(reddit.waitForExistence(timeout: 5))
    }

    func testTheBarsFloatOverTheFeedAsItScrolls() {
        app.launch()
        XCTAssertTrue(instagram.waitForExistence(timeout: 10))
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(instagram.isHittable, "The feed bar stays over the posts")
        XCTAssertTrue(app.buttons["menu"].isHittable, "So does the ⋯ button")
        keep("Scrolled")
    }

    func testTheFeedRunsUnderTheBarAndItsEndClearsIt() {
        app.launchArguments += ["-demoService", "reddit", "-demoLayout", "grid"]
        app.launch()
        XCTAssertTrue(reddit.waitForExistence(timeout: 10))
        let last = app.staticTexts["Liquid Glass after a year: what I like and what still bugs me"]
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        for _ in 0..<3 { app.swipeUp() }
        // The bar's glass reaches a few points past its buttons.
        XCTAssertLessThanOrEqual(last.frame.maxY, reddit.frame.minY - 4, "The last post scrolls clear of the bar")
        keep("End of the Reddit grid")

        app.buttons["menu"].tap()
        app.buttons["Cards"].tap()
        app.swipeUp()
        keep("Reddit cards under the bar")
    }

    private func keep(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
