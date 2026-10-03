# The Safari extension asks the app which RFC a page is

*Decided October 2026 (issue #194).* `App/SafariExtension` is a Safari Web Extension, embedded in the app on macOS and iOS (`RFCReaderSafari` in `project.yml`, bundle ID `me.mazetti.rfc-reader.safari`). It offers rather than forces, as the issue asks. Someone reading on a device without the corpus may still want the web page:

- **A toolbar button**, enabled on a page that names an RFC, opens it in the app at the page's section.
- **A per-site opt-in**, off by default: "Always open RFCs from rfc-editor.org in RFC Reader", and the same for Datatracker. With it on, a navigation to a document's own page on that site goes to the app instead (`webNavigation.onBeforeNavigate`, then the tab is sent to the `rfc://` link). A page about the document, its info page, errata or history, stays in Safari, as does anything else, an Internet-Draft among them.

**One parser, in Swift.** The script never matches a URL. It sends the page's URL to the extension's native handler (`browser.runtime.sendNativeMessage`), which answers with `RFCLink(url:)`'s `rfc://` link and whether `RFCLink(documentPage:)` holds. So the extension, the share sheet and the app agree on what an RFC's URL is, and RFCKit's tests cover every form the extension meets (`RFCLinkTests`). The RFC Editor's PDF of a legacy RFC, `/rfc/pdfrfc/rfc2616.txt.pdf`, was the one form `RFCLink` did not read; it now reads the last path component of an RFC Editor URL, without any of its extensions. The script stays small enough that there is little in it to test, and nothing runs it but Safari.

**Safari's prompt is accepted.** Safari asks "Open in RFC Reader?" before it follows an `rfc://` link, and there is no way around it from an extension. A Universal Link would avoid it, but needs a domain the app is served from. So the opt-in redirect is two steps, not one, and the popup says that Safari asks each time.

**It asks for no more than it needs:** `nativeMessaging`, `storage` for the opt-in and `webNavigation` for the redirect, and host access to `rfc-editor.org`, `www.rfc-editor.org` and `datatracker.ietf.org`, so that Safari's permission prompt names exactly those sites. `tools.ietf.org` is left out: it only redirects to Datatracker, and the button still works on the page it lands on. The extension holds no data but the opt-in, and makes no connection of its own.
