import Foundation
import RFCKit

/// The document someone asks for by typing or scripting it: Go to RFC,
/// and `open rfc` in the scripting dictionary.
public enum DocumentReference {
  /// A number (`9110`), a name (`"RFC 9110"`, `"BCP 14"`), or a link the app
  /// already opens (`rfc://9110#section-4.2`, an rfc-editor.org or datatracker
  /// URL), as typed or as pasted from a document's text (`[RFC9110]`, `RFC 9110.`).
  /// A `section` given separately wins over one the link carries: it is the
  /// more specific of the two requests.
  public static func link(from reference: String, section: String? = nil) -> RFCLink? {
    let trimmed = pasted(reference)
    var link: RFCLink
    if let id = DocumentID(parsing: trimmed) {
      link = RFCLink(id: id)
    } else if let url = URL(string: trimmed), url.scheme != nil, let parsed = RFCLink(url: url) {
      link = parsed
    } else {
      return nil
    }
    if let section, !section.isEmpty {
      link.section = section
      link.anchor = nil
    }
    return link
  }

  /// The Internet-Draft `reference` names (#728): its name, with a revision or
  /// without (`draft-ietf-quic-http-34`), or a link to it the app opens. Nil for
  /// anything an RFC's reference reads. A `section` wins as it does for an RFC.
  public static func draft(from reference: String, section: String? = nil) -> DraftLink? {
    let trimmed = pasted(reference)
    var link: DraftLink
    if let id = DraftID(parsing: trimmed) {
      link = DraftLink(id: id)
    } else if let url = URL(string: trimmed), url.scheme != nil, let parsed = DraftLink(url: url) {
      link = parsed
    } else {
      return nil
    }
    if let section, !section.isEmpty {
      link.section = section
      link.anchor = nil
    }
    return link
  }

  /// The registry values `reference` names (#175), read as a pasted reference is:
  /// `425.` and `(425)` name what `425` does.
  public static func registryMatches(
    for reference: String, in entries: [RegistryEntry]
  ) -> [RegistryEntry] {
    RegistryLookup.matches(pasted(reference), in: entries)
  }

  /// A reference less what a paste brings with it from the text around it (#579):
  /// the spaces, the punctuation that ended its sentence, then one pair of the
  /// brackets or quotes a citation (`[RFC9110]`), an aside (`(BCP 14)`), a link
  /// (`<https://…>`) or a quotation (`“RFC 9110”`) is written in, and the punctuation
  /// inside them (`(RFC 9110.)`).
  private static func pasted(_ reference: String) -> String {
    var text = withoutTrailingPunctuation(Substring(reference))
    for (open, close) in [("[", "]"), ("(", ")"), ("<", ">"), ("“", "”"), ("\"", "\"")]
    where text.hasPrefix(open) && text.hasSuffix(close) {
      text = withoutTrailingPunctuation(text.dropFirst().dropLast())
      break
    }
    return String(text)
  }

  /// `text` less the spaces around it and the punctuation that ends it.
  private static func withoutTrailingPunctuation(_ text: Substring) -> Substring {
    var text = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
    while let last = text.last, ".,;:".contains(last) {
      text = text.dropLast()
    }
    return Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
