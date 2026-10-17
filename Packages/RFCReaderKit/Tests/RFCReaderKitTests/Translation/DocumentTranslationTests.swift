import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A translated document (#749): the original's model with its prose replaced, so it
/// is built, anchored and navigated as the original is. The Translation framework
/// cannot run here, so each test stands a pure function over strings in for it.
@Suite("Document translation")
struct DocumentTranslationTests {
  static let fixtures = ["rfc8999.xml", "rfc2119.txt", "rfc9271.xml", "rfc793.txt"]

  /// `document` translated by `translate`, as the reader would translate it: every
  /// source it asks for, and nothing else.
  private static func translated(
    _ document: RFCDocument, by translate: (String) -> String
  ) -> RFCDocument {
    let sources = DocumentTranslation.sources(in: document)
    let translations = Dictionary(
      sources.map { ($0, translate($0)) }, uniquingKeysWith: { first, _ in first })
    return DocumentTranslation.translated(document, translations)
  }

  private static func crossReferences(in document: RFCDocument) -> [CrossReference] {
    document.proseInlines.compactMap { inline in
      if case .crossReference(let reference) = inline { return reference }
      return nil
    }
  }

  private static func preformatted(in document: RFCDocument) -> [Preformatted] {
    document.blocks.compactMap { block in
      if case .preformatted(let preformatted) = block { return preformatted }
      return nil
    }
  }

  @Test(arguments: fixtures)
  func `a translation that changes nothing gives back the document`(name: String) throws {
    let document = try Fixtures.document(named: name)
    #expect(Self.translated(document) { $0 } == document)
    #expect(DocumentTranslation.translated(document, [:]) == document)
  }

  @Test(arguments: fixtures)
  func `every anchor of the original is where it was`(name: String) throws {
    let document = try Fixtures.document(named: name)
    let translated = Self.translated(document) { "«\($0.uppercased())»" }
    try #require(translated != document)
    let style = ReadingStyle()
    let original = DocumentTextBuilder.build(document, style: style)
    let built = DocumentTextBuilder.build(translated, style: style, translation: .english)
    #expect(built.anchors.entries.map(\.anchor) == original.anchors.entries.map(\.anchor))
    #expect(translated.allSections.map(\.anchor) == document.allSections.map(\.anchor))
  }

  @Test(arguments: fixtures)
  func `artwork, code and references come back as they were`(name: String) throws {
    let document = try Fixtures.document(named: name)
    let translated = Self.translated(document) { "«\($0.uppercased())»" }
    #expect(Self.preformatted(in: translated) == Self.preformatted(in: document))
    let references = { (document: RFCDocument) -> [ReferenceList] in
      document.blocks.compactMap { block in
        if case .references(let list) = block { return list }
        return nil
      }
    }
    #expect(references(translated) == references(document))
    #expect(translated.header == document.header.with(abstract: translated.header.abstract))
  }

  /// A table cell of digits and punctuation, "0x01", has nothing to translate.
  @Test(arguments: fixtures)
  func `every source has words to translate`(name: String) throws {
    let document = try Fixtures.document(named: name)
    let sources = DocumentTranslation.sources(in: document)
    try #require(!sources.isEmpty)
    #expect(sources.allSatisfy { $0.contains { $0.isLetter } })
    #expect(Set(sources).count == sources.count)
  }

  /// A label the translation keeps as it was, as "RFC 2119" or "[HTTP]" usually is,
  /// is linked again where it landed.
  @Test func `a reference whose label survives is linked again`() throws {
    let document = try Fixtures.rfc8999()
    let original = Self.crossReferences(in: document)
    try #require(original.count > 10)
    let translated = Self.translated(document) { "Übersetzt: \($0)" }
    #expect(Self.crossReferences(in: translated).map(\.target) == original.map(\.target))
  }

  /// "Section 4" translated as a sentence of its own is found by its translation, and
  /// keeps its target under the translated words.
  @Test func `a reference whose label is words is found by the label's translation`() throws {
    let document = try Fixtures.rfc8999()
    let worded = Self.crossReferences(in: document).filter { !$0.display.isChip }
    try #require(!worded.isEmpty)
    let translated = Self.translated(document) { $0.replacing("Section", with: "Abschnitt") }
    let relinked = Self.crossReferences(in: translated).filter { !$0.display.isChip }
    #expect(relinked.map(\.target) == worded.map(\.target))
    #expect(relinked.contains { $0.display.text.hasPrefix("Abschnitt") })
  }

  /// One the translation rewrote leaves its words as plain text, rather than a link
  /// on the wrong words.
  @Test func `a reference whose label does not survive is plain text`() throws {
    let document = try Fixtures.rfc8999()
    let translated = Self.translated(document) { source in
      String(source.filter { !$0.isNumber }) + " (übersetzt)"
    }
    let numbered = Self.crossReferences(in: document).filter {
      $0.display.text.contains { $0.isNumber }
    }
    try #require(!numbered.isEmpty)
    let kept = Self.crossReferences(in: translated)
    #expect(kept.allSatisfy { !$0.display.text.contains { $0.isNumber } })
    #expect(kept.count < Self.crossReferences(in: document).count)
  }

  /// A section's qualifier, "(Normative)", is part of its title in a translation,
  /// which translates the two together.
  @Test func `a heading is translated with its qualifier`() throws {
    let document = try Fixtures.rfc8999()
    let translated = Self.translated(document) { "«\($0)»" }
    for (section, original) in zip(translated.allSections, document.allSections)
    where !original.titleText.isEmpty {
      #expect(section.qualifier == nil)
      #expect(section.titleText == "«\(original.headingWords.plainText)»")
    }
  }

  /// An aside's "Note:" stays, so the builder still takes it for the caption the
  /// translated labels name, and translates the rest.
  @Test func `an aside keeps the label its caption is made from`() throws {
    let aside = Block.aside([
      .paragraph(Paragraph([.text("Note: the server keeps the shape of the reply.")]))
    ])
    let translated = DocumentTranslation.translated(
      blocks: [aside], ["the server keeps the shape of the reply.": "der Server antwortet."])
    guard case .aside(let blocks) = try #require(translated.first) else {
      Issue.record("not an aside: \(translated)")
      return
    }
    #expect(DocumentTextBuilder.labeledAside(blocks).caption == "Note")
    #expect(
      DocumentTextBuilder.labeledAside(blocks).blocks
        == [.paragraph(Paragraph([.text("der Server antwortet.")]))])
  }
}

extension DocumentHeader {
  fileprivate func with(abstract: [Block]) -> DocumentHeader {
    var header = self
    header.abstract = abstract
    return header
  }
}
