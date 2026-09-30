import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Builder: artwork")
struct BuilderVerbatimTests {
  private let style = ReadingStyle()

  private func document(_ content: Preformatted) -> RFCDocument {
    Fixtures.document(.preformatted(content))
  }

  @Test func `artwork survives line for line`() {
    let art = "+---+\n| A |\n+---+"
    let built = DocumentTextBuilder.build(
      document(Preformatted(kind: .artwork, text: art)), style: style)
    for line in art.split(separator: "\n") {
      #expect(built.text.string.contains(line), "lost artwork line: \(line)")
    }
    #expect(
      built.text.string.contains(art),
      "artwork must survive as one contiguous block, newlines included")
  }

  /// Every line of a verbatim block ends in a newline, and each newline ends a
  /// paragraph, so the block's paragraph spacing landed after every line of it:
  /// RFC 9000's Figure 13 advanced 29.25 pt per line and read double spaced (#31).
  /// The spacing belongs after the block, once — also when the block is a single
  /// line, or its text already ends in a newline.
  @Test(arguments: ["+-A-+\n| B |\n+-C-+", "+-A-+\n| B |\n+-C-+\n", "+-A-+"])
  func `artwork is spaced after the block not after every line`(art: String) throws {
    // Distinct lines, so each is found where it is.
    let built = DocumentTextBuilder.build(
      document(Preformatted(kind: .artwork, text: art)), style: style)
    let lines = art.split(separator: "\n")
    let spacings = try lines.map { line in
      let offset = try Fixtures.offset(of: String(line), in: built.text)
      let paragraph = try #require(
        built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil)
          as? NSParagraphStyle)
      return paragraph.paragraphSpacing
    }
    #expect(spacings.dropLast().allSatisfy { $0 == 0 }, "no spacing between a block's lines")
    #expect(spacings.last == style.paragraphSpacing, "the block is spaced from what follows it")
  }

  /// The body's line height leaves a gap between the lines of a vertical `|` stroke,
  /// so a diagram is set tighter. A code listing is read as text and keeps the body's.
  @Test(arguments: [
    (Preformatted.Kind.artwork, ReadingStyle().artworkLineHeightMultiple),
    (Preformatted.Kind.sourceCode, ReadingStyle().lineHeightMultiple),
  ])
  func `artwork is set tighter than code`(kind: Preformatted.Kind, expected: CGFloat) throws {
    let built = DocumentTextBuilder.build(
      document(Preformatted(kind: kind, text: "+-A-+\n| B |\n+-C-+")), style: style)
    for line in ["+-A-+", "| B |", "+-C-+"] {
      let offset = try Fixtures.offset(of: line, in: built.text)
      let paragraph = try #require(
        built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil)
          as? NSParagraphStyle)
      #expect(paragraph.lineHeightMultiple == expected, "line height of \(line)")
    }
  }

  @Test func `artwork is monospaced and never wraps`() throws {
    let art = "GET / HTTP/1.1"
    let built = DocumentTextBuilder.build(
      document(Preformatted(kind: .artwork, text: art)), style: style)
    let offset = try Fixtures.offset(of: art, in: built.text)
    let font = try #require(
      built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)
    let builder = DocumentTextBuilder(style: style)
    let narrow = builder.lineWidth("i", font: font)
    let wide = builder.lineWidth("W", font: font)
    #expect(abs(narrow - wide) < 0.01)

    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
    #expect(paragraph.lineBreakMode == .byClipping)
  }

  @Test func `artwork carries its decoration and its source`() throws {
    let content = Preformatted(kind: .artwork, text: "x", anchor: "figure-1")
    let built = DocumentTextBuilder.build(document(content), style: style)
    let offset = try #require(built.anchors.offset(of: "figure-1"))
    #expect(
      RFCDecoration(
        attributeValue: built.text.attribute(.rfcDecoration, at: offset, effectiveRange: nil))
        == .artwork)
    let box = try #require(
      built.text.attribute(.rfcVerbatim, at: offset, effectiveRange: nil) as? VerbatimBox)
    #expect(box.content.text == "x")
  }

  @Test func `narrow artwork is not scaled down`() {
    let builder = DocumentTextBuilder(style: style)
    #expect(builder.monospaceScale(for: "short", indent: 0) == 1)
  }

  @Test func `wide artwork scales to fit the measure`() {
    let builder = DocumentTextBuilder(style: style)
    let wide = String(repeating: "#", count: 129)
    let scale = builder.monospaceScale(for: wide, indent: 0)
    #expect(scale < 1)

    let font = style.monospacedFont(scale: scale)
    let width = builder.lineWidth(wide, font: font)
    #expect(width <= style.measure + 1, "129 columns must fit the measure after scaling")
  }

  @Test func `the widest line drives the scale`() {
    let builder = DocumentTextBuilder(style: style)
    let mixed = "short\n" + String(repeating: "#", count: 120) + "\nshort"
    #expect(
      builder.monospaceScale(for: mixed, indent: 0)
        == builder.monospaceScale(for: String(repeating: "#", count: 120), indent: 0))
  }

  /// Quotes nested deep enough to eat the whole measure must still leave the
  /// artwork a font size: a scale of zero is a block that draws nothing.
  @Test func `artwork indented past the measure still has a size`() {
    let builder = DocumentTextBuilder(style: style)
    #expect(builder.monospaceScale(for: "+--+", indent: style.measure) > 0)
    #expect(builder.monospaceScale(for: "+--+", indent: style.measure * 2) > 0)
  }

  @Test func `source code shows its language`() {
    let content = Preformatted(kind: .sourceCode, text: "rule = 1*DIGIT", type: "abnf")
    let built = DocumentTextBuilder.build(document(content), style: style)
    #expect(built.text.string.contains("ABNF"))
  }

  /// The label names the card, so it sits inside it: one decoration run from the
  /// label through the code, or the renderer draws the card starting below it.
  @Test func `the language label sits inside its card`() throws {
    let content = Preformatted(kind: .sourceCode, text: "rule = 1*DIGIT", type: "abnf")
    let built = DocumentTextBuilder.build(document(content), style: style)
    let label = try Fixtures.offset(of: "ABNF", in: built.text)
    let code = try Fixtures.offset(of: "rule = 1*DIGIT", in: built.text)
    var run = NSRange(location: 0, length: 0)
    let value = built.text.attribute(
      .rfcDecoration, at: label, longestEffectiveRange: &run,
      in: NSRange(location: 0, length: built.text.length))
    #expect(RFCDecoration(attributeValue: value) == .artwork)
    #expect(NSLocationInRange(code, run), "the label and the code must be one card")
  }

  /// Artwork inside a quote starts an indent step in, so the widest line has to fit
  /// what is left of the measure — scaled against the whole measure, it overruns
  /// the column by exactly the indent.
  @Test func `indented artwork scales to fit what is left of the measure`() throws {
    let wide = String(repeating: "#", count: 129)
    let quoted = Fixtures.document(
      .blockQuote([.preformatted(Preformatted(kind: .artwork, text: wide, anchor: "art"))]))
    let built = DocumentTextBuilder.build(quoted, style: style)
    let offset = try #require(built.anchors.offset(of: "art"))
    let font = try #require(
      built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)

    let rendered = DocumentTextBuilder(style: style).lineWidth(wide, font: font)
    let available = style.measure - style.indentStep
    #expect(
      abs(rendered - available) < 1,
      "the widest line fills the indented measure: \(rendered) vs \(available)")
  }

  /// A caption centres under its figure, and an indented figure's card starts at the
  /// indent — so the caption's paragraph has to start there too.
  @Test func `an indented figures caption is indented with it`() throws {
    let figure = Figure(
      title: "Packet", number: 1,
      blocks: [.preformatted(Preformatted(kind: .artwork, text: "+--+"))])
    let built = DocumentTextBuilder.build(
      Fixtures.document(.blockQuote([.figure(figure)])), style: style)
    let offset = try Fixtures.offset(of: "Figure 1: Packet", in: built.text)
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
    #expect(paragraph.alignment == .center)
    #expect(paragraph.headIndent == style.indentStep)
    #expect(paragraph.firstLineHeadIndent == style.indentStep)
  }

  /// Artwork is scaled so its widest line fills the measure. Inside the abstract —
  /// which is set smaller than the body — that scaling has to be worked out in the
  /// abstract's own style, not applied on top of a full-size answer.
  ///
  /// Quietening the abstract as a second pass over finished attributes got this
  /// wrong: the block was measured at body size, then shrunk again, so its widest
  /// line came out short of the measure by exactly the abstract's scale.
  @Test func `artwork in the abstract is scaled once in its own style`() throws {
    let wide = String(repeating: "#", count: 200)
    let document = RFCDocument(
      header: DocumentHeader(
        title: "T",
        abstract: [.preformatted(Preformatted(kind: .artwork, text: wide, anchor: "art"))]),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "S",
          blocks: [.paragraph(Paragraph(text: "body"))])
      ],
      source: .xml
    )
    let built = DocumentTextBuilder.build(document, style: style)
    let offset = try #require(built.anchors.offset(of: "art"))
    let font = try #require(
      built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)

    let ruler = DocumentTextBuilder(style: style)
    let rendered = ruler.lineWidth(wide, font: font)
    #expect(
      abs(rendered - style.measure) < 1,
      "the widest line fills the measure: \(rendered) vs \(style.measure)")
  }

  // MARK: - RFC 8792 folding (issue #64)

  private static let header =
    "=============== NOTE: '\\' line wrapping per RFC 8792 ================"

  /// A block folded to fit the page, whose single unfolded line is `unfolded`.
  private static func folded(_ unfolded: String) -> Preformatted {
    let pieces = stride(from: 0, to: unfolded.count, by: 60).map { start in
      String(unfolded.dropFirst(start).prefix(60))
    }
    let text = header + "\n\n" + pieces.joined(separator: "\\\n")
    return Preformatted(kind: .sourceCode, text: text, anchor: "folded")
  }

  /// The column is wider than the page the folds were made for, so the reader
  /// shows what the author wrote, and the header that explained the folds goes.
  @Test func `a folded block that fits is shown unfolded`() {
    let unfolded = "{\"key\": \"" + String(repeating: "a", count: 50) + "\"}"
    let content = Self.folded(unfolded)
    let built = DocumentTextBuilder.build(document(content), style: style)
    #expect(built.text.string.contains(unfolded))
    #expect(!built.text.string.contains("line wrapping per RFC 8792"))
  }

  /// Unfolded, it would have to be scaled down to fit; the published folds read
  /// better than that, and they keep the header that explains them.
  @Test func `a folded block that does not fit is shown as published`() {
    let content = Self.folded(String(repeating: "b", count: 300))
    let built = DocumentTextBuilder.build(document(content), style: style)
    #expect(built.text.string.contains(content.text))
  }

  /// Whether it fits is a question about this column, so a narrow one keeps the
  /// folds that a wide one takes out.
  @Test func `whether it fits is measured against the column`() {
    let unfolded = String(repeating: "c", count: 65)
    let content = Self.folded(unfolded)
    let wide = DocumentTextBuilder(style: style)
    let narrow = DocumentTextBuilder(style: ReadingStyle(measure: 300))
    #expect(wide.displayedText(of: content, indent: 0) == unfolded)
    #expect(narrow.displayedText(of: content, indent: 0) == content.text)
  }

  /// What is shown changes; what the block is does not. "Copy Figure" and the
  /// accessibility element read the published block from its box.
  @Test func `the box keeps the published block`() throws {
    let content = Self.folded("short enough to fit once unfolded, and folded anyway")
    let built = DocumentTextBuilder.build(document(content), style: style)
    let offset = try #require(built.anchors.offset(of: "folded"))
    let box = try #require(
      built.text.attribute(.rfcVerbatim, at: offset, effectiveRange: nil) as? VerbatimBox)
    #expect(box.content.text == content.text)
  }

  @Test func `a block that is not folded is shown as it is`() {
    let content = Preformatted(kind: .artwork, text: "a line ending in a backslash \\\nnext")
    let builder = DocumentTextBuilder(style: style)
    #expect(builder.displayedText(of: content, indent: 0) == content.text)
  }

  /// 168 artwork blocks in 65 published RFCXML documents carry a literal tab, and
  /// the verbatim style sets no tab stops, so each tab went to the next default
  /// stop, a distance in points unrelated to the monospaced columns
  /// around it, and the figure sheared (#31). The RFC Editor's own text rendering
  /// expands them to eight-column stops, each line on its own.
  @Test func `a tab in artwork is spaces to the next eighth column`() {
    let content = Preformatted(kind: .artwork, text: "\t|\n  \t|\nabcdefgh\t|")
    let builder = DocumentTextBuilder(style: style)
    #expect(
      builder.displayedText(of: content, indent: 0)
        == "        |\n        |\nabcdefgh        |")
  }

  /// Unfolded first: a tab that opens a continuation is the author's and stays, and
  /// it is expanded at its column in the rejoined line. Expanded first, it became
  /// eight spaces that unfolding stripped as the fold's indent.
  @Test func `a folded block's tabs are expanded where the unfolded line puts them`() {
    let text = Self.header + "\n\nabc\\\n\tx"
    let content = Preformatted(kind: .artwork, text: text)
    let builder = DocumentTextBuilder(style: style)
    #expect(builder.displayedText(of: content, indent: 0) == "abc     x")
  }

  /// A tab that ends a line draws nothing, so it is not counted: expanded, trailing
  /// tabs made some of RFC 8902's figures 80 columns wide where what they show is
  /// 66, and so drew them smaller.
  @Test func `a tab that ends a line adds no width`() {
    let content = Preformatted(kind: .artwork, text: "abc\t\nde  \t\t\n\tf")
    let builder = DocumentTextBuilder(style: style)
    #expect(builder.displayedText(of: content, indent: 0) == "abc\nde\n        f")
  }

  /// Scaled by the columns it is drawn in, not by its characters: fifteen tabs are
  /// 120 columns.
  @Test func `a block with tabs scales by its expanded width`() {
    let builder = DocumentTextBuilder(style: style)
    let tabbed = Preformatted(kind: .artwork, text: String(repeating: "\t", count: 15) + "|")
    let spaced = String(repeating: " ", count: 120) + "|"
    let text = builder.displayedText(of: tabbed, indent: 0)
    #expect(text == spaced)
    #expect(builder.monospaceScale(for: text, indent: 0) < 1)
  }

  /// What is shown changes; what the block is does not.
  @Test func `the box keeps a tabbed block's tabs`() throws {
    let content = Preformatted(kind: .artwork, text: "\t|", anchor: "tabbed")
    let built = DocumentTextBuilder.build(document(content), style: style)
    let offset = try #require(built.anchors.offset(of: "tabbed"))
    let box = try #require(
      built.text.attribute(.rfcVerbatim, at: offset, effectiveRange: nil) as? VerbatimBox)
    #expect(box.content.text == "\t|")
    #expect(!built.text.string.contains("\t"))
  }
}
