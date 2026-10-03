import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// ABNF rule names as links (#185): a rule's definition is an anchor, and every use
/// of a name the document defines links to it, across the document's grammar blocks;
/// RFC 5234's core rules link to its Appendix B.1.
@Suite("Grammar links")
struct GrammarLinksTests {
  private static func text(_ lines: String...) -> String {
    lines.joined(separator: "\n")
  }

  private static func linked(_ text: String, grammar: DocumentGrammar? = nil) throws -> LinkedText {
    let grammar = grammar ?? DocumentGrammar(blocks: [text])
    guard case .linked(let linked)? = ABNFPresentation.render(text, grammar: grammar) else {
      Issue.record("no linked rendition")
      throw CancellationError()
    }
    return linked
  }

  private static func substring(_ text: String, _ range: NSRange) -> String {
    (text as NSString).substring(with: range)
  }

  // MARK: Guards

  @Test func `a definition is an anchor named for the rule`() throws {
    let text = Self.text("greeting = salutation SP name", "Name     = 1*ALPHA")
    let linked = try Self.linked(text)
    #expect(linked.definitions.map(\.anchor) == ["abnf-greeting", "abnf-name"])
    #expect(linked.definitions.map { Self.substring(text, $0.range) } == ["greeting", "Name"])
  }

  /// Rule names are case-insensitive, so a use in another spelling links all the same.
  @Test func `a use links to its definition whatever its case`() throws {
    let text = Self.text("greeting = NAME / name", "name     = 1*ALPHA")
    let linked = try Self.linked(text)
    let toName = linked.links.filter { $0.target == .anchor("abnf-name") }
    #expect(toName.map { Self.substring(text, $0.range) } == ["NAME", "name"])
  }

  @Test func `a core rule links to RFC 5234's Appendix B.1`() throws {
    let text = Self.text("greeting = salutation SP", "salutation = 1*ALPHA")
    let linked = try Self.linked(text)
    let core = linked.links.filter { $0.target == .document(.rfc(5234), section: "B.1") }
    #expect(core.map { Self.substring(text, $0.range) } == ["SP", "ALPHA"])
  }

  /// A document that defines a core rule itself, as RFC 5234 does, links to its own.
  @Test func `a core rule the document defines links to the document's own`() throws {
    let text = Self.text("ALPHA = %x41-5A / %x61-7A", "word = 1*ALPHA")
    let linked = try Self.linked(text)
    #expect(linked.links.map(\.target) == [.anchor("abnf-alpha")])
  }

  /// A name defined nowhere in the document, such as one imported from another,
  /// stays plain until rules are resolved across documents.
  @Test func `a name defined nowhere stays plain`() throws {
    let linked = try Self.linked("message = field-value CRLF")
    #expect(linked.links.map(\.target) == [.document(.rfc(5234), section: "B.1")])
  }

