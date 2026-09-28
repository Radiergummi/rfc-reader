import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What VoiceOver is given for a range of the reader's text (#12): prose as it is,
/// a diagram as one spoken label instead of its box drawing.
@Suite("Accessible reading")
@MainActor
struct AccessibleReadingTests {
  private let style = ReadingStyle()

  private func built(_ document: RFCDocument) -> NSAttributedString {
    DocumentTextBuilder.build(document, style: style).text
  }

  private let diagram = "+--+\n|  |\n+--+"

  private func figure(named name: String? = nil) -> Block {
    .figure(
      Figure(
        title: "Packet layout",
        number: 3,
        blocks: [.preformatted(Preformatted(kind: .artwork, text: diagram, name: name))]))
  }

  /// What the text view's accessors return for `range`, with each label in brackets
  /// so a test can see where it went, and every range handed to AppKit in `asked`.
  private func reading(
    _ range: NSRange, in text: NSAttributedString, asked: inout [NSRange]
  ) -> String? {
    AccessibleReading.reading(
      range, in: text,
      text: { range in
        asked.append(range)
        return range.length > 0 ? (text.string as NSString).substring(with: range) : nil
      },
      label: { "[\($0)]" },
      join: { $0.joined() })
  }

  private func reading(_ range: NSRange, in text: NSAttributedString) -> String {
    var asked: [NSRange] = []
    return reading(range, in: text, asked: &asked) ?? ""
  }

  private func whole(_ text: NSAttributedString) -> NSRange {
    NSRange(location: 0, length: text.length)
  }

  @Test func `prose is read exactly as it is`() {
    let text = built(Fixtures.document(.paragraph(Paragraph(text: "A plain paragraph."))))
    #expect(AccessibleReading.pieces(of: whole(text), in: text) == [.text(whole(text))])
  }

  /// Prose is AppKit's to read, in one piece and exactly the range asked for, so it
  /// keeps every attribute AppKit gives VoiceOver.
  @Test func `a range over prose is left to AppKit whole`() {
    let text = built(Fixtures.document(.paragraph(Paragraph(text: "A plain paragraph."))))
    var asked: [NSRange] = []
    _ = reading(whole(text), in: text, asked: &asked)
    #expect(asked == [whole(text)])
  }

  /// Nothing to substitute in an empty range, or one the text does not hold: what
  /// VoiceOver gets for it is AppKit's answer, not an empty string of ours.
  @Test(arguments: [NSRange(location: 0, length: 0), NSRange(location: NSNotFound, length: 0)])
  func `a range with nothing in it is left to AppKit`(range: NSRange) {
    let text = built(Fixtures.document(figure()))
    var asked: [NSRange] = []
    #expect(reading(range, in: text, asked: &asked) == nil)
    #expect(asked == [range])
  }

  /// A diagram's later lines have no label and no text, and are silent: an empty
  /// reading, not AppKit's, which would be the box drawing.
  @Test func `a diagram's later line is silent`() throws {
    let text = built(Fixtures.document(figure()))
    let inside = try Fixtures.offset(of: "|  |", in: text)
    var asked: [NSRange] = []
    #expect(reading(NSRange(location: inside, length: 4), in: text, asked: &asked) == "")
    #expect(asked.isEmpty)
  }

  /// Two blocks of artwork in a row, as legacy documents often set them, touch with
  /// nothing between them; each is still announced, and neither is read out.
  @Test func `two diagrams back to back are each announced`() {
    let artwork = Block.preformatted(Preformatted(kind: .artwork, text: diagram))
    let text = built(Fixtures.document(artwork, artwork))
    let reading = reading(whole(text), in: text)
    #expect(reading.contains("[Diagram]\n[Diagram]\n"))
    #expect(!reading.contains("+--+"))
  }

  @Test func `a diagram is read as one label and none of its characters`() throws {
    let text = built(Fixtures.document(.paragraph(Paragraph(text: "Before.")), figure()))
    let reading = reading(whole(text), in: text)

    #expect(reading.contains("[Diagram]\nFigure 3: Packet layout"))
    #expect(!reading.contains("+--+"))
    #expect(!reading.contains("|  |"))
    #expect(reading.hasPrefix(try #require(text.string.components(separatedBy: "+--+").first)))
  }

  /// VoiceOver reads a line at a time. Asked for each line of a diagram in turn, the
  /// label comes back once, on the first, and the rest are silent.
  @Test func `read a line at a time, a diagram is announced once`() throws {
    let text = built(Fixtures.document(figure()))
    let start = try Fixtures.offset(of: "+--+", in: text)
    var lines: [String] = []
    var location = start
    for line in diagram.split(separator: "\n") {
      let range = NSRange(location: location, length: line.utf16.count + 1)
      lines.append(reading(range, in: text))
      location = NSMaxRange(range)
    }
    #expect(lines == ["[Diagram]", "", "\n"])
  }

  @Test func `a range that starts inside a diagram does not announce it`() throws {
    let text = built(Fixtures.document(figure()))
    let inside = try Fixtures.offset(of: "|  |", in: text)
    let reading = reading(NSRange(location: inside, length: text.length - inside), in: text)
    #expect(!reading.contains("["))
    #expect(reading.hasPrefix("\nFigure 3"))
  }

  /// The name is the one thing about a diagram the text does not already say; the
  /// caption is set right after it, so a label repeating it would be read twice.
  @Test func `a named diagram says its name`() {
    let text = built(Fixtures.document(figure(named: "QUIC long header")))
    #expect(reading(whole(text), in: text).contains("[QUIC long header, diagram]\nFigure 3"))
  }

  @Test func `source code is read as text`() {
    let text = built(
      Fixtures.document(.preformatted(Preformatted(kind: .sourceCode, text: "a = b", type: "abnf")))
    )
    #expect(AccessibleReading.pieces(of: whole(text), in: text) == [.text(whole(text))])
  }

  /// Over a whole real document, every character is either read as text or stands
  /// under a diagram's label: nothing is skipped, nothing is read twice.
  ///
  /// RFC 8999 has four artworks; RFC 2119 has none, and checks that prose alone
  /// comes back whole.
  @Test(arguments: [("rfc8999.xml", 4), ("rfc2119.txt", 0)])
  func `nothing is skipped or read twice`(fixture: String, diagrams: Int) throws {
    let document = fixture.hasSuffix(".xml") ? try Fixtures.rfc8999() : try Fixtures.rfc2119()
    let text = built(document)
    var covered = IndexSet()
    var labels = 0
    for piece in AccessibleReading.pieces(of: whole(text), in: text) {
      guard case .text(let range) = piece else {
        labels += 1
        continue
      }
      let span = IndexSet(integersIn: range.location..<NSMaxRange(range))
      #expect(covered.isDisjoint(with: span))
      covered.formUnion(span)
    }
    var artwork = IndexSet()
    text.enumerateAttribute(.rfcVerbatim, in: whole(text)) { value, range, _ in
      guard let box = value as? VerbatimBox, box.content.kind == .artwork else { return }
      artwork.formUnion(IndexSet(integersIn: range.location..<NSMaxRange(range)))
    }
    // Only artwork goes unread, and all of it is under a label.
    #expect(covered.union(artwork).count == text.length)
    #expect(labels == diagrams)
  }
}
