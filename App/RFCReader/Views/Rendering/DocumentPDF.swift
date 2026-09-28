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
  /// document itself. With Original Text showing, both are fetched at once.
  @MainActor
  static func make(
    for id: DocumentID, original: Bool, paperSize: CGSize, library: LibraryModel
  ) async throws -> Data {
    async let fetched = library.document(for: id)
    let source: String? = if original { try await library.originalText(for: id) } else { nil }
    let document = try await fetched
    let furniture = PrintFurniture(header: document.header, metadata: library.metadata(id))
    let content: Content = source.map { .original($0) } ?? .document(document)
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
        built.text, keepingWithNext: built.keepsWithNext, layout: layout, furniture: furniture)
    case .original(let source):
      let text = NSAttributedString(
        string: source,
        attributes: [
          .font: PlatformFont.monospacedSystemFont(
            ofSize: PrintLayout.originalTextSize, weight: .regular),
          .foregroundColor: RFCColors.label,
        ])
      return draw(text, keepingWithNext: [], layout: layout, furniture: furniture)
    }
  }

  // MARK: - Layout

  /// Lays `text` out at the page's column and draws it a page at a time.
  ///
  /// The storage, layout manager and fragment factory are held for the whole call:
  /// a fragment reaches its text through its layout manager, weakly, and draws its
  /// decorations from what it finds there.
  private static func draw(
    _ text: NSAttributedString, keepingWithNext: Set<Int>, layout: PrintLayout,
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

    var fragments: [NSTextLayoutFragment] = []
    var spans: [PrintPagination.Span] = []
    var lines: [PrintPagination.Line] = []
    _ = manager.enumerateTextLayoutFragments(
      from: manager.documentRange.location, options: [.ensuresLayout]
    ) { fragment in
      let frame = fragment.layoutFragmentFrame
      let keeps = keepingWithNext.contains(manager.offset(of: fragment.rangeInElement.location))
      for line in fragment.textLineFragments {
        let bounds = line.typographicBounds
        lines.append(
          PrintPagination.Line(
            minY: frame.minY + bounds.minY, maxY: frame.minY + bounds.maxY, keepsWithNext: keeps))
      }
      fragments.append(fragment)
      spans.append(PrintPagination.Span(minY: frame.minY, maxY: frame.maxY))
      return true
    }
    let pages = PrintPagination.pages(of: lines, pageHeight: layout.contentRect.height)
    return pdf(
      pages: pages, fragments: fragments, spans: spans, layout: layout, furniture: furniture)
  }

  /// The reader's own fragment class, so a print has the cards, rules and chips the
  /// screen has.
  nonisolated private final class FragmentFactory: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
      _ textLayoutManager: NSTextLayoutManager,
      textLayoutFragmentFor location: any NSTextLocation,
      in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
      RFCTextLayoutFragment.make(for: textElement)
    }
  }

  // MARK: - Drawing

  private static func pdf(
    pages: [PrintPagination.Page], fragments: [NSTextLayoutFragment],
    spans: [PrintPagination.Span], layout: PrintLayout, furniture: PrintFurniture
  ) -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: layout.paperSize)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { return Data() }
    let column = layout.contentRect
    inLightAppearance {
      withCurrentContext(context) {
        // Inside the light appearance, which the furniture's colour resolves in.
        let running = RunningLines(furniture, layout: layout)
        for (index, page) in pages.enumerated() {
          context.beginPDFPage(nil)
          context.saveGState()
          // Top-down, as the text view the fragments were written for draws.
          context.translateBy(x: 0, y: layout.paperSize.height)
          context.scaleBy(x: 1, y: -1)
          running.draw(page: index + 1, in: context)
          context.clip(
            to: CGRect(x: column.minX, y: column.minY, width: column.width, height: page.height))
          for fragment in fragments[PrintPagination.spans(spans, on: page)] {
            let frame = fragment.layoutFragmentFrame
            let origin = CGPoint(
              x: column.minX + frame.minX, y: column.minY + frame.minY - page.top)
            fragment.draw(at: origin, in: context)
            drawAttachments(of: fragment, at: origin)
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

/// The running header and footer, set once per document: only the page number
/// changes from page to page.
nonisolated private struct RunningLines {
  /// A line set, and where its baseline starts, in the page's top-down
  /// coordinates.
  struct Placed {
    let line: CTLine
    let origin: CGPoint
  }

  let fixed: [Placed]
  let footer: CGRect
  let attributes: [NSAttributedString.Key: Any]
  let colour: CGColor

  init(_ furniture: PrintFurniture, layout: PrintLayout) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: PlatformFont.systemFont(ofSize: 8.5),
      NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
    ]
    let header = layout.headerRect
    let footer = layout.footerRect
    let token = CTLineCreateWithAttributedString(
      NSAttributedString(string: "…", attributes: attributes))
    func place(_ text: String, _ rect: CGRect, _ alignment: NSTextAlignment) -> Placed? {
      Self.place(text, in: rect, alignment: alignment, attributes: attributes, token: token)
    }
    fixed = [
      place(furniture.headerLeading, header, .left),
      place(furniture.headerCenter, header, .center),
      place(furniture.headerTrailing, header, .right),
      place(furniture.footerLeading, footer, .left),
      place(furniture.footerCenter, footer, .center),
    ].compactMap { $0 }
    self.attributes = attributes
    self.footer = footer
    colour = RFCColors.secondaryLabel.cgColor
  }

  func draw(page: Int, in context: CGContext) {
    let number = Self.place(
      PrintFurniture.pageLabel(page), in: footer, alignment: .right, attributes: attributes,
      token: nil)
    context.saveGState()
    context.setFillColor(colour)
    // The context is flipped, and CoreText sets glyphs upright only in an
    // unflipped one, so the text matrix flips them back.
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    var lines = fixed
    if let number { lines.append(number) }
    for placed in lines {
      context.textPosition = placed.origin
      CTLineDraw(placed.line, context)
    }
    context.restoreGState()
  }

  /// One line of furniture, in the context's fill colour. The middle of the line
  /// gets half its width and each end a quarter, so a long title is truncated
  /// rather than run over the date.
  private static func place(
    _ text: String, in rect: CGRect, alignment: NSTextAlignment,
    attributes: [NSAttributedString.Key: Any], token: CTLine?
  ) -> Placed? {
    guard !text.isEmpty else { return nil }
    let full = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: attributes))
    let room = rect.width * (alignment == .center ? 0.5 : 0.25)
    let line = CTLineCreateTruncatedLine(full, room, .end, token) ?? full
    var ascent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, nil, nil))
    let x: CGFloat =
      switch alignment {
      case .center: rect.midX - width / 2
      case .right: rect.maxX - width
      default: rect.minX
      }
    return Placed(line: line, origin: CGPoint(x: x, y: rect.minY + ascent))
  }
}
