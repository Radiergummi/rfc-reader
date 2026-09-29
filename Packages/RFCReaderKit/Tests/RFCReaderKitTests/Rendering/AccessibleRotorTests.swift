import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// VoiceOver's rotors over the reader's one text view: which runs are stops, and
/// which stop comes next.
@Suite("Accessible reading: rotors")
@MainActor
struct AccessibleRotorTests {
  private let diagram = "+--+\n|  |\n+--+"

  private func built(_ document: RFCDocument) -> NSAttributedString {
    DocumentTextBuilder.build(document, style: ReadingStyle()).text
  }

  private var artwork: Block { .preformatted(Preformatted(kind: .artwork, text: diagram)) }

  @Test func `each heading and each link is a stop over its text`() throws {
    let text = built(
      Fixtures.document(
        .paragraph(
          Paragraph([.link(try #require(URL(string: "https://example.com")), [.text("here")])]))))
    let rotors = AccessibleReading.Rotors(text)
    let heading = try Fixtures.offset(of: "S", in: text)
    #expect(rotors.headings.count == 1)
    #expect(rotors.headings.first.map { NSLocationInRange(heading, $0.range) } == true)
    #expect(rotors.links.map { (text.string as NSString).substring(with: $0.range) } == ["here"])
    #expect(rotors.headings.allSatisfy { $0.label == nil })
  }

  /// Two diagrams back to back are two stops, each over the whole of its own
  /// block, however many storage runs the block is.
  @Test func `each diagram is one stop over its whole block`() throws {
    let text = built(Fixtures.document(artwork, artwork))
    let rotors = AccessibleReading.Rotors(text)
    #expect(rotors.diagrams.count == 2)
    let first = try #require(rotors.diagrams.first)
    let second = try #require(rotors.diagrams.last)
    #expect(NSMaxRange(first.range) == second.range.location)
    #expect(first.range == text.extent(ofBox: .rfcVerbatim, at: first.range.location))
    #expect(first.label == "Diagram")
  }

  @Test func `code is not a diagram stop`() {
    let text = built(
      Fixtures.document(.preformatted(Preformatted(kind: .sourceCode, text: "a = b", type: "abnf")))
    )
    #expect(AccessibleReading.Rotors(text).diagrams.isEmpty)
  }

  private let stops = [10, 20, 30].map {
    AccessibleReading.RotorItem(range: NSRange(location: $0, length: 5), label: nil)
  }

  private func next(after location: Int?, forward: Bool) -> Int? {
    AccessibleReading.nextRotorItem(in: stops, after: location, forward: forward)?.range.location
  }

  /// No current stop starts from the end the direction implies.
  @Test func `with no current stop the search starts at an end`() {
    #expect(next(after: nil, forward: true) == 10)
    #expect(next(after: nil, forward: false) == 30)
    #expect(next(after: NSNotFound, forward: true) == 10)
  }

  @Test func `the next stop is strictly after and the previous strictly before`() {
    #expect(next(after: 10, forward: true) == 20)
    #expect(next(after: 12, forward: true) == 20)
    #expect(next(after: 20, forward: false) == 10)
    #expect(next(after: 25, forward: false) == 20)
  }

  /// Past either end there is no stop, which VoiceOver marks with a boundary sound.
  @Test func `there is no stop past either end`() {
    #expect(next(after: 30, forward: true) == nil)
    #expect(next(after: 10, forward: false) == nil)
    #expect(AccessibleReading.nextRotorItem(in: [], after: nil, forward: true) == nil)
  }
}
