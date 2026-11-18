// Copies Safari's cookies for each site (the session ones are HttpOnly, so the page itself can't) to the app.
// Instagram wants its whole set, not just the session cookie, and the app sends Safari's user agent along with them.

const sites = [
    { service: "instagram", domain: "instagram.com", session: "sessionid" },
    { service: "reddit", domain: "reddit.com", session: "reddit_session" },
];

let lastSent = "";

async function sync() {
    const cookies = {};
    for (const { service, domain, session } of sites) {
        const all = await browser.cookies.getAll({ domain });
        if (!all.some((cookie) => cookie.name === session)) continue;
        cookies[service] = all.map(({ name, value, domain, path, secure, httpOnly, expirationDate }) =>
            ({ name, value, domain, path, secure, httpOnly, expirationDate }));
    }
    if (Object.keys(cookies).length === 0) return;
    const handoff = JSON.stringify({ cookies, userAgent: navigator.userAgent });
    if (handoff === lastSent) return;
    await browser.runtime.sendNativeMessage("com.hreinsson.SavedFeeds", { handoff });
    lastSent = handoff;
}

browser.runtime.onMessage.addListener((message) => {
    if (message?.type === "sync") sync();
});
