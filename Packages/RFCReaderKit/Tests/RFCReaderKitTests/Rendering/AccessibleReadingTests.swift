import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// What VoiceOver is given for a range of the reader's text (#12): prose as it is,
/// a diagram as one spoken label instead of its box drawing.
@Suite("Accessible reading")
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

  /// RFCXML's `name` on artwork is a file name to extract it to, not a title:
  /// VoiceOver says "Diagram", never "tcp-header.txt, diagram".
  @Test func `a named diagram is still said as a diagram`() {
    let text = built(Fixtures.document(figure(named: "tcp-header.txt")))
    let reading = reading(whole(text), in: text)
    #expect(reading.contains("[Diagram]\nFigure 3"))
    #expect(!reading.contains("tcp-header.txt"))
  }

  /// The rotor lists figures by name, and is never read through, so there the
  /// caption is not said twice: it is what tells one figure from the next.
  @Test func `the rotor names a figure by its caption`() throws {
    let text = built(Fixtures.document(figure(named: "tcp-header.txt")))
    let offset = try Fixtures.offset(of: "+--+", in: text)
    #expect(AccessibleReading.rotorLabel(at: offset, in: text) == "Figure 3: Packet layout")
  }

  @Test func `the rotor calls a diagram with no caption a diagram`() throws {
    let text = built(Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: diagram))))
    let offset = try Fixtures.offset(of: "+--+", in: text)
    #expect(AccessibleReading.rotorLabel(at: offset, in: text) == "Diagram")
  }

  /// An informative chip is said as its label and its kind (#457), over the chip's
  /// own range, so the text view can keep the link it is: said as a plain label, it
  /// lost the link trait a normative chip keeps.
  @Test func `an informative chip is said as a chip, with its range`() throws {
    let text = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: style).text
    let chips = AccessibleReading.pieces(of: whole(text), in: text).compactMap { piece in
      if case .chipLabel(let label, let range) = piece { (label, range) } else { nil }
    }
    let chip = try #require(chips.first)
    #expect(chip.0.hasSuffix(", informative"))
    #expect(text.attribute(.link, at: NSMaxRange(chip.1) - 1, effectiveRange: nil) != nil)
    #expect(text.attribute(.rfcChip, at: chip.1.location, effectiveRange: nil) != nil)
    // Where an accessor takes no range, the label is said as any other.
    var asked: [NSRange] = []
    let said = reading(chip.1, in: text, asked: &asked)
    #expect(said == "[\(chip.0)]")
  }

  @Test func `source code is read as text`() {
    let text = built(
      Fixtures.document(.preformatted(Preformatted(kind: .sourceCode, text: "a = b", type: "abnf")))
    )
    // Read as its words, not as a diagram.
    let labels = AccessibleReading.pieces(of: whole(text), in: text).compactMap { piece in
      if case .label(let label) = piece { label } else { nil }
    }
    #expect(labels.isEmpty)
    #expect(reading(whole(text), in: text).contains("a = b"))
  }

  /// The copy button is a pointer's control VoiceOver cannot press, so it is said
  /// neither as a label nor as the object-replacement character it is set as.
  @Test func `a code block's copy button is not read`() {
    let text = built(
      Fixtures.document(.preformatted(Preformatted(kind: .sourceCode, text: "a = b", type: "abnf")))
    )
    let reading = reading(whole(text), in: text)
    #expect(!reading.contains("\u{FFFC}"))
    #expect(!reading.contains("["))
    #expect(reading.contains("ABNF"), "the language is still read")
  }

  /// Artwork that is not a drawing reads perfectly well as words, and legacy
  /// documents set every block that is not prose as artwork: grammars, message
  /// examples, packet notation. RFC 8999's four artworks are packet notation.
  @Test func `artwork that is not a drawing is read as text`() throws {
    let text = built(try Fixtures.rfc8999())
    let reading = reading(whole(text), in: text)
    #expect(reading.contains("Long Header Packet {"))
    #expect(!reading.contains("[Diagram]"))
  }

  /// RFC 793's drawings are said as diagrams: none of the header's bit layout or
  /// the state diagram's boxes is read out.
  @Test func `RFC 793's drawings are diagrams`() throws {
    let text = built(try Fixtures.document(named: "rfc793.txt"))
    let reading = reading(whole(text), in: text)
    #expect(reading.contains("[Diagram]"))
    #expect(!reading.contains("+-+-+-+-+-+"))
    #expect(!reading.contains("+---------+ ---------\\"))
    // Its receive test table is a table, and is read.
    #expect(reading.contains("Segment Receive  Test"))
  }

  /// RFC 5234's rules are grammar, not drawings, however many `<`, `*` and `/`
  /// they hold: `<a>*<b>element` is read as it is.
  @Test func `RFC 5234's rules are not diagrams`() throws {
    let text = built(try Fixtures.document(named: "rfc5234.txt"))
    let reading = reading(whole(text), in: text)
    #expect(!reading.contains("[Diagram]"))
    #expect(reading.contains("<a>*<b>element"))
  }

  /// Over a whole real document, every character is either read as text or stands
  /// under a label, a diagram's or a backlink caption's (#183): nothing is skipped,
  /// nothing is read twice.
  ///
  /// RFC 793 has ten drawings: its layering and header diagrams, the sequence
  /// spaces, the state diagram. RFC 8999's artworks are packet notation, RFC 5234's
  /// are grammar rules and RFC 2119 has none, so those check that what is not a
  /// diagram comes back whole.
  @Test(arguments: [
    ("rfc793.txt", 10), ("rfc5234.txt", 0), ("rfc8999.xml", 0), ("rfc2119.txt", 0),
  ])
  func `nothing is skipped or read twice`(fixture: String, diagrams: Int) throws {
    let text = built(try Fixtures.document(named: fixture))
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
    var unread = IndexSet()
    text.enumerateAttribute(.rfcVerbatim, in: whole(text)) { value, range, _ in
      guard let box = value as? VerbatimBox, AccessibleReading.isDiagram(box) else { return }
      unread.formUnion(IndexSet(integersIn: range.location..<NSMaxRange(range)))
    }
    var chips = 0
    text.enumerateAttribute(.rfcSpoken, in: whole(text)) { value, range, _ in
      guard value != nil else { return }
      chips += 1
      unread.formUnion(IndexSet(integersIn: range.location..<NSMaxRange(range)))
    }
    // The reader's own controls go unread with no label at all.
    var controls = IndexSet()
    text.enumerateAttribute(.attachment, in: whole(text)) { value, range, _ in
      guard value != nil,
        text.attribute(.rfcReaderOnly, at: range.location, effectiveRange: nil) != nil,
        text.attribute(.rfcSpoken, at: range.location, effectiveRange: nil) == nil
      else { return }
      controls.formUnion(IndexSet(integersIn: range.location..<NSMaxRange(range)))
    }
    // Only diagrams, chips and controls go unread, and all but the controls are
    // under a label.
    #expect(covered.isDisjoint(with: controls))
    #expect(covered.union(unread).union(controls).count == text.length)
    #expect(labels == diagrams + chips)
  }

  /// Guard level: what makes a block of artwork a drawing, over hand-written lines
  /// in the shape of an RFC's.
  /// Source code is never a diagram, whatever it looks like.
  @Test func `source code that looks like a drawing is not a diagram`() {
    let box = VerbatimBox(Preformatted(kind: .sourceCode, text: diagram))
    #expect(!AccessibleReading.isDiagram(box))
  }

  @Test func `a rendered packet diagram is said as its fields`() {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: ReadingStyle())
    let pieces = AccessibleReading.pieces(
      of: NSRange(location: 0, length: built.text.length), in: built.text)
    #expect(
      pieces.first(where: Self.isLabel)
        == .label(
          "Packet diagram, 16 bits a row: Type, 8 bits; Length, 8 bits; Value, variable length"))
  }

  @Test func `a packet diagram shown as source is said as a diagram`() {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: ReadingStyle(), choices: PresentationChoices(chosen: [.ordinal(0): .text]))
    let pieces = AccessibleReading.pieces(
      of: NSRange(location: 0, length: built.text.length), in: built.text)
    #expect(pieces.first(where: Self.isLabel) == .label(AccessibleReading.label))
  }

  /// The document's heading comes before the diagram, as text.
  private static func isLabel(_ piece: AccessibleReading.Piece) -> Bool {
    if case .label = piece { return true }
    return false
  }

  /// Whether a block is said as a diagram is its rendering's to say where it has
  /// one, and the drawing-share heuristic's only where it has none.
  @Test func `a rendered block with a spoken label is a diagram whatever it draws with`() {
    let box = VerbatimBox(
      Preformatted(kind: .artwork, text: "mostly words and few lines"), shown: .rendered,
      spokenLabel: "Packet diagram")
    #expect(AccessibleReading.isDiagram(box))
  }
}
