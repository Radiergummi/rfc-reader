import CoreGraphics
import Foundation

/// Where things go on a printed page, and the style the document is built in for it
/// (#375).
///
/// A print is its own build rather than the reader's storage sent to a printer: the
/// reader is built for the window's column, and artwork scaling and table shape are
/// measured against that column at build time, so nothing laid out for the screen
/// can be re-flowed onto paper afterwards. The paper's width is the column.
///
/// Page coordinates here run top-down from the page's top-left corner, as the
/// reader's text view does; the renderer flips a PDF context to match.
public struct PrintLayout: Sendable, Equatable {
  public let paperSize: CGSize

  /// The body text's size on paper. Print is read closer than a screen, and a
  /// 10.5 pt body is what a typeset standard is set in.
  static let bodySize: CGFloat = 10.5

  /// Three quarters of an inch at the sides, which every printer can reach and
  /// which leaves a Letter page's column close to the reader's own measure.
  static let sideMargin: CGFloat = 54
  /// Room above and below the text for the running header and footer.
  static let verticalMargin: CGFloat = 64
  /// How far the running header's and footer's lines sit from the paper's edge.
  static let furnitureInset: CGFloat = 32
  /// The height of the running header's and footer's line.
  static let furnitureHeight: CGFloat = 12

  /// The size the RFC as published is set in, when Original Text is what prints:
  /// small enough that its 72 columns fit the narrowest paper's column without
  /// wrapping, which is what its artwork needs to read.
  public static let originalTextSize: CGFloat = 9

  public init(paperSize: CGSize) {
    self.paperSize = paperSize
  }

  /// US Letter, in points.
  static let letter = CGSize(width: 612, height: 792)
  /// ISO A4, in points.
  static let isoA4 = CGSize(width: 595, height: 842)

  /// The regions that print on Letter. Not the ones that measure in US customary
  /// units: Canada, Mexico and the Philippines are metric and use Letter too. This
  /// is CLDR's paper-size data, which Foundation does not expose.
  static let letterRegions: Set<String> = [
    "BZ", "CA", "CL", "CO", "CR", "GT", "MX", "NI", "PA", "PH", "PR", "SV", "US", "VE",
  ]

  /// The paper a region prints on when nothing has said otherwise: Letter where
  /// the region uses it, A4 everywhere else. For iOS, whose print sheet picks the
  /// paper only after the document is laid out; the Mac asks Page Setup.
  public static func paperSize(for locale: Locale) -> CGSize {
    guard let region = locale.region?.identifier else { return isoA4 }
    return letterRegions.contains(region) ? letter : isoA4
  }

  /// Where the document's text goes on every page.
  public var contentRect: CGRect {
    CGRect(
      x: Self.sideMargin,
      y: Self.verticalMargin,
      width: max(0, paperSize.width - 2 * Self.sideMargin),
      height: max(0, paperSize.height - 2 * Self.verticalMargin)
    )
  }

  /// The running header's line: as wide as the text, near the top edge.
  public var headerRect: CGRect {
    CGRect(
      x: contentRect.minX, y: Self.furnitureInset, width: contentRect.width,
      height: Self.furnitureHeight)
  }

  /// The running footer's line: as wide as the text, near the bottom edge.
  public var footerRect: CGRect {
    CGRect(
      x: contentRect.minX, y: paperSize.height - Self.furnitureInset - Self.furnitureHeight,
      width: contentRect.width, height: Self.furnitureHeight)
  }

  /// What a page's text is clipped to: the lines `page` holds, top to bottom, and
  /// the paper's whole width across. Not the column's: a card's padding and a block
  /// quote's rule hang outside the text they decorate, and clipped to the column
  /// every card would lose its sides and a quote at the margin its rule. Nothing
  /// else is drawn beside the lines, so the side margins are theirs.
  public func clipRect(for page: PrintPagination.Page) -> CGRect {
    CGRect(x: 0, y: contentRect.minY, width: paperSize.width, height: page.height)
  }

  /// `rect`, in the laid-out document's coordinates, where `page` puts it on
  /// paper: the page's slice of the document starts at the top of the column.
  /// Where a fragment is drawn, and where an exported PDF's links and
  /// destinations go (#376).
  public func onPaper(_ rect: CGRect, page: PrintPagination.Page) -> CGRect {
    rect.offsetBy(dx: contentRect.minX, dy: contentRect.minY - page.top)
  }

  /// The style a document is built in for this paper: the print body size, set to
  /// the page's column, with no links, since paper cannot follow one. The system's
  /// text size is left at its default: it is a setting for the screen, and paper
  /// has one size.
  public var style: ReadingStyle {
    ReadingStyle(
      bodySize: Self.bodySize, measure: contentRect.width, lineHeightMultiple: 1.2,
      emitsLinks: false)
  }
}
