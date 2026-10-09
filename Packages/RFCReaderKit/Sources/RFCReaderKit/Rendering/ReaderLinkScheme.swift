import Foundation

/// The reader's private link schemes: written into the built text, and read back by
/// routing, previews, copying and the PDF export, which need no build to do so (#772).
public enum ReaderLinkScheme {
  /// The private URL scheme an in-document anchor link uses.
  public static let anchorScheme = "rfc-anchor"

  /// The scheme a citation of a bibliography entry uses instead. The body leaves
  /// the bibliography to the inspector (`holdsOnlyReferences`), so a citation of
  /// anything but an RFC — still an anchor after parsing — has no position to
  /// scroll to, and goes to its entry there.
  public static let referenceScheme = "rfc-reference"

  /// The scheme of a heading's backlink caption (#183), naming the section: a click
  /// lists the sections that refer to it rather than going anywhere.
  public static let backlinksScheme = "rfc-backlinks"

  /// The anchor a link of `anchorScheme` names: the other half of `url(_:scheme:)`,
  /// and nil when the URL is not one of ours. Kept beside the encoder, because a
  /// scheme whose two halves live apart is one percent-encoding rule away from
  /// silently failing on an anchor containing `?` or `#`.
  public static func anchor(from url: URL) -> String? {
    decoded(url, scheme: anchorScheme)
  }

  /// The same for `referenceScheme`: the bibliography entry a citation names.
  public static func reference(from url: URL) -> String? {
    decoded(url, scheme: referenceScheme)
  }

  /// The same for `backlinksScheme`: the section whose backlinks a caption lists.
  public static func backlinks(from url: URL) -> String? {
    decoded(url, scheme: backlinksScheme)
  }

  private static func decoded(_ url: URL, scheme: String) -> String? {
    guard url.scheme == scheme else { return nil }
    let encoded = url.absoluteString.dropFirst(scheme.count + 1)
    return String(encoded).removingPercentEncoding ?? String(encoded)
  }

  /// The encoding half of `decoded(_:scheme:)`: `anchor` as a link of one of our
  /// schemes, which `anchor(from:)` and its siblings read back.
  public static func url(_ anchor: String, scheme: String) -> URL? {
    let encoded = anchor.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? anchor
    return URL(string: "\(scheme):\(encoded)")
  }
}
