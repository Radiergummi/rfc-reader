import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Annotations: a note's Markdown")
struct NoteMarkdownTests {
  typealias Span = NoteBody.Span

  /// Every construct of the scope, nested where it nests, with the characters
  /// Markdown would otherwise read as something else.
  static let bodies: [NoteBody] = [
    NoteBody([.paragraph([Span("A plain sentence.")])]),
    NoteBody([
      .paragraph([
        Span("Some "), Span("emphasis", style: .emphasis), Span(", "),
        Span("strong", style: .strong), Span(", "), Span("gone", style: .strikethrough),
        Span(" and "), Span("code()", style: .code), Span("."),
      ])
    ]),
    NoteBody([
      .paragraph([
        Span("all three", style: [.emphasis, .strong, .strikethrough]),
        Span(" then "), Span("bold", style: .strong), Span("italic", style: .emphasis),
        Span("bolder", style: [.strong, .emphasis]), Span("."),
      ])
    ]),
    NoteBody([
      .paragraph([
        Span("See "), Span("RFC 9110", link: URL(string: "rfc://9110#section-4.2")),
        Span(" and "),
        Span("the site", style: .strong, link: URL(string: "https://www.rfc-editor.org/(x)")),
        Span("."),
      ])
    ]),
    NoteBody([
      .paragraph([Span("Characters: \\ * _ ~ ` [ ] < > & ! # - + = | 1. 2) www.example.org")]),
      .paragraph([Span("# not a heading")]),
      .paragraph([Span("- not a list")]),
      .paragraph([Span("12. not numbered")]),
      .paragraph([Span("https://example.org is text")]),
    ]),
    NoteBody([
      .paragraph([Span("tick ` inside", style: .code), Span(" and "), Span("`edge`", style: .code)])
    ]),
    NoteBody([.paragraph([Span("a line"), Span("\n"), Span("and the next")])]),
    NoteBody([
      .paragraph([Span("Before the list.")]),
      .list(
        NoteBody.List(
          isOrdered: false,
          items: [
            NoteBody.Item(
              [Span("one")],
              lists: [
                NoteBody.List(
                  isOrdered: true,
                  items: [
                    NoteBody.Item([Span("nested "), Span("first", style: .emphasis)]),
                    NoteBody.Item(
                      [Span("second")],
                      lists: [
                        NoteBody.List(isOrdered: false, items: [NoteBody.Item([Span("deep")])])
                      ]),
                  ])
              ]),
            NoteBody.Item([Span("- two, starting with a dash")]),
          ])),
      .list(
        NoteBody.List(
          isOrdered: true,
          items: (1...11).map { NoteBody.Item([Span("item \($0)")]) })),
      .paragraph([Span("After.")]),
    ]),
  ]

  @Test(arguments: bodies)
  func `a body reads back from its Markdown as itself`(body: NoteBody) {
    #expect(NoteBody(markdown: body.markdown) == body, "\(body.markdown)")
  }

  @Test(arguments: bodies)
  func `a body's Markdown is the Markdown of what it reads back as`(body: NoteBody) {
    let markdown = body.markdown
    #expect(NoteBody(markdown: markdown).markdown == markdown)
  }

  @Test func `the Markdown is spelled as CommonMark's own`() {
    let body = NoteBody([
      .paragraph([Span("A "), Span("b", style: .strong), Span(" "), Span("c", style: .emphasis)]),
      .list(
        NoteBody.List(
          isOrdered: true,
          items: [
            NoteBody.Item(
              [Span("x")],
              lists: [NoteBody.List(isOrdered: false, items: [NoteBody.Item([Span("y")])])])
          ])),
    ])
    #expect(body.markdown == "A **b** *c*\n\n1. x\n   - y")
  }

  @Test func `what lies outside the scope becomes paragraphs of its text`() {
    let body = NoteBody(
      markdown:
        "# A heading\n\n> quoted\n\n```\nlet x\n```\n\n| a | b |\n|---|---|\n| c | d |\n\n![alt](i.png)"
    )
    #expect(
      body
        == NoteBody([
          .paragraph([Span("A heading")]), .paragraph([Span("quoted")]),
          .paragraph([Span("let x")]), .paragraph([Span("a b")]), .paragraph([Span("c d")]),
          .paragraph([Span("alt")]),
        ]))
  }

  @Test func `white space at a styled run's edge is not styled`() {
    let body = NoteBody([.paragraph([Span("a"), Span(" bold ", style: .strong), Span("b")])])
    #expect(body.markdown == "a **bold** b")
  }

  /// A delimiter beside punctuation opens or closes only where white space or more
  /// punctuation is on its other side: `a**(b)**c` reads back as its asterisks.
  @Test(arguments: [
    [Span("a"), Span("(b)", style: .strong), Span("c")],
    [Span("x"), Span("「語」", style: .emphasis), Span("y")],
    [Span("so"), Span("-gone", style: .strikethrough)],
  ])
  func `a style CommonMark cannot spell beside a letter goes, its text kept`(spans: [Span]) {
    let body = NoteBody([.paragraph(spans)])
    let text = spans.map(\.text).joined()
    #expect(body == NoteBody([.paragraph([Span(text)])]))
    #expect(NoteBody(markdown: body.markdown) == body, "\(body.markdown)")
  }

  @Test func `a style beside punctuation that CommonMark can spell is kept`() {
    let body = NoteBody([.paragraph([Span("a "), Span("(b)", style: .strong), Span(", c")])])
    #expect(body.markdown == "a **(b)**, c")
    #expect(NoteBody(markdown: body.markdown) == body)
  }

  @Test func `two lists of one kind side by side are one`() {
    let item = NoteBody.Item([Span("x")])
    let body = NoteBody([
      .list(NoteBody.List(isOrdered: false, items: [item])),
      .list(NoteBody.List(isOrdered: false, items: [item])),
    ])
    #expect(body.blocks == [.list(NoteBody.List(isOrdered: false, items: [item, item]))])
  }

  @Test func `a mail address in the text reads back as a link to it`() {
    let body = NoteBody([.paragraph([Span("write to a@example.org")])])
    #expect(
      NoteBody(markdown: body.markdown)
        == NoteBody([
          .paragraph([
            Span("write to "), Span("a@example.org", link: URL(string: "mailto:a@example.org")),
          ])
        ]))
  }

  @Test func `an empty body is no Markdown`() {
    #expect(NoteBody([.paragraph([Span("  ")])]).isEmpty)
    #expect(NoteBody(markdown: "").isEmpty)
    #expect(NoteBody().markdown.isEmpty)
  }
}
