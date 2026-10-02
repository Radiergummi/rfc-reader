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
  private func built(_ document: RFCDocument) -> NSAttributedString {
    DocumentTextBuilder.build(document, style: ReadingStyle()).text
  }

  private func artwork(_ text: String) -> Block {
    .preformatted(Preformatted(kind: .artwork, text: text))
  }

  /// Each line of every diagram as its text, with what is said in its place.
  private func spoken(in text: NSAttributedString) -> [(line: String, pronunciation: String)] {
    let string = text.string as NSString
    var spoken: [(line: String, pronunciation: String)] = []
    text.enumerateAttribute(.rfcVerbatim, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      guard let box = value as? VerbatimBox, AccessibleReading.isDiagram(box) else { return }
      for line in AccessibleReading.diagramSpeech(ofDiagram: range, in: string) {
        spoken.append((string.substring(with: line.range), line.pronunciation))
      }
    }
    return spoken
  }

  @Test func `a diagram's first line is said as a diagram and the rest are silent`() {
    let text = built(
      Fixtures.document(
        .paragraph(Paragraph(text: "Before.")), artwork("+--+\n|  |\n+--+"),
        .paragraph(Paragraph(text: "After."))))
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
    let text = built(Fixtures.document(artwork("\n+--+\n\n+--+")))
    #expect(spoken(in: text).map(\.line) == ["+--+", "+--+"])
    #expect(spoken(in: text).first?.pronunciation == AccessibleReading.labelPronunciation)
  }

  @Test func `two diagrams are each announced`() {
    let text = built(Fixtures.document(artwork("+--+\n+--+"), artwork("<--->\n|   |")))
    #expect(
      spoken(in: text).map(\.pronunciation) == [
        AccessibleReading.labelPronunciation, AccessibleReading.silence,
        AccessibleReading.labelPronunciation, AccessibleReading.silence,
      ])
  }

  #if canImport(UIKit)
    @Test func `the build puts the pronunciation where UIKit reads it`() throws {
      let text = built(Fixtures.document(artwork("+--+\n|  |\n+--+")))
      let first = try #require(spoken(in: text).first)
      let location = try Fixtures.offset(of: first.line, in: text)
      var extent = NSRange()
      let value = text.attribute(
        .accessibilitySpeechIPANotation, at: location,
        longestEffectiveRange: &extent, in: NSRange(location: 0, length: text.length))
      #expect(value as? String == AccessibleReading.labelPronunciation)
      #expect(extent == NSRange(location: location, length: 4))
    }

    /// Only what VoiceOver says as a diagram on macOS is silenced on iOS.
    @Test func `prose, source code and artwork that is not a drawing carry no speech`() {
      let text = built(
        Fixtures.document(
          .paragraph(Paragraph(text: "A plain paragraph.")),
          .preformatted(Preformatted(kind: .sourceCode, text: "+--+\n|  |\n+--+", type: "c")),
          artwork("rule = 1*ALPHA\nother = DIGIT")))
      var found = false
      text.enumerateAttribute(
        .accessibilitySpeechIPANotation, in: NSRange(location: 0, length: text.length)
      ) { value, _, _ in
        if value != nil { found = true }
      }
      #expect(!found)
    }

    @Test func `a printed page carries no speech`() {
      var style = ReadingStyle()
      style.emitsLinks = false
      let text = DocumentTextBuilder.build(
        Fixtures.document(artwork("+--+\n|  |\n+--+")), style: style
      ).text
      var found = false
      text.enumerateAttribute(
        .accessibilitySpeechIPANotation, in: NSRange(location: 0, length: text.length)
      ) { value, _, _ in
        if value != nil { found = true }
      }
      #expect(!found)
    }
  #endif
}
