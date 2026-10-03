import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Selection text")
struct SelectionTextTests {
  private func copied(_ inlines: [Inline]) -> String {
    SelectionText.plainText(of: Fixtures.inlineRun(inlines))
  }

  @Test func `ordinary prose is copied as it is`() {
    #expect(copied([.text("hello world")]) == "hello world")
  }

  /// A table cell's line break is set as a line separator, to keep its row one
  /// paragraph (#506), but is copied as the newline it was before.
  @Test func `a table cell's line break is copied as a newline`() throws {
    let table = RFCKit.Table(
      title: nil, header: [],
      rows: [RFCKit.Table.Row(cells: [[.text("first"), .lineBreak, .text("second")]])])
    let built = DocumentTextBuilder.build(Fixtures.document(.table(table)), style: ReadingStyle())
    let start = try Fixtures.offset(of: "first", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: start, length: ("first\u{2028}second" as NSString).length))
    #expect(SelectionText.plainText(of: selection) == "first\nsecond")
  }

  /// The whole reason this exists: the chip's symbol rides in the text as an
  /// object-replacement character, which means nothing off the screen.
  @Test func `no object replacement character reaches the pasteboard`() {
    let text = copied([
      .text("see "), .crossReference(CrossReference(target: .document(.rfc(9110), section: nil))),
    ])
    #expect(
      !text.contains("\u{FFFC}"), "U+FFFC is the chip's symbol, not text: \(text.debugDescription)")
    #expect(!text.contains("\u{2060}"), "nor the word joiner behind it")
  }

  @Test func `a reference is copied with its brackets`() {
    #expect(
      copied([.crossReference(CrossReference(target: .document(.rfc(9110), section: nil)))])
        == "[RFC 9110]")
  }

  /// The brackets earn their place here: on screen the chip's tint separates two
  /// adjacent references, and a pasteboard has no tint.
  @Test func `adjacent references do not run together`() {
    let text = copied([
      .text("see "),
      .crossReference(CrossReference(target: .document(.rfc(9110), section: nil))),
      .text(" "),
      .crossReference(CrossReference(target: .document(.rfc(9111), section: nil))),
    ])
    #expect(text == "see [RFC 9110] [RFC 9111]")
  }

  @Test func `a section reference is copied as the phrase it reads`() {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    #expect(copied([.crossReference(xref)]) == "Section 4.2 of [RFC 9110]")
  }

  /// Non-breaking spaces stop a chip wrapping mid-label in a narrow column. That is
  /// a fact about a text view, and has no business in a mail or a terminal.
  @Test func `typesetting does not travel to the pasteboard`() {
    let text = copied([
      .crossReference(CrossReference(target: .document(.rfc(9110), section: "4.2")))
    ])
    #expect(
      !text.contains("\u{00A0}"), "a non-breaking space is typesetting: \(text.debugDescription)")
  }

  @Test func `an authors own words are copied as written`() {
    let xref = CrossReference(
      target: .document(.rfc(9110), section: "4.2"), text: "the caching rules")
    #expect(copied([.text("see "), .crossReference(xref)]) == "see the caching rules")
  }

  @Test func `a documents own tag is copied as written`() {
    let xref = CrossReference(target: .document(.rfc(9000), section: nil), text: "[QUIC-TRANSPORT]")
    #expect(copied([.crossReference(xref)]) == "[QUIC-TRANSPORT]")
  }

  @Test func `an anchor reference keeps its own text`() {
    let xref = CrossReference(target: .anchor("section-3"), text: "Section 3")
    #expect(copied([.text("in "), .crossReference(xref)]) == "in Section 3")
  }

  /// A chip is one thing on screen; there is no half of it that means anything. A
  /// selection that starts inside one still yields a whole label rather than the
  /// tail of one — which is also what stops a selection beginning after the symbol
  /// from copying a bare fragment.
  @Test func `a partly selected reference still copies whole`() {
    let whole = Fixtures.inlineRun([
      .crossReference(CrossReference(target: .document(.rfc(9110), section: nil)))
    ])
    let tail = whole.attributedSubstring(from: NSRange(location: whole.length - 2, length: 2))
    #expect(SelectionText.plainText(of: tail) == "[RFC 9110]")
  }

  @Test func `an empty selection copies nothing`() {
    #expect(SelectionText.plainText(of: NSAttributedString(string: "")) == "")
  }

  // MARK: - A block shown folded (#212)

  /// A JSON block in RFC 8792's shape, folded once, in a column too narrow to show
  /// it unfolded, so the storage holds it as published.
  private static let folded = Preformatted(
    kind: .sourceCode,
    text:
      "=============== NOTE: '\\' line wrapping per RFC 8792 ================\n\n{\"key\": \"a long \\\n      value\"}",
    type: "json")

  private static func narrowBuild() -> NSAttributedString {
    DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph(text: "Before the figure.")), .preformatted(folded)),
      style: ReadingStyle(measure: 120)
    ).text
  }

  private static func selection(
    from start: String, through end: String, in text: NSAttributedString
  )
    throws -> NSAttributedString
  {
    let first = try Fixtures.offset(of: start, in: text)
    let last = try Fixtures.offset(of: end, in: text) + (end as NSString).length
    return text.attributedSubstring(from: NSRange(location: first, length: last - first))
  }

  @Test func `a block too wide for the column is stored folded`() {
    #expect(Self.narrowBuild().string.contains(Self.folded.text))
  }

  /// What Copy Figure gives, whatever the window's width.
  @Test func `a whole folded block is copied unfolded`() throws {
    let text = Self.narrowBuild()
    let selection = try Self.selection(from: "====", through: "value\"}", in: text)
    #expect(SelectionText.plainText(of: selection) == Self.folded.unfoldedText)
  }

  @Test func `a selection across a fold is copied with the fold undone`() throws {
    let text = Self.narrowBuild()
    let selection = try Self.selection(from: "long", through: "value", in: text)
    #expect(SelectionText.plainText(of: selection) == "long value")
  }

  /// The prose before a figure is copied as it is, and the figure unfolded after it,
  /// without the block's language label, which is the reader's and not the document's.
  @Test func `prose and a folded block are copied together`() throws {
    let text = Self.narrowBuild()
    let selection = try Self.selection(from: "Before", through: "value\"}", in: text)
    #expect(
      SelectionText.plainText(of: selection) == "Before the figure.\n" + Self.folded.unfoldedText)
  }

  /// On a published RFC: RFC 9985's YANG example in a column too narrow to show it
  /// unfolded copies as Copy Figure does.
  @Test func `rfc9985's folded block copies as Copy Figure does`() throws {
    let built = DocumentTextBuilder.build(
      try Fixtures.document(named: "rfc9985.xml"), style: ReadingStyle(measure: 300))
    let text = built.text
    let locator = try Fixtures.offset(of: "xmlns:bfd-mki=", in: text)
    var run = NSRange(location: 0, length: 0)
    let box = try #require(
      text.attribute(
        .rfcVerbatim, at: locator, longestEffectiveRange: &run,
        in: NSRange(location: 0, length: text.length)) as? VerbatimBox)
    let string = text.string as NSString
    let header = string.range(of: "NOTE:", range: run)
    try #require(header.location != NSNotFound, "the block is stored folded")
    let start = string.lineRange(for: header).location
    let selection = text.attributedSubstring(
      from: NSRange(location: start, length: NSMaxRange(run) - start))
    // The storage ends every block with a newline; the block's own text may not.
    let figure = FigureCopy.pasteboardText(for: box.content)
    #expect(
      SelectionText.plainText(of: selection) == (figure.hasSuffix("\n") ? figure : figure + "\n"))
  }

  #if !canImport(UIKit) && canImport(AppKit)
    /// `NSTextView` asks for each flavor by its legacy name, which never equals the
    /// modern constant: a copy that switched on `.string` alone rewrote nothing.
    @Test func `a flavor is recognized by its legacy name as by its modern one`() {
      let asked: [(String, SelectionText.Flavor?)] = [
        ("NSStringPboardType", .plain),
        ("public.utf8-plain-text", .plain),
        ("NeXT Rich Text Format v1.0 pasteboard type", .rtf),
        ("public.rtf", .rtf),
        ("NeXT RTFD pasteboard type", .rtfd),
        ("com.apple.flat-rtfd", .rtfd),
        ("public.html", nil),
      ]
      for (name, flavor) in asked {
        #expect(SelectionText.flavor(of: NSPasteboard.PasteboardType(name)) == flavor, "\(name)")
      }
    }
  #endif

  /// A rich paste of a rendered diagram would otherwise carry its grid as characters
  /// in a clear color: the field names pasted, every border invisible.
  @Test func `a rich copy shows the borders a rendered diagram hides`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: ReadingStyle())
    let rich = try #require(SelectionText.richText(of: built.text))
    #expect(rich.string == built.text.string)
    var hidden = 0
    rich.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: rich.length)) {
      value, _, _ in
      if let color = value as? PlatformColor, color == DocumentTextBuilder.hiddenColor {
        hidden += 1
      }
    }
    #expect(hidden == 0)
  }
}
