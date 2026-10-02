import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#endif

/// What VoiceOver says in place of a diagram's lines on iOS, where `UITextView` has
/// no per-range accessor to override and the speech attributes in the text are all
/// there is to say it with (#308).
@Suite("Diagram speech")
struct DiagramSpeechTests {
  private func built(_ blocks: Block...) -> NSAttributedString {
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: blocks)],
      source: .xml)
    return DocumentTextBuilder.build(document, style: ReadingStyle()).text
  }

  private func artwork(_ text: String) -> Block {
    .preformatted(Preformatted(kind: .artwork, text: text))
  }

  /// Each line as its text, with what is said in its place.
  private func spoken(in text: NSAttributedString) -> [(line: String, pronunciation: String)] {
    AccessibleReading.diagramSpeech(in: text).map { line in
      ((text.string as NSString).substring(with: line.range), line.pronunciation)
    }
  }

  @Test func `a diagram's first line is said as a diagram and the rest are silent`() {
    let text = built(
      .paragraph(Paragraph(text: "Before.")), artwork("+--+\n|  |\n+--+"),
      .paragraph(Paragraph(text: "After.")))
    let spoken = spoken(in: text)
    #expect(spoken.map(\.line) == ["+--+", "|  |", "+--+"])
    #expect(
      spoken.map(\.pronunciation) == [
        AccessibleReading.labelPronunciation, AccessibleReading.silence, AccessibleReading.silence,
      ])
  }

  /// A line break is left as it is, so VoiceOver still finds the lines to move
  /// between, and a blank line has nothing to say in place of.
  @Test func `line breaks and blank lines carry nothing`() {
    let text = built(artwork("\n+--+\n\n+--+"))
    #expect(spoken(in: text).map(\.line) == ["+--+", "+--+"])
    #expect(spoken(in: text).first?.pronunciation == AccessibleReading.labelPronunciation)
  }

  @Test func `two diagrams are each announced`() {
    let text = built(artwork("+--+\n+--+"), artwork("<--->\n|   |"))
    #expect(
      spoken(in: text).map(\.pronunciation) == [
        AccessibleReading.labelPronunciation, AccessibleReading.silence,
        AccessibleReading.labelPronunciation, AccessibleReading.silence,
      ])
  }

  /// Only what VoiceOver says as a diagram on macOS is silenced on iOS.
  @Test func `prose, source code and artwork that is not a drawing are read`() {
    let text = built(
      .paragraph(Paragraph(text: "A plain paragraph.")),
      .preformatted(Preformatted(kind: .sourceCode, text: "+--+\n|  |\n+--+", type: "c")),
      artwork("rule = 1*ALPHA\nother = DIGIT"))
    #expect(spoken(in: text).isEmpty)
  }

  #if canImport(UIKit)
    @Test func `the build puts the pronunciation where UIKit reads it`() throws {
      let text = built(artwork("+--+\n|  |\n+--+"))
      let first = try #require(AccessibleReading.diagramSpeech(in: text).first)
      var extent = NSRange()
      let value = text.attribute(
        .accessibilitySpeechIPANotation, at: first.range.location,
        longestEffectiveRange: &extent, in: NSRange(location: 0, length: text.length))
      #expect(value as? String == AccessibleReading.labelPronunciation)
      #expect(extent == first.range)
    }
  #endif
}
