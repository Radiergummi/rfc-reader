import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// How a text view draws the reader's links, decided when it draws rather than when
/// the document is built: a link on a card, and a heading's backlink caption (#772).
public enum LinkRendering {
  /// A text view's link attributes, `defaults`, for a link on a card: in
  /// `RFCColors.cardLink`, since the text view's color may fall below the minimum
  /// contrast on a card's fill in dark (#694). Made once, with the text view's.
  public static func cardAttributes(
    _ defaults: [NSAttributedString.Key: Any]
  ) -> [NSAttributedString.Key: Any] {
    var attributes = defaults
    attributes[.foregroundColor] = RFCColors.cardLink(
      over: defaults[.foregroundColor] as? PlatformColor ?? RFCColors.link)
    return attributes
  }

  /// The attributes a text view draws the link `link` with, given its own
  /// `defaults`: a text view colors every link itself, over the storage's color,
  /// which a backlink caption has to keep to stay in the background. The caption
  /// is drawn with `caption` on top: on macOS the ordinary pointer, not a link's
  /// pointing hand, since it opens a list beside it as a control does. Passed in
  /// rather than made here, because a cursor is AppKit's to make on the main
  /// thread and TextKit may ask from another. Every other link is drawn as the
  /// text view would: `defaults`, which on a card are `cardAttributes`.
  ///
  /// A heading's hung number (#433) is no link to look at, but the heading's own
  /// number: it keeps its quieter color, and comes up to the label's under the
  /// pointer, as `sectionNumber` says it is.
  ///
  /// Under a page theme (#704), `palette`, every color is the theme's instead:
  /// the link's, the card link's where the link is `onCard`, and the theme's
  /// secondary and body text where the storage's color is kept. The automatic
  /// palette changes nothing.
  public static func attributes(
    for link: Any, defaults: [NSAttributedString.Key: Any],
    caption: [NSAttributedString.Key: Any] = [:], sectionNumber: SectionNumberState? = nil,
    palette: ReaderPalette = .automatic, onCard: Bool = false
  ) -> [NSAttributedString.Key: Any] {
    var attributes = defaults
    if let sectionNumber {
      attributes[.foregroundColor] =
        sectionNumber == .hovered
        ? palette.foreground(for: RFCColors.label) ?? RFCColors.label
        : palette.foreground(for: RFCColors.secondaryLabel)
      return attributes
    }
    // The scheme alone: asked of every link TextKit draws, where decoding the
    // anchor would allocate for an answer nobody reads.
    guard let url = link as? URL, url.scheme == ReaderLinkScheme.backlinksScheme else {
      if !palette.drawsStoredColors {
        attributes[.foregroundColor] = onCard ? palette.cardLink : palette.link
      }
      return attributes
    }
    // The caption's own color, which the builder stores as the secondary label's.
    attributes[.foregroundColor] = palette.foreground(for: RFCColors.secondaryLabel)
    attributes.merge(caption) { _, caption in caption }
    return attributes
  }
}
