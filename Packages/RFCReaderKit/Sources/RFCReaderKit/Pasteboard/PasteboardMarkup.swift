import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The HTML and RTF flavors every copy writes, in one place so they cannot drift
/// apart again (#775).
enum PasteboardMarkup {
  /// `body` as the HTML flavor. The charset, or a target reading the flavor as
  /// Latin-1 garbles anything that is not ASCII, a dash or a title among them.
  static func html(_ body: String) -> String {
    "<meta charset=\"utf-8\">\n" + body
  }

  /// `text` as HTML text or an attribute value: the characters markup is made of, as
  /// entities.
  static func escaped(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  /// `text` as the RTF flavor.
  static func rtf(_ text: NSAttributedString) -> Data? {
    try? text.data(
      from: NSRange(location: 0, length: text.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
  }
}
