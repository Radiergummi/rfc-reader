import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Where the builder marks an abbreviation the document expands (#67): a gloss over
/// its first use in each section, as a defined term's is in each paragraph, and not
/// where the document expands it.
@Suite("Builder: abbreviations")
struct BuilderAbbreviationTests {
  private static let tls = Abbreviation(
    short: "TLS", expansion: "Transport Layer Security", sectionAnchor: "section-1")

  /// A document of `sections`, each a list of paragraphs, that expands `TLS`.
  private static func document(_ sections: [String]...) -> RFCDocument {
    var document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: sections.enumerated().map { offset, paragraphs in
        Section(
          anchor: "section-\(offset + 1)", number: "\(offset + 1)", title: "S",
          blocks: paragraphs.map { .paragraph(Paragraph(text: $0)) })
      },
      source: .xml)
    document.abbreviations = ["TLS": tls]
    return document
  }

  /// Every gloss, as its text and the gloss it carries, in order.
  private static func glosses(in document: RFCDocument) -> [(text: String, gloss: Gloss)] {
    let text = DocumentTextBuilder.build(document, style: ReadingStyle()).text
    var found: [(String, Gloss)] = []
    var offset = 0
    while offset < text.length {
      if let gloss = text.gloss(at: offset) {
        found.append(((text.string as NSString).substring(with: gloss.range), gloss.box.gloss))
        offset = NSMaxRange(gloss.range)
      } else {
        offset += 1
      }
    }
    return found
  }

  @Test func `an abbreviation is glossed with its expansion`() {
    let found = Self.glosses(in: Self.document(["Run it over TLS."]))
    #expect(found.map(\.text) == ["TLS"])
    #expect(found.first?.gloss == .abbreviation(Self.tls))
  }

  /// `IP` is in nearly every paragraph of the documents that expand it (answered on
  /// #67, 2026-10-14).
  @Test func `only the first use in each section is glossed`() {
    let found = Self.glosses(
      in: Self.document(
        ["TLS here.", "TLS again."], ["And TLS in the next section.", "TLS once more."]))
    #expect(found.map(\.text) == ["TLS", "TLS"])
  }

  @Test func `the expansion's own parentheses are not glossed`() {
    let found = Self.glosses(
      in: Self.document(["Transport Layer Security (TLS) protects it.", "TLS keeps it."]))
    #expect(found.count == 1)
  }

  /// RFC 8999 expands a handful of abbreviations; every gloss in it is one of them.
  @Test func `a committed document's abbreviations are glossed where they are used`() throws {
    let document = try Fixtures.rfc8999()
    let found = Self.glosses(in: document)
    #expect(!found.isEmpty)
    #expect(found.allSatisfy { document.abbreviations[$0.text] != nil })
  }
}
