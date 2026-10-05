import { redirects, resolve, siteOf } from "./shared.js";

// The opt-in redirect's question from `redirect.js`: the `rfc://` link to send a
// page to, or null to leave it in Safari.
browser.runtime.onMessage.addListener(async ({ redirect: url }) => {
  const site = siteOf(url);
  if (!site || !(await redirects(site))) {
    return null;
  }
  const { link, documentPage } = await resolve(url);
  return documentPage ? link : null;
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
