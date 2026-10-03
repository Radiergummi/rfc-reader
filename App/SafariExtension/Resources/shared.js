// What the background script and the popup share (#194).

// Which RFC the page at `url` is, as the app's extension handler reads it with
// RFCKit's RFCLink: `{ link: "rfc://…", documentPage: true }`, or `{}` for a page
// that names none. The handler is the one place a URL is matched, so the
// extension, the share sheet and the app agree on what an RFC's URL is.
//
// A tab's URL is undefined on any site outside the extension's host permissions,
// so those never reach the handler.
export async function resolve(url) {
  if (!url) {
    return {};
  }
  try {
    // Safari ignores the application ID and talks to the extension's own handler.
    const reply = await browser.runtime.sendNativeMessage("application.id", { url });
    return reply ?? {};
  } catch (error) {
    console.error("RFC Reader could not read the page's URL", error);
    return {};
  }
}

// The site the opt-in names for `url`: the RFC Editor with or without `www.`, or
// Datatracker; null for any other.
export function siteOf(url) {
  let host;
  try {
    host = new URL(url).hostname;
  } catch {
    return null;
  }
  switch (host) {
    case "rfc-editor.org":
    case "www.rfc-editor.org":
      return "rfc-editor.org";
    case "datatracker.ietf.org":
      return host;
    default:
      return null;
  }
}

const key = (site) => `redirect:${site}`;

// Whether a navigation to an RFC on `site` goes to the app. Off until it is turned
// on in the popup, per site: someone without the corpus downloaded may still want
// the web page.
export async function redirects(site) {
  const stored = await browser.storage.local.get(key(site));
  return stored[key(site)] === true;
}

export async function setRedirects(site, on) {
  if (on) {
    await browser.storage.local.set({ [key(site)]: true });
  } else {
    await browser.storage.local.remove(key(site));
  }
}
