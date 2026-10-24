import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Annotations: a note as the editor edits it")
struct NoteTextTests {
  typealias Span = NoteBody.Span

  private let font = PlatformFont.systemFont(ofSize: 13, weight: .regular)

  @Test(arguments: NoteMarkdownTests.bodies)
  func `the editor's text reads back as the body it was made from`(body: NoteBody) {
    #expect(NoteText.body(of: NoteText.attributed(body, font: font)) == body)
  }

  @Test func `a list item is a paragraph with its lists and no marker`() {
    let body = NoteBody([
      .list(
        NoteBody.List(
          isOrdered: false,
          items: [
            NoteBody.Item(
              [Span("one")],
              lists: [NoteBody.List(isOrdered: true, items: [NoteBody.Item([Span("two")])])])
          ]))
    ])
    let text = NoteText.attributed(body, font: font)
    #expect(text.string == "one\ntwo")
    let inner = text.attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle
    #expect(inner?.textLists.map(\.markerFormat) == [.disc, .decimal])
  }

  @Test func `a paste keeps the scope and loses fonts, sizes and colors`() {
    let pasted = NSMutableAttributedString()
    let heading = PlatformFont.systemFont(ofSize: 28, weight: .bold)
    pasted.append(
      NSAttributedString(
        string: "Heading\n",
        attributes: [.font: heading, .foregroundColor: PlatformColor.red]))
    let serif = PlatformFont(name: "Times New Roman", size: 18) ?? font
    pasted.append(
      NSAttributedString(
        string: "Big serif text with ",
        attributes: [.font: serif, .backgroundColor: PlatformColor.yellow]))
    pasted.append(
      NSAttributedString(
        string: "code",
        attributes: [.font: PlatformFont.monospacedFont(ofSize: 9, weight: .regular)]))
    pasted.append(
      NSAttributedString(
        string: " and a link",
        attributes: [.font: font, .link: URL(string: "https://example.org")!]))
    let reduced = NoteText.reduced(pasted, font: font)
    #expect(
      NoteText.body(of: reduced)
        == NoteBody([
          .paragraph([Span("Heading", style: .strong)]),
          .paragraph([
            Span("Big serif text with "), Span("code", style: .code), Span(" "),
            Span("and a link", link: URL(string: "https://example.org")),
          ]),
        ]))
    var fonts: Set<CGFloat> = []
    reduced.enumerateAttribute(.font, in: NSRange(location: 0, length: reduced.length)) {
      value, _, _ in
      if let font = value as? PlatformFont { fonts.insert(font.pointSize) }
    }
    #expect(fonts == [13])
    var colored = false
    reduced.enumerateAttributes(in: NSRange(location: 0, length: reduced.length)) {
      attributes, _, _ in
      if attributes[.foregroundColor] != nil || attributes[.backgroundColor] != nil {
        colored = true
      }
    }
    #expect(!colored)
  }

  @Test(arguments: [NSTextList.MarkerFormat.disc, .decimal])
  func `an item's own text between tabs is no marker, and is kept`(
    format: NSTextList.MarkerFormat
  ) {
    let style = NSMutableParagraphStyle()
    style.textLists = [NSTextList(markerFormat: format, options: 0)]
    let typed = NSAttributedString(
      string: "\tkey\tvalue", attributes: [.font: font, .paragraphStyle: style])
    // The tab at the paragraph's edge goes, as white space there always does.
    #expect(NoteText.body(of: typed).plainText == "key\tvalue")
  }

  @Test func `a number written into pasted numbered text is dropped`() {
    let style = NSMutableParagraphStyle()
    style.textLists = [NSTextList(markerFormat: .decimal, options: 0)]
    let list = style.textLists[0]
    let pasted = NSAttributedString(
      string:
        "\t\(list.marker(forItemNumber: 1))\tfirst\n\t\(list.marker(forItemNumber: 2))\tsecond",
      attributes: [.font: font, .paragraphStyle: style])
    #expect(NoteText.body(of: pasted).plainText == "first\nsecond")
  }

  @Test func `a marker written into pasted list text is dropped`() {
    let list = NSTextList(markerFormat: .disc, options: 0)
    let style = NSMutableParagraphStyle()
    style.textLists = [list]
    let pasted = NSAttributedString(
      string: "\t•\tfirst\n\t•\tsecond", attributes: [.font: font, .paragraphStyle: style])
    #expect(
      NoteText.body(of: pasted)
        == NoteBody([
          .list(
            NoteBody.List(
              isOrdered: false,
              items: [NoteBody.Item([Span("first")]), NoteBody.Item([Span("second")])]))
        ]))
  }

  @Test func `an item that starts a list deeper keeps its depth`() {
    let outer = NSTextList(markerFormat: .disc, options: 0)
    let inner = NSTextList(markerFormat: .circle, options: 0)
    let style = NSMutableParagraphStyle()
    style.textLists = [outer, inner]
    let text = NSAttributedString(
      string: "deep", attributes: [.font: font, .paragraphStyle: style])
    #expect(
      NoteText.body(of: text).markdown == "-\n  - deep")
  }

  /// The editor opens what it saved: an item with no text of its own, only a deeper
  /// list, keeps its place in the list.
  @Test func `an item that only opens a deeper list reads back as itself`() {
    for markdown in ["-\n  - deep", "Before\n\n-\n  - deep"] {
      let body = NoteBody(markdown: markdown)
      #expect(body.markdown == markdown)
      #expect(NoteText.body(of: NoteText.attributed(body, font: font)) == body)
    }
  }

  // MARK: - Formatting

  private func editable(_ body: NoteBody) -> NSMutableAttributedString {
    NSMutableAttributedString(attributedString: NoteText.attributed(body, font: font))
  }

  @Test func `a style turns on over a selection, and off where all of it has it`() {
    let text = editable(NoteBody([.paragraph([Span("one two three")])]))
    NoteText.toggle(.strong, in: text, range: NSRange(location: 4, length: 3), font: font)
    #expect(
      NoteText.body(of: text).markdown == "one **two** three")
    NoteText.toggle(.strong, in: text, range: NSRange(location: 0, length: 7), font: font)
    #expect(NoteText.body(of: text).markdown == "**one two** three")
    NoteText.toggle(.strong, in: text, range: NSRange(location: 0, length: 7), font: font)
    #expect(NoteText.body(of: text).markdown == "one two three")
    NoteText.toggle(.code, in: text, range: NSRange(location: 8, length: 5), font: font)
    #expect(NoteText.body(of: text).markdown == "one two `three`")
  }

  @Test func `paragraphs become a list, join the one before, and leave it again`() {
    let text = editable(
      NoteBody([
        .list(NoteBody.List(isOrdered: true, items: [NoteBody.Item([Span("first")])])),
        .paragraph([Span("second")]), .paragraph([Span("third")]),
      ]))
    let rest = NSRange(location: 6, length: text.length - 6)
    NoteText.toggleList(ordered: true, in: text, range: rest, font: font)
    #expect(NoteText.body(of: text).markdown == "1. first\n2. second\n3. third")
    NoteText.toggleList(ordered: true, in: text, range: rest, font: font)
    #expect(NoteText.body(of: text).markdown == "1. first\n\nsecond\n\nthird")
    NoteText.toggleList(ordered: false, in: text, range: rest, font: font)
    #expect(NoteText.body(of: text).markdown == "1. first\n\n- second\n- third")
  }

  @Test func `items nest a level deeper and come back out`() {
    let text = editable(
      NoteBody([
        .list(
          NoteBody.List(
            isOrdered: false,
            items: [
              NoteBody.Item([Span("a")]), NoteBody.Item([Span("b")]), NoteBody.Item([Span("c")]),
            ]))
      ]))
    NoteText.indent(by: 1, in: text, range: NSRange(location: 2, length: 3), font: font)
    #expect(NoteText.body(of: text).markdown == "- a\n  - b\n  - c")
    NoteText.indent(by: -1, in: text, range: NSRange(location: 4, length: 1), font: font)
    #expect(NoteText.body(of: text).markdown == "- a\n  - b\n- c")
  }

  @Test func `a list that changes kind stays one list`() {
    let text = editable(
      NoteBody([
        .list(
          NoteBody.List(
            isOrdered: false,
            items: [
              NoteBody.Item([Span("a")]), NoteBody.Item([Span("b")]), NoteBody.Item([Span("c")]),
            ]))
      ]))
    NoteText.toggleList(
      ordered: true, in: text, range: NSRange(location: 0, length: text.length), font: font)
    let lists = (0..<3).compactMap { index in
      (text.attribute(.paragraphStyle, at: index * 2, effectiveRange: nil) as? NSParagraphStyle)?
        .textLists.last
    }
    #expect(lists.count == 3)
    #expect(lists.allSatisfy { $0 === lists[0] })
    #expect(NoteText.body(of: text).markdown == "1. a\n2. b\n3. c")
  }

  @Test func `an item indented under one with a nested list joins it`() {
    let text = editable(
      NoteBody([
        .list(
          NoteBody.List(
            isOrdered: false,
            items: [
              NoteBody.Item(
                [Span("a")],
                lists: [NoteBody.List(isOrdered: true, items: [NoteBody.Item([Span("x")])])]),
              NoteBody.Item([Span("b")]),
            ]))
      ]))
    // "b" is the third paragraph: a, x, b.
    NoteText.indent(by: 1, in: text, range: NSRange(location: 4, length: 1), font: font)
    #expect(NoteText.body(of: text).markdown == "- a\n  1. x\n  2. b")
  }

  @Test func `the list buttons on an empty paragraph style what is typed next`() {
    let style = NoteText.toggledTypingStyle(ordered: false, current: nil, font: font)
    #expect(style.textLists.count == 1)
    let off = NoteText.toggledTypingStyle(ordered: false, current: style, font: font)
    #expect(off.textLists.isEmpty)
  }

  // MARK: - Links

  @Test func `the link field acts on the selection, or on the whole link the caret is in`() {
    let url = URL(string: "https://example.com")!
    let text = editable(
      NoteBody([.paragraph([Span("see "), Span("this link", link: url), Span(" here")])]))
    let link = NSRange(location: 4, length: 9)
    #expect(NoteText.linkRange(NSRange(location: 6, length: 0), in: text) == link)
    #expect(NoteText.linkRange(NSRange(location: 4, length: 0), in: text) == link)
    // Just past it, the caret is in the text after it.
    #expect(
      NoteText.linkRange(NSRange(location: 13, length: 0), in: text)
        == NSRange(location: 13, length: 0))
    #expect(
      NoteText.linkRange(NSRange(location: 0, length: 3), in: text)
        == NSRange(location: 0, length: 3))
  }

  @Test func `a caret at the end of a note that ends in a link is in it`() {
    let url = URL(string: "https://example.com")!
    let text = editable(NoteBody([.paragraph([Span("see "), Span("this", link: url)])]))
    #expect(
      NoteText.linkRange(NSRange(location: 8, length: 0), in: text)
        == NSRange(location: 4, length: 4))
    #expect(
      NoteText.linkRange(NSRange(location: 0, length: 0), in: NSAttributedString())
        == NSRange(location: 0, length: 0))
  }
}
