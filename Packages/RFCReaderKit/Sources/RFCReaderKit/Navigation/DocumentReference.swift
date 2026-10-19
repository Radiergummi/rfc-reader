import Foundation
import RFCKit

/// The document someone asks for by typing or scripting it: Go to RFC,
/// and `open rfc` in the scripting dictionary.
public enum DocumentReference {
  /// A number (`9110`), a name (`"RFC 9110"`, `"BCP 14"`), or a link the app
  /// already opens (`rfc://9110#section-4.2`, an rfc-editor.org or datatracker
  /// URL). A `section` given separately wins over one the link carries: it is the
  /// more specific of the two requests.
  public static func link(from reference: String, section: String? = nil) -> RFCLink? {
    let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
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
    let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
