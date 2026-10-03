import { redirects, resolve, siteOf } from "./shared.js";

// The opt-in redirect. A navigation to a document's own page, on a site where it is
// turned on, goes to the app instead, at the same section. A page about the
// document, such as its errata or history, stays in Safari, as does anything that
// names no RFC, an Internet-Draft among them.
//
// Safari asks before it opens the app, each time; the popup says so.
browser.webNavigation.onBeforeNavigate.addListener(async ({ tabId, frameId, url }) => {
  if (frameId !== 0) {
    return;
  }
  const site = siteOf(url);
  if (!site || !(await redirects(site))) {
    return;
  }
  const { link, documentPage } = await resolve(url);
  if (link && documentPage) {
    await browser.tabs.update(tabId, { url: link });
  }
});

// The toolbar button is enabled on a page that names an RFC, and only there.
async function updateAction(tabId, url) {
  const { link } = await resolve(url);
  if (link) {
    await browser.action.enable(tabId);
  } else {
    await browser.action.disable(tabId);
  }
}

browser.tabs.onUpdated.addListener((tabId, change, tab) => {
  if (change.url || change.status === "complete") {
    updateAction(tabId, tab.url);
  }
});

browser.tabs.onActivated.addListener(async ({ tabId }) => {
  try {
    const tab = await browser.tabs.get(tabId);
    await updateAction(tabId, tab.url);
  } catch {
    // The tab closed before it could be read; there is no button left to update.
  }
});
