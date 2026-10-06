# The Safari extension asks the app which RFC a page is

*Decided October 2026 (issue #194).*
`App/SafariExtension` is a Safari Web Extension, embedded in the app on macOS and iOS (`RFCReaderSafari` in `project.yml`, bundle ID `me.mazetti.rfc-reader.safari`).
It offers rather than forces, as the issue asks.
Someone reading on a device without the corpus may still want the web page:

- **A toolbar button**, enabled on a page that names an RFC, opens it in the app at the page's section.
- **A per-site opt-in**, off by default: "Always open RFCs from rfc-editor.org in RFC Reader", and the same for Datatracker. With it on, a document's own page on that site sends itself to the app: a content script, `redirect.js`, runs at `document_start` on the RFC Editor's `/rfc/` and Datatracker's `/doc/` pages, asks the background script for the page's `rfc://` link, and gets one only where the opt-in is on and the page is the document's own; then it calls `location.replace` with it. A page about the document, its info page, errata or history, stays in Safari, as does anything else, an Internet-Draft among them.

**One parser, in Swift.**
The script never matches a URL.
It sends the page's URL to the extension's native handler (`browser.runtime.sendNativeMessage`), which answers with `RFCLink(url:)`'s `rfc://` link and whether `RFCLink(documentPage:)` holds.
So the extension, the share sheet and the app agree on what an RFC's URL is, and RFCKit's tests cover every form the extension meets (`RFCLinkTests`).
`RFCLink` reads the last path component of an RFC Editor URL without any of its extensions, so the RFC Editor's PDF of a legacy RFC, `/rfc/pdfrfc/rfc2616.txt.pdf`, reads too.
And a number in a Datatracker path names an RFC only when it is spelled as one, `rfc19`: a draft's revision, a meeting and an IPR disclosure are numbered too, and a bare number would open RFC 19 for `/doc/draft-…/19/`.
The script stays small enough that there is little in it to test, and nothing runs it but Safari.

**The page navigates itself, not the background script.**
The first version redirected from the background script, on `webNavigation.onBeforeNavigate`, with `tabs.update` to the `rfc://` link.
Tried in Safari on the Mac, with access granted and the opt-in on, the page loaded in Safari regardless and the app never opened.
The toolbar button's `tabs.update`, sent from the popup on a click, does open the app.
Safari opens an app from a page's own navigation to a custom scheme, as any web page that hands off to an app does, so the content script navigates the page.
Redirect Web, a Safari extension that sends pages to apps, does the same through a page of its own (mshibanami/redirect-web, discussions #57 and #109).
It needs no `webNavigation` permission either, and declining Safari's prompt is expected to leave the page as it is rather than an empty tab.

**Safari's prompt is accepted.**
Safari asks "Open in RFC Reader?" before it follows an `rfc://` link, and there is no way around it from an extension.
A Universal Link would avoid it, but needs a domain the app is served from.
So the opt-in redirect is two steps, not one, and the popup says that Safari asks each time.

**Access to the three sites is granted from the popup.**
Safari grants a manifest's host permissions only when the user allows them.
Until then the extension cannot read a tab's URL there, and Safari sends it no `tabs.onUpdated` for that tab, so nothing disables its button.
Clicking the button on any such page, github.com included, brought up Safari's own prompt for access to that page's site, which the extension does not need.
So the popup offers "Allow on rfc-editor.org and Datatracker" while it lacks access to any of them, which calls `browser.permissions.request` with the manifest's `host_permissions` as the click's first call, the user gesture WebKit requires, and then draws itself again.
Whether Safari still asks for the page's own site on such a click is Safari's to decide and not yet seen.
The button is never disabled globally: a disabled button might not open the popup at all, and Safari's documentation does not say whether it would.

**It asks for no more than it needs:** `nativeMessaging`, `storage` for the opt-in, and host access to `rfc-editor.org`, `www.rfc-editor.org` and `datatracker.ietf.org`, so that Safari's permission prompt names exactly those sites.
`tools.ietf.org` is left out: it only redirects to Datatracker, and the button still works on the page it lands on.
The extension holds no data but the opt-in, and makes no connection of its own.
