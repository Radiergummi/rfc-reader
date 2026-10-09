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

  /// A grammar in the bar dialect, alternating with `|`, links as one in RFC 5234's
  /// does (#696); its type says which it is.
  @Test func `a grammar that alternates with a bar links its rules`() throws {
    let text = Self.text("greeting = salutation | name", "name     = 1*ALPHA")
    #expect(ABNFPresentation.dialect(ofType: "abnf822") == .rfc822)
    #expect(ABNFPresentation.dialect(ofType: "abnf") == .rfc5234)
    let grammar = DocumentGrammar(blocks: [(text: text, dialect: ABNF.Dialect.rfc822)])
    guard
      case .linked(let linked)? = ABNFPresentation.render(
        text, dialect: .rfc822, grammar: grammar)
    else {
      Issue.record("no linked rendition")
      return
    }
    #expect(linked.definitions.map(\.anchor) == ["abnf-greeting", "abnf-name"])
    #expect(linked.links.map { Self.substring(text, $0.range) } == ["name"])
    // A block typed as RFC 5234's grammar is read as one, a stray `|` and all.
    #expect(ABNFPresentation.render(text, grammar: DocumentGrammar(blocks: [text])) == nil)
  }

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

  /// `=/` extends a rule another document defines, as `method =/` would RFC 9110's:
  /// with no definition here, its name stays plain rather than going nowhere.
  @Test func `an incremental rule of another document's stays plain`() throws {
    let linked = try Self.linked("method =/ \"FOO\"")
    #expect(linked.links.isEmpty)
    #expect(linked.definitions.isEmpty)
  }

  /// A block shown other than as written, folded per RFC 8792 or set with tabs, is
  /// left out of the grammar: its rules could not be anchored in its own text.
  @Test func `a folded or tabbed grammar block is left out`() {
    let folded = Preformatted(
      kind: .sourceCode,
      text:
        "=============== NOTE: '\\' line wrapping per RFC 8792 ================\n\nfirst = 1*\\\n  ALPHA",
      type: "abnf")
    let tabbed = Preformatted(kind: .sourceCode, text: "second\t= 1*DIGIT", type: "abnf")
    let plain = Preformatted(kind: .sourceCode, text: "third = 1*DIGIT", type: "abnf")
    let document = Fixtures.document(
      .preformatted(folded), .preformatted(tabbed), .preformatted(plain))
    let blocks = DocumentGrammar.blocks(of: document, hints: .empty)
    #expect(blocks.map(\.content) == [plain])
  }

  /// Source code is set without the indent all its lines share, as a converted RFC's
  /// grammar has, so the grammar is collected over that text: its definitions are
  /// anchored, and its uses link to them.
  @Test func `an indented grammar block is linked as it is set`() throws {
    let grammar = Preformatted(
      kind: .sourceCode, text: Self.text("   pair = item item", "   item = 1*DIGIT"), type: "abnf")
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(grammar)), style: ReadingStyle())
    let offset = try #require(built.anchors.offset(of: "abnf-item"))
    #expect(
      (built.text.string as NSString).substring(with: NSRange(location: offset, length: 4))
        == "item")
    let use = (built.text.string as NSString).range(of: "pair = item").location + 7
    let url = try #require(built.text.attribute(.link, at: use, effectiveRange: nil) as? URL)
    #expect(ReaderLinkScheme.anchor(from: url) == "abnf-item")
  }

  @Test func `what is not a grammar is not linked`() {
    #expect(ABNFPresentation.render("x = y + 1;", grammar: DocumentGrammar(blocks: [String]())) == nil)
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
      if let anchor = ReaderLinkScheme.anchor(from: link.url) {
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

  /// Links and anchors are attributes: each grammar block's text is in the storage
  /// as the document has it, character for character.
  @Test func `the grammar's text is unchanged`() throws {
    let document = try Fixtures.document(named: "rfc9682.xml")
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let blocks = DocumentGrammar.blocks(of: document, hints: .bundled)
    #expect(blocks.count == 12)
    for block in blocks {
      #expect(built.text.string.contains(block.content.text))
    }
  }

  /// A grammar's links draw nothing, so it has no presentation to switch: it is
  /// plain, with no figure item over it (which on iOS would take a press from its
  /// links), and keeps its links when the reader prefers figures as text.
  @Test func `a grammar is plain, and linked whatever the preference`() throws {
    let built = try Self.rfc9682(PresentationChoices(preferred: .text))
    let link = try #require(Self.grammarLinks(in: built).first)
    let box = try #require(
      built.text.attribute(.rfcVerbatim, at: link.range.location, effectiveRange: nil)
        as? VerbatimBox)
    #expect(box.shown == .plain)
    #expect(
      built.text.attribute(.rfcFigureItem, at: link.range.location, effectiveRange: nil) == nil)
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
      Self.grammarLinks(in: built).first { ReaderLinkScheme.anchor(from: $0.url) != nil })
    let anchor = try #require(ReaderLinkScheme.anchor(from: link.url))
    let definition = try #require(built.grammar.definition(of: anchor))
    #expect(built.text.string.contains(definition))
  }
}
