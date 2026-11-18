// Reads the session cookies (HttpOnly, so the page itself can't) and hands them to the app.

const sessions = [
    { service: "instagram", url: "https://www.instagram.com/", name: "sessionid" },
    { service: "reddit", url: "https://www.reddit.com/", name: "reddit_session" },
];

let lastSent = "";

async function sync() {
    const found = {};
    for (const { service, url, name } of sessions) {
        const cookie = await browser.cookies.get({ url, name });
        if (cookie?.value) found[service] = cookie.value;
    }
    const payload = JSON.stringify(found);
    if (payload === "{}" || payload === lastSent) return;
    await browser.runtime.sendNativeMessage("com.hreinsson.SavedFeeds", { sessions: found });
    lastSent = payload;
}

browser.runtime.onMessage.addListener((message) => {
    if (message?.type === "sync") sync();
});
