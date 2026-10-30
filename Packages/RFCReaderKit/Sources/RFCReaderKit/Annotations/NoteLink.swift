import Foundation
import RFCKit

/// What a note's link field makes of what is typed into it, and what a paste into a
/// note becomes a link by itself (#523).
public enum NoteLink {
  /// The URL `typed` names: anything that names an RFC, such as `RFC 9110`,
  /// `RFC 9110 Section 4.2`, `9110#section-4.2` or an rfc-editor.org address, as the
  /// app's own `rfc://` link; otherwise a web or mail address, `https://` assumed
  /// where none is given and `mailto:` for a bare mail address. Nil for anything else.
  public static func url(from typed: String) -> URL? {
    let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return nil }
    if let link = rfcLink(from: trimmed) { return link.appURL }
    if let url = URL(string: trimmed), follows(url) { return url }
    guard !trimmed.contains(" "), trimmed.contains("."), !trimmed.hasPrefix(".") else {
      return nil
    }
    // A bare mail address, as `a@example.org`: mail, not a web page with a user.
    if !trimmed.contains("/"), let atSign = trimmed.firstIndex(of: "@"),
      atSign != trimmed.startIndex,
      trimmed[trimmed.index(after: atSign)...].contains("."),
      let url = URL(string: "mailto:" + trimmed)
    {
      return url
    }
    // A bare host, as `example.org/page`: a word, a period, a word, and no space.
    if let url = URL(string: "https://" + trimmed), url.host()?.contains(".") == true {
      return url
    }
    return nil
  }

  /// Whether a note keeps `url` as a link: a web page, a mail address, or the app's
  /// own `rfc://` link. Not a file, or another app's scheme.
  public static func follows(_ url: URL) -> Bool {
    ["http", "https", "mailto", "rfc"].contains(url.scheme?.lowercased() ?? "")
  }

  /// The link `text` is, when it is the whole of a paste: an `rfc://` link, or an
  /// address of an RFC at the RFC Editor or Datatracker, as the app's own link.
  public static func pasted(_ text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
      url.scheme != nil, let link = RFCLink(url: url)
    else { return nil }
    return link.appURL
  }

  private static func rfcLink(from text: String) -> RFCLink? {
    // `9110#section-4.2`, `RFC 9110#section-4.2`.
    if let hash = text.firstIndex(of: "#"), !text.contains("://"),
      var link = DocumentReference.link(from: String(text[..<hash]))
    {
      link.anchor = String(text[text.index(after: hash)...])
      link.section = nil
      return link
    }
    // `RFC 9110 Section 4.2`, `RFC 9110, Section 4.2`, `RFC 9110 §4.2`.
    let pattern = /^(?<document>.+?)[,\s]+(?:[Ss]ection|§)\s*(?<section>[0-9A-Za-z.]+)$/
    if let match = text.wholeMatch(of: pattern),
      let link = DocumentReference.link(
        from: String(match.document), section: String(match.section))
    {
      return link
    }
    return DocumentReference.link(from: text)
  }
}
