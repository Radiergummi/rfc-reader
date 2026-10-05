// The opt-in redirect, run in the page at document_start on the pages a document
// can be (the manifest's `content_scripts`). The background script answers with the
// `rfc://` link where the page is a document's own and its site's opt-in is on, and
// nothing otherwise; a page about the document, such as its errata or history,
// stays in Safari.
//
// The page navigates itself because Safari opens an app from a page's own
// navigation, asking "Open in RFC Reader?" each time, but did not from a
// `tabs.update` sent by the background script during `webNavigation.onBeforeNavigate`
// (#194). Declining the prompt is expected to leave the page as it is.
browser.runtime.sendMessage({ redirect: location.href }).then((link) => {
  if (link) {
    location.replace(link);
  }
});
