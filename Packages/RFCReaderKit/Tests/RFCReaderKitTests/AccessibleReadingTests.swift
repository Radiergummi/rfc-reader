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

  private func built(_ blocks: Block...) -> NSAttributedString {
    DocumentTextBuilder.build(
      RFCDocument(
        header: DocumentHeader(title: "T"),
        sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: blocks)],
        source: .xml),
      style: style
    ).text
  }

  private let diagram = "+--+\n|  |\n+--+"

  private func figure(named name: String? = nil) -> Block {
    .figure(
      Figure(
        title: "Packet layout",
        number: 3,
        blocks: [.preformatted(Preformatted(kind: .artwork, text: diagram, name: name))]))
  }

  /// The pieces read back into one string, with each label in brackets so a test
  /// can see where it went.
  private func reading(_ range: NSRange, in text: NSAttributedString) -> String {
    AccessibleReading.pieces(of: range, in: text).map { piece in
      switch piece {
      case .text(let range): (text.string as NSString).substring(with: range)
      case .label(let label): "[\(label)]"
      }
    }.joined()
  }

  private func whole(_ text: NSAttributedString) -> NSRange {
    NSRange(location: 0, length: text.length)
  }

  @Test func `prose is read exactly as it is`() {
    let text = built(.paragraph(Paragraph(text: "A plain paragraph.")))
    #expect(AccessibleReading.pieces(of: whole(text), in: text) == [.text(whole(text))])
  }

  @Test func `a diagram is read as one label and none of its characters`() throws {
    let text = built(.paragraph(Paragraph(text: "Before.")), figure())
    let reading = reading(whole(text), in: text)

    #expect(reading.contains("[Diagram]\nFigure 3: Packet layout"))
    #expect(!reading.contains("+--+"))
    #expect(!reading.contains("|  |"))
    #expect(reading.hasPrefix(try #require(text.string.components(separatedBy: "+--+").first)))
  }

  /// VoiceOver reads a line at a time. Asked for each line of a diagram in turn, the
  /// label comes back once, on the first, and the rest are silent.
  @Test func `read a line at a time, a diagram is announced once`() throws {
    let text = built(figure())
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
    let text = built(figure())
    let inside = try Fixtures.offset(of: "|  |", in: text)
    let reading = reading(NSRange(location: inside, length: text.length - inside), in: text)
    #expect(!reading.contains("["))
    #expect(reading.hasPrefix("\nFigure 3"))
  }

  /// The name is the one thing about a diagram the text does not already say; the
  /// caption is set right after it, so a label repeating it would be read twice.
  @Test func `a named diagram says its name`() {
    let text = built(figure(named: "QUIC long header"))
    #expect(reading(whole(text), in: text).contains("[QUIC long header, diagram]\nFigure 3"))
  }

  @Test func `source code is read as text`() {
    let text = built(.preformatted(Preformatted(kind: .sourceCode, text: "a = b", type: "abnf")))
    #expect(AccessibleReading.pieces(of: whole(text), in: text) == [.text(whole(text))])
  }

  /// Over a whole real document, every character is either read as text or stands
  /// under a diagram's label: nothing is skipped, nothing is read twice.
  @Test(arguments: ["rfc8999.xml", "rfc2119.txt"])
  func `nothing is skipped or read twice`(fixture: String) throws {
    let document = fixture.hasSuffix(".xml") ? try Fixtures.rfc8999() : try Fixtures.rfc2119()
    let text = DocumentTextBuilder.build(document, style: style).text
    var covered = IndexSet()
    var labels = 0
    for piece in AccessibleReading.pieces(of: whole(text), in: text) {
      guard case .text(let range) = piece else {
        labels += 1
        continue
      }
      let span = IndexSet(integersIn: range.location..<NSMaxRange(range))
      #expect(covered.intersection(span).isEmpty)
      covered.formUnion(span)
    }
    var artwork = IndexSet()
    text.enumerateAttribute(.rfcVerbatim, in: whole(text)) { value, range, _ in
      guard let box = value as? VerbatimBox, box.content.kind == .artwork else { return }
      artwork.formUnion(IndexSet(integersIn: range.location..<NSMaxRange(range)))
    }
    // Only artwork goes unread, and all of it is under a label.
    #expect(covered.union(artwork).count == text.length)
    #expect(labels == AccessibleReading.diagrams(in: text).count)
  }
}
