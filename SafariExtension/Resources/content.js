// Every reddit.com / instagram.com page load: ask the background script to pass the session on.
browser.runtime.sendMessage({ type: "sync" });