  /// `=/` adds to a rule: it is a use of the name, not a second definition.
  @Test func `an incremental rule links to the rule it adds to`() throws {
    let text = Self.text("command = \"open\"", "command =/ \"close\"")
    let linked = try Self.linked(text)
    #expect(linked.definitions.map(\.anchor) == ["abnf-command"])
    #expect(linked.links.map(\.target) == [.anchor("abnf-command")])
    #expect(
      linked.links.map(\.range.location) == [
        (Self.text("command = \"open\"", "") as NSString).length
      ])
  }

  /// One grammar spread over several blocks is one grammar: a use links to a
  /// definition in another block, and the first definition of a name is its anchor.
  @Test func `blocks share one grammar, and the first definition wins`() throws {
    let first = Self.text("record = field *( \",\" field )")
    let second = Self.text("field = 1*ALPHA")
    let third = Self.text("field = 1*DIGIT")
    let grammar = DocumentGrammar(blocks: [first, second, third])
    #expect(
      try Self.linked(first, grammar: grammar).links.map(\.target).contains(.anchor("abnf-field")))
    #expect(try Self.linked(second, grammar: grammar).definitions.map(\.anchor) == ["abnf-field"])
    #expect(try Self.linked(third, grammar: grammar).definitions.isEmpty)
  }

  @Test func `what is not a grammar is not linked`() {
    #expect(ABNFPresentation.render("x = y + 1;", grammar: DocumentGrammar(blocks: [])) == nil)
  }

  /// The preview of a rule is its definition, continuation lines included, without
  /// the comments and blank lines before the next rule.
  @Test func `a rule's definition is its lines`() {
    let grammar = DocumentGrammar(
      blocks: [
        Self.text(
          "pair  = item \",\" item   ; two of them",
          "        [ item ]",
          "",
          "; the items",
          "item  = 1*DIGIT")
      ])
    #expect(
      grammar.definition(of: "abnf-pair")
        == Self.text("pair  = item \",\" item   ; two of them", "        [ item ]"))
    #expect(grammar.definition(of: "abnf-item") == "item  = 1*DIGIT")
  }

  // MARK: Through a document

  /// RFC 9682 sets its grammar over twelve blocks.
  private static func rfc9682(_ choices: PresentationChoices = PresentationChoices()) throws
    -> BuiltDocument
  {
    DocumentTextBuilder.build(
      try Fixtures.document(named: "rfc9682.xml"), style: ReadingStyle(), choices: choices)
  }

  private static func grammarLinks(in built: BuiltDocument) -> [(range: NSRange, url: URL)] {
    var links: [(NSRange, URL)] = []
    let whole = NSRange(location: 0, length: built.text.length)
    built.text.enumerateAttribute(.link, in: whole) { value, range, _ in
      guard let url = value as? URL,
        built.text.attribute(.rfcVerbatim, at: range.location, effectiveRange: nil) != nil
      else { return }
      links.append((range, url))
    }
    return links
  }

  @Test func `every rule a document's grammar uses links to an anchor it holds`() throws {
    let built = try Self.rfc9682()
    let links = Self.grammarLinks(in: built)
    #expect(links.count > 20)
    for link in links {
      if let anchor = DocumentTextBuilder.anchor(from: link.url) {
        #expect(built.anchors.offset(of: anchor) != nil, "\(anchor) is not in the index")
        // The anchor lands on the definition's name, which the link spells.
        let offset = try #require(built.anchors.offset(of: anchor))
        let defined = (built.text.string as NSString).substring(
          with: NSRange(location: offset, length: link.range.length))
        #expect(
          defined.lowercased()
            == (built.text.string as NSString).substring(with: link.range).lowercased())
      } else {
        #expect(RFCLink(url: link.url) == RFCLink(id: .rfc(5234), section: "B.1"))
      }
    }
  }

  /// Links and anchors are attributes: the text is the block's, character for
  /// character, as it is shown as text.
  @Test func `the grammar's text is unchanged`() throws {
    let linked = try Self.rfc9682()
    let plain = try Self.rfc9682(PresentationChoices(preferred: .text))
    #expect(linked.text.string == plain.text.string)
    #expect(Self.grammarLinks(in: plain).isEmpty, "shown as text, the grammar is plain")
  }

  /// A copy of a grammar is its text, not its rule links' labels.
  @Test func `a copied grammar is its text`() throws {
    let built = try Self.rfc9682()
    let link = try #require(Self.grammarLinks(in: built).first)
    let line = (built.text.string as NSString).lineRange(for: link.range)
    let selection = built.text.attributedSubstring(from: line)
    #expect(SelectionText.plainText(of: selection) == selection.string)
  }

  /// The card a rule link previews is the rule's definition.
  @Test func `a rule anchor's definition is on the built document`() throws {
    let built = try Self.rfc9682()
    let link = try #require(
      Self.grammarLinks(in: built).first { DocumentTextBuilder.anchor(from: $0.url) != nil })
    let anchor = try #require(DocumentTextBuilder.anchor(from: link.url))
    let definition = try #require(built.grammar.definition(of: anchor))
    #expect(built.text.string.contains(definition))
  }
}
