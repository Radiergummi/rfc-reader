import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#endif

/// What VoiceOver says for the reader's own labelled runs on iOS (#872): a heading's
/// backlink caption, its errata chip and an aside's caption carry a `.rfcSpoken`
/// label, which only macOS reads (`AccessibleReading`). `UITextView` has no
/// per-range accessor, so iOS is told in the text instead, as for a diagram (#308)
/// and an informative chip (#862): a symbol is pronounced as nothing, and a caption
/// set in capitals as its word.
@Suite("Spoken label speech")
struct SpokenLabelSpeechTests {
  @Test func `an English caption is pronounced as its word`() {
    #expect(AccessibleReading.captionPronunciation("Note") == AccessibleReading.notePronunciation)
    #expect(
      AccessibleReading.captionPronunciation("Notes") == AccessibleReading.notesPronunciation)
  }

  /// A translated document's caption (#749) has no IPA to give, and is read as drawn.
  @Test func `a translated caption has no pronunciation`() {
    #expect(AccessibleReading.captionPronunciation("Hinweis") == nil)
  }

  #if canImport(UIKit)
    /// Each run of `range` that carries a pronunciation, as its text and the
    /// pronunciation.
    private func pronounced(
      in range: NSRange, of text: NSAttributedString
    ) -> [(text: String, pronunciation: String)] {
      let string = text.string as NSString
      var found: [(text: String, pronunciation: String)] = []
      text.enumerateAttribute(.accessibilitySpeechIPANotation, in: range) { value, piece, _ in
        guard let pronunciation = value as? String else { return }
        found.append((string.substring(with: piece), pronunciation))
      }
      return found
    }

    private func refer(to anchor: String) -> Block {
      .paragraph(
        Paragraph([.text("see "), .crossReference(CrossReference(target: .anchor(anchor)))]))
    }

    /// The arrow is pronounced as nothing, so the caption is said as its words, as
    /// its label is; nothing else of it is pronounced.
    @Test func `a backlink caption's arrow is silent`() throws {
      let document = RFCDocument(
        header: DocumentHeader(title: "T"),
        sections: [
          Section(anchor: "one", number: "1", title: "One", blocks: [refer(to: "two")]),
          Section(
            anchor: "two", number: "2", title: "Two", blocks: [.paragraph(Paragraph(text: "x"))]),
        ],
        source: .xml)
      let built = DocumentTextBuilder.build(document, style: ReadingStyle())
      let heading = try Fixtures.offset(of: "2. Two\n", in: built.text)
      let caption = try #require(built.text.backlinkCaption(at: heading + "2. Two\n".utf16.count))
      let pronounced = pronounced(in: caption.range, of: built.text)
      #expect(pronounced.map(\.text) == ["\u{FFFC}"])
      #expect(pronounced.map(\.pronunciation) == [AccessibleReading.silence])
    }

    /// The chip's icon is pronounced as nothing, so the chip is said as its words.
    @Test func `an errata chip's icon is silent`() throws {
      let document = RFCDocument(
        header: DocumentHeader(title: "T"),
        sections: [
          Section(
            anchor: "one", number: "1", title: "One", blocks: [.paragraph(Paragraph(text: "x"))])
        ],
        source: .xml)
      let erratum = Erratum(
        id: 1, document: .rfc(9999), status: .verified, type: .technical, section: "1",
        original: "old", corrected: "new", notes: "", submitted: "2024-01-01")
      let built = DocumentTextBuilder.build(
        document, style: ReadingStyle(),
        errata: ErrataMarks(errata: [erratum], document: document, locale: .english))
      let heading = try Fixtures.offset(of: "1. One", in: built.text)
      let chip = try #require(built.text.errataChip(at: heading + "1. One ".utf16.count))
      let pronounced = pronounced(in: chip.range, of: built.text)
      #expect(pronounced.map(\.text) == ["\u{FFFC}"])
      #expect(pronounced.map(\.pronunciation) == [AccessibleReading.silence])
    }

    /// Set in capitals, the caption is pronounced as the word its label is, and its
    /// line break carries nothing.
    @Test(arguments: [
      ("rfc9271.xml", "NOTE", AccessibleReading.notePronunciation),
      ("rfc9682.xml", "NOTES", AccessibleReading.notesPronunciation),
    ])
    func `an aside caption is pronounced as its word`(
      name: String, shown: String, pronunciation: String
    ) throws {
      let built = DocumentTextBuilder.build(
        try Fixtures.document(named: name), style: ReadingStyle())
      let captions = built.foldingIndex.asides.map { aside in
        NSRange(location: aside.caption, length: shown.utf16.count + 1)
      }
      let string = built.text.string as NSString
      let matching = captions.filter { string.substring(with: $0) == shown + "\n" }
      #expect(!matching.isEmpty)
      for caption in matching {
        let pronounced = pronounced(in: caption, of: built.text)
        #expect(pronounced.map(\.text) == [shown])
        #expect(pronounced.map(\.pronunciation) == [pronunciation])
      }
    }
  #endif
}
