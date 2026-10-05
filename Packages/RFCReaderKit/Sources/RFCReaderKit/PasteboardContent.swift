import Foundation
import RFCKit
import UniformTypeIdentifiers

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// What a copy puts on the pasteboard (#778): one item, in every flavor a target
/// might read, richest first. Each kind of copy is answered here, once for both
/// platforms; the App target's `Clipboard` only writes it.
public struct PasteboardContent: Equatable, Sendable {
  public enum Value: Equatable, Sendable {
    case text(String)
    case data(Data)
  }

  public struct Flavor: Equatable, Sendable {
    public let type: UTType
    public let value: Value

    public init(_ type: UTType, _ value: Value) {
      self.type = type
      self.value = value
    }
  }

  public let flavors: [Flavor]

  public func value(for type: UTType) -> Value? {
    flavors.first { $0.type == type }?.value
  }

  /// Text with nothing richer to say: a citation, a checklist, a block of code.
  public static func text(_ text: String) -> PasteboardContent {
    PasteboardContent(flavors: [Flavor(.utf8PlainText, .text(text))])
  }

  /// A link anyone can open: the URL, as a URL and as text, and its label linked to
  /// it, for a target that pastes a link as words.
  public static func link(_ link: LinkCopy) -> PasteboardContent {
    let url = link.url.absoluteString
    var flavors = [
      Flavor(.url, .text(url)), Flavor(.utf8PlainText, .text(url)),
      Flavor(.html, .text(link.html)),
    ]
    if let rtf = link.rtf { flavors.append(Flavor(.rtf, .data(rtf))) }
    return PasteboardContent(flavors: flavors)
  }

  /// Copy as Quote (#186). The plain text is the Markdown, which is what a web page
  /// and a chat app read.
  public static func quote(_ quote: QuoteCitation.Quote) -> PasteboardContent {
    var flavors = [
      Flavor(.utf8PlainText, .text(quote.plainText)),
      Flavor(UTType(importedAs: QuoteCitation.Quote.markdownType), .text(quote.markdown)),
      Flavor(.html, .text(quote.html)),
    ]
    if let rtf = quote.rtf { flavors.append(Flavor(.rtf, .data(rtf))) }
    return PasteboardContent(flavors: flavors)
  }

  /// A figure: its text as `FigureCopy` gives it, and the drawing as an image where
  /// the reader draws one, whichever gesture copied it. Text first, so a target
  /// that reads both, such as a code editor, gets the text.
  public static func figure(_ figure: Preformatted, png: Data?) -> PasteboardContent {
    var flavors = [Flavor(.utf8PlainText, .text(FigureCopy.pasteboardText(for: figure)))]
    if let png { flavors.append(Flavor(.png, .data(png))) }
    return PasteboardContent(flavors: flavors)
  }

  /// A selection of the reader's text: rich text with the chips' images, rich text,
  /// HTML and plain text. The rich flavors and the HTML link a reference to the URL
  /// `publicURL` gives for its link, or to nothing, never to the reader's own
  /// (`LinkCopy.publicURL`).
  public static func selection(
    _ selection: NSAttributedString, publicURL: (URL) -> URL?
  ) -> PasteboardContent {
    let rich = SelectionText.richCopy(of: selection, publicURL: publicURL)
    let whole = NSRange(location: 0, length: rich.length)
    var flavors: [Flavor] = []
    if let rtfd = try? rich.data(
      from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    {
      flavors.append(Flavor(.flatRTFD, .data(rtfd)))
    }
    if let rtf = PasteboardMarkup.rtf(rich) { flavors.append(Flavor(.rtf, .data(rtf))) }
    flavors.append(Flavor(.html, .text(SelectionText.html(of: selection, publicURL: publicURL))))
    flavors.append(Flavor(.utf8PlainText, .text(SelectionText.plainText(of: selection))))
    return PasteboardContent(flavors: flavors)
  }
}

extension LinkCopy {
  /// The URL a copy links `link` to: `forLink`'s for a link of the reader's, nil for
  /// one with nothing of ours to hand out, and a link to the web as it is.
  public static func publicURL(
    for link: URL, from currentDocument: DocumentID, in index: RFCIndex?,
    bibliography: [ReferenceGroup]
  ) -> URL? {
    guard isReaders(link) else { return link }
    return forLink(link, from: currentDocument, in: index, bibliography: bibliography)?.url
  }
}
