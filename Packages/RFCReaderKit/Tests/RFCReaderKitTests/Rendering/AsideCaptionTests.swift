import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// An aside's "Note" caption (#700): the reader's line at the top of its card, which
/// Implementer folds the aside's body under, in place of the label its own text
/// opens with.
@Suite("Aside captions")
struct AsideCaptionTests {
  private static func build(_ name: String, style: ReadingStyle = ReadingStyle()) throws
    -> BuiltDocument
  {
    DocumentTextBuilder.build(try Fixtures.document(named: name), style: style)
  }

  /// Each aside's paragraphs, in order, as strings, from the first character carrying
  /// its ordinal to the last.
  private static func asides(of built: BuiltDocument) -> [[String]] {
    let string = built.text.string as NSString
    return FoldingIndex(built).asides.map { aside in
      let range = NSRange(location: aside.caption, length: aside.body.upperBound - aside.caption)
      var paragraphs: [String] = []
      string.enumerateSubstrings(in: range, options: .byParagraphs) { paragraph, _, _, _ in
        paragraphs.append(paragraph ?? "")
      }
      return paragraphs
    }
  }

  /// Every aside opens with the caption, the reader's: left out of a copy, and said
  /// as the word rather than its capitals. The label the text opened with is gone,
  /// in either spelling.
  @Test(arguments: ["rfc9271.xml", "rfc9197.xml", "rfc9631.xml"])
  func `an aside opens with a note caption in place of its label`(name: String) throws {
    let built = try Self.build(name)
    let index = FoldingIndex(built)
    let asides = Self.asides(of: built)
    #expect(!asides.isEmpty)
    for (aside, paragraphs) in zip(index.asides, asides) {
      #expect(paragraphs.first == "NOTE")
      #expect(built.text.attribute(.rfcReaderOnly, at: aside.caption, effectiveRange: nil) != nil)
      #expect(
        built.text.attribute(.rfcSpoken, at: aside.caption, effectiveRange: nil) as? String
          == "Note")
      let text = try #require(paragraphs.dropFirst().first)
      #expect(!text.hasPrefix("Note:") && !text.hasPrefix("NOTE:"))
      #expect(!text.isEmpty)
    }
  }

  /// "Notes:" gives way to a "Notes" caption, and a paragraph that was only the
  /// label goes with it, leaving no empty line in the card.
  @Test func `notes are captioned notes, and a label alone leaves no empty paragraph`() throws {
    let built = try Self.build("rfc9682.xml")
    let asides = Self.asides(of: built)
    #expect(asides.contains { $0.first == "NOTES" })
    for paragraphs in asides where paragraphs.first == "NOTES" {
      let text = try #require(paragraphs.dropFirst().first)
      #expect(!text.hasPrefix("Notes:"))
      #expect(!text.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }

  /// Paper has no caption and nothing to fold: an aside prints as its words.
  @Test func `a build without live links keeps the aside's words and adds no caption`() throws {
    let built = try Self.build("rfc9271.xml", style: ReadingStyle(emitsLinks: false))
    #expect(FoldingIndex(built).asides.isEmpty)
    #expect(!built.text.string.contains("NOTE\n"))
    #expect(built.text.string.contains("Note:"))
  }

  /// The label is found only where the aside's text opens with it, set plain or in
  /// bold; a word that merely starts with it is no label.
  @Test func `the label is only a note label the aside opens with`() {
    func labeled(_ inlines: [Inline], anchor: String? = nil) -> DocumentTextBuilder.LabeledAside {
      DocumentTextBuilder.labeledAside([.paragraph(Paragraph(inlines, anchor: anchor))])
    }
    let kept: [Block] = [.paragraph(Paragraph([.text("Keep it short.")]))]
    #expect(labeled([.text("Note: Keep it short.")]).blocks == kept)
    #expect(labeled([.strong([.text("NOTE:")]), .text(" Keep it short.")]).blocks == kept)
    let notable: [Inline] = [.text("Notable: Keep it short.")]
    #expect(
      labeled(notable) == DocumentTextBuilder.LabeledAside(blocks: [.paragraph(Paragraph(notable))])
    )
    let late: [Inline] = [.text("Keep it short. Note: not a label.")]
    #expect(labeled(late).blocks == [.paragraph(Paragraph(late))])
    #expect(
      labeled([.text("Notes:")], anchor: "notes")
        == DocumentTextBuilder.LabeledAside(caption: "Notes", blocks: [], anchor: "notes"))
  }
}

extension AsideCaptionTests {
  /// A closed aside's card ends with its caption, rounded and capped there, rather
  /// than running on into the body Implementer folds away; open, it runs on.
  @Test func `a closed aside's card ends at its caption`() throws {
    let built = try Self.build("rfc9271.xml")
    let index = FoldingIndex(built)
    let aside = try #require(index.asides.first)
    let caption = NSRange(location: aside.caption, length: aside.body.lowerBound - aside.caption)
    let closed = Folding(mode: .implementer).hidden(in: index)
    let folded = try #require(
      FragmentGeometry.decorationSpan(in: built.text, fragment: caption, hidden: closed))
    #expect(folded.isFirst && folded.isLast)
    #expect(NSMaxRange(folded.runRange) == aside.body.lowerBound)
    let open = try #require(FragmentGeometry.decorationSpan(in: built.text, fragment: caption))
    #expect(open.isFirst && !open.isLast)
  }
}

extension AsideCaptionTests {
  /// A card straight after a closed aside starts on its own, capped and rounded,
  /// rather than as the continuation of the aside's card, whose folded body is all
  /// that touched it.
  @Test func `a card after a closed aside does not meet it`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .aside([.paragraph(Paragraph(text: "aside"))]),
        .preformatted(Preformatted(kind: .artwork, text: "AAAA"))),
      style: ReadingStyle())
    let closed = Folding(mode: .implementer).hidden(in: FoldingIndex(built))
    let offset = try Fixtures.offset(of: "AAAA", in: built.text)
    let span = try #require(
      FragmentGeometry.decorationSpan(
        in: built.text, fragment: NSRange(location: offset, length: 1), hidden: closed))
    #expect(span.decoration == .artwork)
    #expect(!span.meetsCardAbove)
    let open = try #require(
      FragmentGeometry.decorationSpan(
        in: built.text, fragment: NSRange(location: offset, length: 1)))
    #expect(open.meetsCardAbove)
  }
}
