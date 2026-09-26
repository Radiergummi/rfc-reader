import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A decoration has to reach the renderer as *one run* spanning the whole block.
///
/// `RFCTextLayoutFragment` asks for the attribute's `effectiveRange` to decide
/// whether a fragment is the first, last or a middle piece of its block -- which is
/// what caps the band's rounded corners and what makes every fragment agree on one
/// left edge. If contiguous paragraphs do not merge into one run, each line reports
/// itself as a complete decoration: every line gets its own fully rounded card at
/// its own indent, and a block of artwork reads as a staircase.
@Suite("Decoration runs merge across a block")
struct DecorationRunTests {
  private let style = ReadingStyle()

  /// The renderer's own lookup, called rather than restated: asking
  /// `NSAttributedString` directly here would leave the suite green even if
  /// `decorationSpan` went back to the `effectiveRange` that caused the staircase.
  private func run(at offset: Int, in text: NSAttributedString) throws -> NSRange {
    let span = try #require(
      FragmentGeometry.decorationSpan(in: text, fragment: NSRange(location: offset, length: 1)),
      "no decoration at \(offset)"
    )
    return span.runRange
  }

  @Test func multiLineArtworkIsOneDecorationRun() throws {
    let art = "line one\nline two\nline three\nline four"
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: art, anchor: "figure-1"))),
      style: style
    )
    let start = try #require(built.anchors.offset(of: "figure-1"))
    let run = try run(at: start, in: built.text)

    // Every line of the block, not just the first.
    for needle in ["line one", "line two", "line three", "line four"] {
      let offset = try Fixtures.offset(of: needle, in: built.text)
      #expect(NSLocationInRange(offset, run), "\(needle) must fall inside the one decoration run")
    }
  }

  @Test func aStackedTablesCellsAreOneDecorationRun() throws {
    let table = RFCKit.Table(
      title: nil,
      number: nil,
      header: [[[Inline.text("Field")], [Inline.text("Meaning")]]],
      rows: [
        [
          [Inline.text("alpha")],
          [Inline.text(String(repeating: "a long prose description ", count: 4))],
        ],
        [
          [Inline.text("beta")],
          [Inline.text(String(repeating: "another long description ", count: 4))],
        ],
      ],
      anchor: "table-1"
    )
    let built = DocumentTextBuilder.build(Fixtures.document(.table(table)), style: style)
    let first = try Fixtures.offset(of: "alpha", in: built.text)
    let run = try run(at: first, in: built.text)
    let last = try Fixtures.offset(of: "beta", in: built.text)
    #expect(NSLocationInRange(last, run), "all of a stacked table's cells belong to one band")
  }

  /// Two verbatim blocks in a row carry the same `.artwork` value with nothing
  /// between them, so the decoration alone reads them as one card — and a source
  /// block's language label then sits mid-card. Each block is its own card.
  @Test(arguments: [
    [
      Preformatted(kind: .artwork, text: "AAAA"),
      Preformatted(kind: .sourceCode, text: "BBBB", type: "abnf"),
    ],
    [
      Preformatted(kind: .sourceCode, text: "AAAA", type: "abnf"),
      Preformatted(kind: .sourceCode, text: "BBBB", type: "abnf"),
    ],
    [Preformatted(kind: .artwork, text: "AAAA"), Preformatted(kind: .artwork, text: "BBBB")],
  ])
  func adjacentVerbatimBlocksAreTwoCards(blocks: [Preformatted]) throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(blocks[0]), .preformatted(blocks[1])), style: style)
    let first = try Fixtures.offset(of: "AAAA", in: built.text)
    let second = try Fixtures.offset(of: "BBBB", in: built.text)
    let firstRun = try run(at: first, in: built.text)
    #expect(!NSLocationInRange(second, firstRun), "the second block must start its own card")
    let secondRun = try run(at: second, in: built.text)
    // Adjacent, so each has to know it is cut against the other, or both cap the
    // shared edge and the cards overlap (`AdjacentCardTests` lays that out).
    let last = try #require(
      FragmentGeometry.decorationSpan(
        in: built.text, fragment: NSRange(location: NSMaxRange(firstRun) - 1, length: 1)))
    let next = try #require(
      FragmentGeometry.decorationSpan(
        in: built.text, fragment: NSRange(location: secondRun.location, length: 1)))
    #expect(last.meetsCardBelow && next.meetsCardAbove, "two cards that meet must know it")
    if blocks[1].type != nil {
      let string = built.text.string as NSString
      let label = string.range(
        of: "ABNF", range: NSRange(location: first, length: string.length - first)
      ).location
      #expect(NSLocationInRange(label, secondRun), "the label opens the card it names")
    }
  }

  /// Two different decorations must still not merge into each other.
  @Test func differentDecorationsStayDifferentRuns() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .blockQuote([.paragraph(Paragraph(text: "quoted"))]),
        .aside([.paragraph(Paragraph(text: "noted"))])
      ),
      style: style
    )
    let quoted = try Fixtures.offset(of: "quoted", in: built.text)
    let noted = try Fixtures.offset(of: "noted", in: built.text)
    #expect(!NSLocationInRange(noted, try run(at: quoted, in: built.text)))
  }

  /// The sweeping form of the two tests above, over whole real documents.
  ///
  /// If a block's decoration is ever split — a separator emitted without it, a new
  /// block kind that forgets `decorate(from:with:)` — the halves show up here as
  /// two runs of the same decoration with nothing but whitespace between them.
  /// That is the shape the staircase had, and this catches it without anyone
  /// having to write a fixture for the new block kind.
  @Test(arguments: ["rfc8999.xml", "rfc2119.txt"])
  func noBlockIsSplitIntoTwoRuns(fixture: String) throws {
    let document = fixture.hasSuffix(".xml") ? try Fixtures.rfc8999() : try Fixtures.rfc2119()
    let built = DocumentTextBuilder.build(document, style: style)
    let text = built.text.string as NSString

    var previous: (decoration: RFCDecoration, range: NSRange)?
    built.text.enumerateAttribute(
      .rfcDecoration, in: NSRange(location: 0, length: built.text.length)
    ) { value, range, _ in
      guard let decoration = RFCDecoration(attributeValue: value) else { return }
      defer { previous = (decoration, range) }
      guard let previous, previous.decoration == decoration else { return }
      let gap = NSRange(
        location: NSMaxRange(previous.range), length: range.location - NSMaxRange(previous.range))
      guard gap.length > 0 else { return }
      let between = text.substring(with: gap)
      #expect(
        between.contains(where: { !$0.isWhitespace }),
        "\(fixture): two \(decoration) runs separated only by whitespace — the block was split at \(gap)"
      )
    }
  }
}
