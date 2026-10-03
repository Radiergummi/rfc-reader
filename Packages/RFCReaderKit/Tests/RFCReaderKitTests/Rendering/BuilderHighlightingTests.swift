import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Builder: highlighted code")
struct BuilderHighlightingTests {
  private static let json = #"{"name": "value", "count": 2}"#
  private static let listing = Preformatted(
    kind: .sourceCode, text: json, type: "json", anchor: "listing")

  private func build(
    _ content: Preformatted, style: ReadingStyle = ReadingStyle(),
    choices: PresentationChoices = .defaults
  ) -> BuiltDocument {
    DocumentTextBuilder.build(
      Fixtures.document(.preformatted(content)), style: style, choices: choices)
  }

  private func color(of fragment: String, in built: BuiltDocument) throws -> PlatformColor? {
    let range = (built.text.string as NSString).range(of: fragment)
    try #require(range.location != NSNotFound, "\(fragment) is not in the text")
    return built.text.attribute(.foregroundColor, at: range.location, effectiveRange: nil)
      as? PlatformColor
  }

  private func box(in built: BuiltDocument) throws -> VerbatimBox {
    let offset = try #require(built.anchors.offset(of: "listing"))
    return try #require(
      built.text.attribute(.rfcVerbatim, at: offset, effectiveRange: nil) as? VerbatimBox)
  }

  private func hasFigureItem(_ built: BuiltDocument) -> Bool {
    var found = false
    built.text.enumerateAttribute(
      .rfcFigureItem, in: NSRange(location: 0, length: built.text.length)
    ) { value, _, stop in
      if value != nil {
        found = true
        stop.pointee = true
      }
    }
    return found
  }

  @Test func `the text is the block's own`() {
    #expect(build(Self.listing).text.string.contains(Self.json))
  }

  @Test func `each token carries its theme color`() throws {
    let built = build(Self.listing)
    #expect(try color(of: #""name""#, in: built) == SyntaxTheme.standard.color(for: .name))
    #expect(try color(of: #""value""#, in: built) == SyntaxTheme.standard.color(for: .string))
    #expect(try color(of: "2", in: built) == SyntaxTheme.standard.color(for: .number))
  }

  /// White space shows no color, so it joins the run before it: a block has a run
  /// per colored token rather than two, which every later pass over the storage
  /// walks (`Build: RFC 8727` in `make benchmark`).
  @Test func `white space between tokens takes no run of its own`() throws {
    let built = build(Self.listing)
    let body = (built.text.string as NSString).range(of: Self.json)
    var blankRuns: [String] = []
    built.text.enumerateAttribute(.foregroundColor, in: body) { _, range, _ in
      let run = (built.text.string as NSString).substring(with: range)
      if run.allSatisfy(\.isWhitespace) { blankRuns.append(run) }
    }
    #expect(blankRuns.isEmpty, "\(blankRuns)")
  }

  @Test func `plain text keeps the body color`() throws {
    let message = Preformatted(
      kind: .sourceCode, text: "HTTP/1.1 200 OK\n\nhello", type: "http-message",
      anchor: "listing")
    #expect(try color(of: "hello", in: build(message)) == RFCColors.label)
  }

  @Test func `a highlighted block is not a figure`() throws {
    let built = build(Self.listing)
    let box = try box(in: built)
    #expect(box.shown == .highlighted)
    #expect(box.presentation == nil, "no Show as Text / Show as Figure")
    #expect(!hasFigureItem(built), "no long-press figure menu on iOS")
    #expect(box.spokenLabel == nil)
    #expect(!AccessibleReading.isDiagram(box))
    #expect(AccessibleReading.Rotors(built.text).diagrams.isEmpty)
  }

  @Test func `drawing diagrams off leaves code highlighted`() throws {
    let built = build(Self.listing, choices: PresentationChoices(drawsDiagrams: false))
    #expect(try color(of: #""name""#, in: built) == SyntaxTheme.standard.color(for: .name))
  }

  @Test func `a choice of text for the block leaves it highlighted`() throws {
    let key = PresentationKey(anchor: "listing", ordinal: 0)
    let built = build(Self.listing, choices: PresentationChoices(chosen: [key: .text]))
    #expect(try color(of: #""name""#, in: built) == SyntaxTheme.standard.color(for: .name))
  }

  /// 17 HTTP messages in the corpus are artwork, not source code; a highlighted
  /// block keeps its indent, as plain artwork does.
  @Test func `highlighted artwork is not centered`() throws {
    let text = "GET / HTTP/1.1\nHost: example.com"
    let typed = build(
      Preformatted(kind: .artwork, text: text, type: "message/http", anchor: "listing"))
    let untyped = build(Preformatted(kind: .artwork, text: text, anchor: "listing"))
    func indent(_ built: BuiltDocument) throws -> CGFloat {
      let offset = (built.text.string as NSString).range(of: "GET").location
      let style = try #require(
        built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil)
          as? NSParagraphStyle)
      return style.firstLineHeadIndent
    }
    #expect(try indent(typed) == indent(untyped))
  }

  // MARK: - RFC 8792 folding

  private static func folded(_ unfolded: String) -> Preformatted {
    Fixtures.folded(unfolded, type: "json", anchor: "listing")
  }

  @Test func `a folded block is highlighted where it is shown unfolded`() throws {
    let unfolded = #"{"key": ""# + String(repeating: "a", count: 50) + #""}"#
    let built = build(Self.folded(unfolded))
    #expect(built.text.string.contains(unfolded), "shown unfolded")
    #expect(try color(of: #""key""#, in: built) == SyntaxTheme.standard.color(for: .name))
  }

  @Test func `a folded block is highlighted where it keeps its folds`() throws {
    let unfolded = #"{"key": ""# + String(repeating: "a", count: 50) + #""}"#
    let content = Self.folded(unfolded)
    let built = build(content, style: ReadingStyle(measure: 300))
    #expect(built.text.string.contains(content.text), "shown folded")
    #expect(try color(of: #""key""#, in: built) == SyntaxTheme.standard.color(for: .name))
  }
}
