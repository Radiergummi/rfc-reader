import Foundation
import RFCKit
import SafariServices

/// The Safari extension's native half (#194). The extension asks one thing, which
/// RFC a page is, and it is answered here with `RFCLink`, so that the extension, the
/// share sheet and the app agree on what an RFC's URL is; the script never matches
/// a URL itself.
///
/// The message is `{"url": "…"}`. The reply is `{"link": "rfc://…", "documentPage":
/// true}` for a page that names an RFC, `documentPage` saying whether the page is the
/// document itself, which the opt-in redirect may send to the app, rather than a page
/// about it; and `{}` for any other.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    let item = context.inputItems.first as? NSExtensionItem
    let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
    let url = (message?["url"] as? String).flatMap { URL(string: $0) }

    var reply: [String: Any] = [:]
    if let url, let link = RFCLink(url: url) {
      reply["link"] = link.appURL.absoluteString
      reply["documentPage"] = RFCLink(documentPage: url) != nil
    }
    let response = NSExtensionItem()
    response.userInfo = [SFExtensionMessageKey: reply]
    context.completeRequest(returningItems: [response], completionHandler: nil)
  }
}
