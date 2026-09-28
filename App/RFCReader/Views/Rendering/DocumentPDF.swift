import CoreGraphics
import CoreText
import Foundation
import RFCKit
import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The open RFC as a PDF laid out for paper: what Print hands the system's print
/// panel, and what Export as PDF will save (#375, #376).
///
/// Not the reader's text view sent to a printer. The reader is built for the
/// window's column, draws in the current appearance, and has its title in a hosted
/// view over the text; a print is built again at the paper's width, with its title
/// in the text, and drawn in the light appearance whatever the screen is in.
///
/// Only the drawing is here. Where the text goes on the page is `PrintLayout`, where
/// the pages break is `PrintPagination`, and what the header and footer say is
/// `PrintFurniture`, all in RFCReaderKit, where they are under test.
///
/// `nonisolated`, as `RFCTextLayoutFragment` is: a document is laid out and drawn
/// off the main actor, since the largest RFCs run to hundreds of pages.
nonisolated enum DocumentPDF {
  /// What is printed: the reader's rendering, or the RFC as published when the
  /// reader is showing that instead.
  nonisolated enum Content: Sendable {
    case document(RFCDocument)
    case original(String)
  }

  /// The open document, fetched and rendered as the reader is showing it. Fetched
  /// again rather than handed over by the reader: the library has it cached, and
  /// `ReaderState` deliberately carries strings out of the document, not the
  /// document itself.
  @MainActor
  static func make(
    for id: DocumentID, original: Bool, paperSize: CGSize, library: LibraryModel
  ) async throws -> Data {
    let document = try await library.document(for: id)
    let furniture = PrintFurniture(header: document.header, metadata: library.metadata(id))
    let content: Content =
      original ? .original(try await library.originalText(for: id)) : .document(document)
    return await render(content, furniture: furniture, paperSize: paperSize)
  }

  /// Builds, lays out and draws, off the main actor.
  @concurrent
  static func render(_ content: Content, furniture: PrintFurniture, paperSize: CGSize) async
    -> Data
  {
    let layout = PrintLayout(paperSize: paperSize)
    switch content {
    case .document(let document):
      let built = DocumentTextBuilder.build(
        document, style: layout.style, title: furniture.titleBlock)
      return draw(
        withoutLinks(built.text), headings: PrintPagination.headingOffsets(in: built),
        layout: layout, furniture: furniture)
    case .original(let source):
      // The published text is set in 72 columns, which fits the narrowest paper's
      // column at this size without wrapping.
      let text = NSAttributedString(
        string: source,
        attributes: [
          .font: PlatformFont.monospacedSystemFont(ofSize: 9, weight: .regular),
          .foregroundColor: RFCColors.label,
        ])
      return draw(text, headings: [], layout: layout, furniture: furniture)
    }
  }

  /// Paper cannot follow a link, and TextKit 2 underlines and recolours every
  /// `.link` run it lays out unless a text view says otherwise, which there is none
  /// of here. A copy, so the build's own text is never written (`BuiltDocument`).
  private static func withoutLinks(_ text: NSAttributedString) -> NSAttributedString {
    let copy = NSMutableAttributedString(attributedString: text)
    copy.removeAttribute(.link, range: NSRange(location: 0, length: copy.length))
    return copy
  }

  // MARK: - Layout

  /// Lays `text` out at the page's column and draws it a page at a time.
  ///
  /// The storage, layout manager and fragment factory are held for the whole call:
  /// a fragment reaches its text through its layout manager, weakly, and draws its
  /// decorations from what it finds there.
  private static func draw(
    _ text: NSAttributedString, headings: Set<Int>, layout: PrintLayout,
    furniture: PrintFurniture
  ) -> Data {
    let storage = NSTextContentStorage()
    let manager = NSTextLayoutManager()
    let factory = FragmentFactory()
    manager.delegate = factory
    storage.addTextLayoutManager(manager)
    let container = NSTextContainer(
      size: CGSize(width: layout.contentRect.width, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    manager.textContainer = container
    storage.install(text)
    manager.ensureLayout(for: manager.documentRange)

    var fragments: [NSTextLayoutFragment] = []
    var lines: [PrintPagination.Line] = []
    _ = manager.enumerateTextLayoutFragments(
      from: manager.documentRange.location, options: [.ensuresLayout]
    ) { fragment in
      let frame = fragment.layoutFragmentFrame
      let keeps = headings.contains(manager.offset(of: fragment.rangeInElement.location))
      for line in fragment.textLineFragments {
        let bounds = line.typographicBounds
        lines.append(
          PrintPagination.Line(
            minY: frame.minY + bounds.minY, maxY: frame.minY + bounds.maxY, keepsWithNext: keeps))
      }
      fragments.append(fragment)
      return true
    }
    let pages = PrintPagination.pages(of: lines, pageHeight: layout.contentRect.height)
    return pdf(pages: pages, fragments: fragments, layout: layout, furniture: furniture)
  }

  /// The reader's own fragment class, so a print has the cards, rules and chips the
  /// screen has.
  nonisolated private final class FragmentFactory: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
      _ textLayoutManager: NSTextLayoutManager,
      textLayoutFragmentFor location: any NSTextLocation,
      in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
      RFCTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
  }

  // MARK: - Drawing

  private static func pdf(
    pages: [PrintPagination.Page], fragments: [NSTextLayoutFragment], layout: PrintLayout,
    furniture: PrintFurniture
  ) -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: layout.paperSize)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { return Data() }
    let column = layout.contentRect
    inLightAppearance {
      withCurrentContext(context) {
        // Fragments are in document order, and so are pages, so the first one a
        // page can hold never moves back.
        var first = 0
        for (index, page) in pages.enumerated() {
          context.beginPDFPage(nil)
          context.saveGState()
          // Top-down, as the text view the fragments were written for draws.
          context.translateBy(x: 0, y: layout.paperSize.height)
          context.scaleBy(x: 1, y: -1)
          drawFurniture(furniture, page: index + 1, layout: layout, in: context)
          context.clip(
            to: CGRect(x: column.minX, y: column.minY, width: column.width, height: page.height))
          while first < fragments.count, fragments[first].layoutFragmentFrame.maxY <= page.top {
            first += 1
          }
          var next = first
          while next < fragments.count, fragments[next].layoutFragmentFrame.minY < page.bottom {
            let fragment = fragments[next]
            let frame = fragment.layoutFragmentFrame
            let origin = CGPoint(
              x: column.minX + frame.minX, y: column.minY + frame.minY - page.top)
            fragment.draw(at: origin, in: context)
            drawAttachments(of: fragment, at: origin)
            next += 1
          }
          context.restoreGState()
          context.endPDFPage()
        }
      }
    }
    context.closePDF()
    return data as Data
  }

  /// The chips' symbols. In a text view an attachment is a view of its own, which
  /// the fragment leaves for the view to draw; there is no view here, so each one a
  /// fragment would have handed to a view is drawn where that view would have been.
  private static func drawAttachments(of fragment: NSTextLayoutFragment, at origin: CGPoint) {
    for provider in fragment.textAttachmentViewProviders {
      guard let image = provider.textAttachment?.image else { continue }
      let frame = fragment.frameForTextAttachment(at: provider.location)
        .offsetBy(dx: origin.x, dy: origin.y)
      #if canImport(UIKit)
        image.draw(in: frame)
      #else
        image.draw(
          in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
          hints: nil)
      #endif
    }
  }

  /// The running header and footer, in the page's top-down coordinates.
  private static func drawFurniture(
    _ furniture: PrintFurniture, page: Int, layout: PrintLayout, in context: CGContext
  ) {
    context.saveGState()
    context.setFillColor(RFCColors.secondaryLabel.cgColor)
    let header = layout.headerRect
    let footer = layout.footerRect
    drawLine(furniture.headerLeading, in: header, alignment: .left, context: context)
    drawLine(furniture.headerCenter, in: header, alignment: .center, context: context)
    drawLine(furniture.headerTrailing, in: header, alignment: .right, context: context)
    drawLine(furniture.footerLeading, in: footer, alignment: .left, context: context)
    drawLine(furniture.footerCenter, in: footer, alignment: .center, context: context)
    drawLine(PrintFurniture.pageLabel(page), in: footer, alignment: .right, context: context)
    context.restoreGState()
  }

  /// One line of furniture, through CoreText rather than string drawing, in the
  /// context's fill colour. The middle of the line gets half its width and each end
  /// a quarter, so a long title is truncated rather than run over the date.
  private static func drawLine(
    _ text: String, in rect: CGRect, alignment: NSTextAlignment, context: CGContext
  ) {
    guard !text.isEmpty else { return }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: PlatformFont.systemFont(ofSize: 8.5),
      NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
    ]
    let full = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: attributes))
    let room = rect.width * (alignment == .center ? 0.5 : 0.25)
    let token = CTLineCreateWithAttributedString(
      NSAttributedString(string: "…", attributes: attributes))
    let line = CTLineCreateTruncatedLine(full, room, .end, token) ?? full
    var ascent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, nil, nil))
    let x: CGFloat =
      switch alignment {
      case .center: rect.midX - width / 2
      case .right: rect.maxX - width
      default: rect.minX
      }
    // The context is flipped, and CoreText sets glyphs upright only in an unflipped
    // one, so the text matrix flips them back.
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: x, y: rect.minY + ascent)
    CTLineDraw(line, context)
  }

  // MARK: - Drawing environment

  /// The reader's colours are dynamic; paper is white, so they resolve as they do
  /// in the light appearance.
  private static func inLightAppearance(_ body: () -> Void) {
    #if canImport(UIKit)
      UITraitCollection(userInterfaceStyle: .light).performAsCurrent(body)
    #else
      if let light = NSAppearance(named: .aqua) {
        light.performAsCurrentDrawingAppearance(body)
      } else {
        body()
      }
    #endif
  }

  /// `context` as the platform's current graphics context, which the attachments'
  /// images draw into.
  private static func withCurrentContext(_ context: CGContext, _ body: () -> Void) {
    #if canImport(UIKit)
      UIGraphicsPushContext(context)
      body()
      UIGraphicsPopContext()
    #else
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      body()
      NSGraphicsContext.restoreGraphicsState()
    #endif
  }
}
