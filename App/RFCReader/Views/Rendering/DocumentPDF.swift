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
/// panel, and what Export as PDF saves, with its links and outline
/// (`DocumentPDF+Export.swift`) (#375, #376).
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
    /// With the title block and running header and footer `PrintFurniture` says.
    case document(Printed, PrintFurniture)
    /// With none: a published page carries its own.
    case original(String)
  }

  /// The open document, fetched and rendered as the reader is showing it. Fetched
  /// again rather than handed over by the reader: the library has it cached, and
  /// `ReaderState` deliberately carries strings out of the document, not the
  /// document itself. With Original Text showing, only the published text is
  /// fetched: its pages have their own header and footer.
  @MainActor
  static func make(
    for id: DocumentID, original: Bool, paperSize: CGSize, library: LibraryModel
  ) async throws -> Data {
    let content: Content
    if original {
      content = .original(try await library.originalText(for: id))
    } else {
      let document = try await library.document(for: id)
      content = .document(
        Printed(
          document: document,
          choices: library.presentationChoices(
            for: id, drawsDiagrams: ReaderPreferences.drawsDiagrams(in: .standard))),
        PrintFurniture(header: document.header, metadata: library.metadata(id)))
    }
    return await render(content, paperSize: paperSize)
  }

  /// Builds, lays out and draws, off the main actor, all of it in the light
  /// appearance: whether a dynamic color resolves when a line is laid out or when
  /// it is drawn is TextKit's to decide, and either way it has to be paper's.
  @concurrent
  static func render(_ content: Content, paperSize: CGSize) async -> Data {
    let layout = PrintLayout(paperSize: paperSize)
    switch content {
    case .document(let printed, let furniture):
      return buildAndLayOut(
        printed, style: layout.style, furniture: furniture, layout: layout
      ) { _, laidOut in
        pdf(laidOut, layout: layout, furniture: furniture)
      }
    case .original(let source):
      return inLightAppearance { publishedPDF(source, layout: layout) }
    }
  }

  /// A document to print, and which of its verbatim blocks the reader shows as their
  /// source: a print shows each block as the reader does.
  nonisolated struct Printed: Sendable {
    let document: RFCDocument
    let choices: PresentationChoices
  }

  /// `printed` built for `layout`'s paper and laid out, handed to `body` with what
  /// the build knows about it. All of it in the light appearance, what `body` draws
  /// included, for the reason `render` gives. A print and an export both go
  /// through here, so a PDF exported in Dark Mode is as white as a print (#376).
  ///
  /// - Parameter style: `layout.style` for a print, `layout.exportStyle` for an
  ///   export, whose links look like links.
  static func buildAndLayOut<Result>(
    _ printed: Printed, style: ReadingStyle, furniture: PrintFurniture, layout: PrintLayout,
    _ body: (BuiltDocument, LaidOut) -> Result
  ) -> Result {
    inLightAppearance {
      let built = DocumentTextBuilder.build(
        printed.document, style: style, title: furniture.titleBlock, choices: printed.choices)
      return layOut(built.text, keepingWithNext: built.keepsWithNext, layout: layout) {
        laidOut in
        body(built, laidOut)
      }
    }
  }

  // MARK: - Layout

  /// Text laid out at a page's column, and broken into pages: what `layOut` hands
  /// its body, and only good while that body runs.
  nonisolated struct LaidOut {
    let manager: NSTextLayoutManager
    /// In document order, top-down.
    let fragments: [NSTextLayoutFragment]
    /// Each fragment's extent, for `PrintPagination.spans(_:on:)`.
    let spans: [PrintPagination.Span]
    let pages: [PrintPagination.Page]
  }

  /// Lays `text` out at the page's column, breaks it into pages and hands the
  /// result to `body`, which draws it and, for an export, measures it again to
  /// place its links and destinations.
  ///
  /// The storage, layout manager and fragment factory are held until `body`
  /// returns, explicitly: a layout manager holds its delegate and its storage
  /// weakly, and a fragment its layout manager, and a local's lifetime ends at its
  /// last use, not at the end of its scope. Released early, the layout falls back
  /// to plain fragments or finds no text, and the fragments draw no decorations.
  private static func layOut<Result>(
    _ text: NSAttributedString, keepingWithNext: Set<Int>, layout: PrintLayout,
    _ body: (LaidOut) -> Result
  ) -> Result {
    let storage = NSTextContentStorage()
    let manager = NSTextLayoutManager()
    let factory = FragmentFactory()
    defer { withExtendedLifetime((storage, manager, factory)) {} }
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
            minY: frame.minY + bounds.minY, maxY: frame.minY + bounds.maxY, keepsWithNext: keeps
          ))
      }
      fragments.append(fragment)
      spans.append(PrintPagination.Span(minY: frame.minY, maxY: frame.maxY))
      return true
    }
    let pages = PrintPagination.pages(of: lines, pageHeight: layout.contentRect.height)
    return body(LaidOut(manager: manager, fragments: fragments, spans: spans, pages: pages))
  }

  /// The reader's own fragment class, so a print has the cards and rules the screen
  /// has. It has no chips: a paper build sets a reference as ordinary text
  /// (`ReferenceStyle.plainText`).
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

  /// Draws `laidOut` a page at a time, with the running header and footer.
  static func pdf(_ laidOut: LaidOut, layout: PrintLayout, furniture: PrintFurniture) -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: layout.paperSize)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { return Data() }
    withCurrentContext(context) {
      let running = RunningLines(furniture, layout: layout)
      for (index, page) in laidOut.pages.enumerated() {
        context.beginPDFPage(nil)
        context.saveGState()
        // Top-down, as the text view the fragments were written for draws.
        context.translateBy(x: 0, y: layout.paperSize.height)
        context.scaleBy(x: 1, y: -1)
        running.draw(page: index + 1, in: context)
        context.clip(to: layout.clipRect(for: page))
        for fragment in laidOut.fragments[PrintPagination.spans(laidOut.spans, on: page)] {
          let origin = layout.onPaper(fragment.layoutFragmentFrame, page: page).origin
          fragment.draw(at: origin, in: context)
        }
        context.restoreGState()
        context.endPDFPage()
      }
    }
    context.closePDF()
    return data as Data
  }

  // MARK: - Drawing environment

  /// The reader's colors are dynamic; paper is white, so they resolve as they do
  /// in the light appearance.
  private static func inLightAppearance<Result>(_ body: () -> Result) -> Result {
    // Both platforms run `body` before they return, so `result` is always set.
    var result: Result?
    #if canImport(UIKit)
      UITraitCollection(userInterfaceStyle: .light).performAsCurrent { result = body() }
    #else
      guard let light = NSAppearance(named: .aqua) else { return body() }
      light.performAsCurrentDrawingAppearance { result = body() }
    #endif
    return result!
  }

  /// `context` as the platform's current graphics context, for drawing that reaches
  /// for the current context rather than the one it is handed.
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
  let color: CGColor

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
    color = RFCColors.secondaryLabel.cgColor
  }

  func draw(page: Int, in context: CGContext) {
    let number = Self.place(
      PrintFurniture.pageLabel(page), in: footer, alignment: .right, attributes: attributes,
      token: nil)
    context.saveGState()
    context.setFillColor(color)
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

  /// One line of furniture, in the context's fill color. The middle of the line
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
