import Foundation
import Testing

@testable import RFCReaderKit

/// That every canonical body reads back from its Markdown as itself (#523), where
/// styles nest and cross, and that the canonical form loses no text in getting there.
@Suite("Annotations: a note's Markdown reads back")
struct NoteMarkdownRoundTripTests {
  typealias Span = NoteBody.Span

  @Test func `a struck word inside an italic sentence keeps both`() {
    let body = NoteBody([
      .paragraph([
        Span("some ", style: .emphasis), Span("gone", style: [.emphasis, .strikethrough]),
        Span(" text", style: .emphasis),
      ])
    ])
    #expect(body.markdown == "*some ~~gone~~ text*")
    #expect(NoteBody(markdown: body.markdown) == body)
  }

  @Test func `a struck word inside a bold sentence keeps both`() {
    let body = NoteBody([
      .paragraph([
        Span("some ", style: .strong), Span("gone", style: [.strong, .strikethrough]),
        Span(" text", style: .strong),
      ])
    ])
    #expect(body.markdown == "**some ~~gone~~ text**")
    #expect(NoteBody(markdown: body.markdown) == body)
  }

  @Test(arguments: [
    // Italic over "a b", struck over "b c": the two cross.
    [
      Span("a ", style: .emphasis), Span("b", style: [.emphasis, .strikethrough]),
      Span(" c", style: .strikethrough),
    ],
    // Two kinds of delimiter inside a word.
    [Span("ab", style: [.strikethrough, .emphasis]), Span("b")],
  ])
  func `styles CommonMark cannot spell together read back, their text kept`(spans: [Span]) {
    let body = NoteBody([.paragraph(spans)])
    #expect(NoteBody(markdown: body.markdown) == body, "\(body.markdown)")
    #expect(body.plainText == spans.map(\.text).joined())
  }

  /// Each save normalizes the note on the main actor: a paragraph of many crossings
  /// is not to take a parse for every style for every style it drops.
  @Test(.timeLimit(.minutes(1)))
  func `a paragraph of a hundred crossing styles is spelled in time`() {
    let spans = (0..<100).flatMap { index in
      [
        Span("a\(index) ", style: .emphasis), Span("b ", style: [.emphasis, .strikethrough]),
        Span("c ", style: .strikethrough), Span("d "),
      ]
    }
    let body = NoteBody([.paragraph(spans)])
    #expect(NoteBody(markdown: body.markdown) == body)
    #expect(body.plainText == spans.map(\.text).joined().trimmingCharacters(in: .whitespaces))
  }

  /// A few thousand bodies from a seeded generator: their parts are the scope's
  /// styles, links, line breaks and the characters a delimiter flanks by.
  @Test func `every canonical body reads back as itself, and keeps its text`() {
    var generator = Generator(seed: 0x5EED)
    for _ in 0..<3000 {
      let spans = generator.spans()
      let body = NoteBody([.paragraph(spans)])
      #expect(
        NoteBody(markdown: body.markdown) == body,
        "\(body.blocks) → \(body.markdown.debugDescription) → \(NoteBody(markdown: body.markdown).blocks)"
      )
      // The delimited styles alone are what the canonical form may take off.
      let plain = NoteBody([
        .paragraph(
          spans.map { Span($0.text, style: $0.style.intersection(.code), link: $0.link) })
      ])
      #expect(
        body.plainText == plain.plainText,
        "\(body.plainText.debugDescription) vs \(plain.plainText.debugDescription) from \(spans)")
    }
  }

  /// A linear congruential generator, so the bodies are the same on every run.
  private struct Generator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next(_ bound: Int) -> Int {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((state >> 33) % UInt64(bound))
    }

    private static let pieces = [
      "a", "b", "word", " ", "  ", "(", ")", ".", ",", "-", "「", "」", "*", "_", "~", "`",
      "[", "]", "1.", "#", "x y",
    ]
    private static let styles: [NoteBody.Style] = [
      [], [], .emphasis, .strong, .strikethrough, .code, [.emphasis, .strong],
      [.emphasis, .strikethrough], [.strong, .strikethrough],
      [.emphasis, .strong, .strikethrough],
    ]

    mutating func spans() -> [Span] {
      (0..<(1 + next(6))).map { _ in
        if next(12) == 0 { return Span("\n") }
        let text = (0..<(1 + next(3))).map { _ in Self.pieces[next(Self.pieces.count)] }
          .joined()
        let link = next(10) == 0 ? URL(string: "https://example.org/\(next(3))") : nil
        return Span(text, style: Self.styles[next(Self.styles.count)], link: link)
      }
    }
  }
}
