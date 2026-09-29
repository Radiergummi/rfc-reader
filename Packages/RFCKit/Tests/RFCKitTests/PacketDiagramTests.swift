import Foundation
import Testing

@testable import RFCKit

/// A packet diagram is recognized exactly or not at all (#47): the bit ruler fixes
/// every bit's column, and every other line has to be a border or a row of fields
/// delimited on bit boundaries. The diagrams here are hand-written in the shape of
/// an RFC's, not quoted from one.
@Suite("Packet diagrams")
struct PacketDiagramTests {
  private static let ruler32 = [
    "    0                   1                   2                   3",
    "    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1",
  ]
  private static let ruler16 = [
    "    0                   1",
    "    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5",
  ]
  private static let border32 =
    "   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+"
  private static let border16 = "   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+"

  private static let header =
    ruler32 + [
      border32,
      "   |    Version    |      Kind     |             Length            |",
      border32,
      "   |                           Identifier                          |",
      border32,
    ]

  private func recognize(_ lines: [String]) -> PacketDiagram? {
    PacketDiagram.recognize(lines.joined(separator: "\n"))
  }

  private func field(
    _ name: String, row: Int, offset: Int, width: Int, rows: Int = 1, variable: Bool = false
  ) -> PacketDiagram.Field {
    PacketDiagram.Field(
      name: name, row: row, bitOffset: offset, bitWidth: width, rowSpan: rows,
      isVariableLength: variable)
  }

  // MARK: - Recognized

  @Test func `a 32-bit diagram gives each field its row, offset and width`() throws {
    let diagram = try #require(recognize(Self.header))
    #expect(diagram.bitsPerRow == 32)
    #expect(
      diagram.fields == [
        field("Version", row: 0, offset: 0, width: 8),
        field("Kind", row: 0, offset: 8, width: 8),
        field("Length", row: 0, offset: 16, width: 16),
        field("Identifier", row: 1, offset: 0, width: 32),
      ])
  }

  /// A row can take several lines, and a one-bit field spells its name down them.
  @Test func `a row over several lines joins each field's text, and a one-bit name reads down`()
    throws
  {
    let diagram = try #require(
      recognize(
        Self.ruler16 + [
          Self.border16,
          "   | Hdr |     |E|A|               |",
          "   | Len | Rsv |C|C|     Window    |",
          "   |     |     |N|K|               |",
          Self.border16,
        ]))
    #expect(diagram.bitsPerRow == 16)
    #expect(
      diagram.fields == [
        field("Hdr Len", row: 0, offset: 0, width: 3),
        field("Rsv", row: 0, offset: 3, width: 3),
        field("ECN", row: 0, offset: 6, width: 1),
        field("ACK", row: 0, offset: 7, width: 1),
        field("Window", row: 0, offset: 8, width: 8),
      ])
  }

  /// A border with no rule over the field, only its ends, continues it into the next
  /// row, and may carry its name.
  @Test func `a field continued past an open border spans the rows`() throws {
    let diagram = try #require(
      recognize(
        Self.ruler32 + [
          Self.border32,
          "   |                                                               |",
          "   +                          Peer Address                         +",
          "   |                                                               |",
          Self.border32,
        ]))
    #expect(diagram.fields == [field("Peer Address", row: 0, offset: 0, width: 64, rows: 2)])
  }

  @Test func `a field between tildes has a variable length`() throws {
    let diagram = try #require(
      recognize(
        Self.ruler16 + [
          Self.border16,
          "   |      Type     |     Length    |",
          Self.border16,
          "   ~             Value             ~",
          Self.border16,
        ]))
    #expect(
      diagram.fields == [
        field("Type", row: 0, offset: 0, width: 8),
        field("Length", row: 0, offset: 8, width: 8),
        field("Value", row: 1, offset: 0, width: 16, variable: true),
      ])
  }

  @Test func `a last row may stop short of the ruler's width`() throws {
    let diagram = try #require(
      recognize(
        Self.ruler32 + [
          Self.border32,
          "   |            Checksum           |              Next             |",
          Self.border32,
          "   |      Tag      |",
          "   +-+-+-+-+-+-+-+-+",
        ]))
    #expect(diagram.fields.last == field("Tag", row: 1, offset: 0, width: 8))
    #expect(diagram.fields.count == 3)
  }

  /// The parser keeps a caption with the artwork above it, so a diagram's block can
  /// end in one. It is not part of the grid, and a blank line keeps it apart.
  @Test func `a caption after a blank line is not part of the diagram`() throws {
    let diagram = try #require(recognize(Self.header + ["", "        Figure 1: Example Header"]))
    #expect(diagram.fields.count == 4)
  }

  /// A diagram set at the margin can have no room for the boundary left of bit 0,
  /// and puts its grid's corners under the ruler's digits: the same grid, one
  /// column to the right of where the ruler puts it.
  @Test func `a grid one column right of its ruler is read against the ruler`() throws {
    let diagram = try #require(
      recognize([
        "0                   1",
        "0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5",
        "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+",
        "|      Type     |     Length    |",
        "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+",
      ]))
    #expect(
      diagram.fields == [
        field("Type", row: 0, offset: 0, width: 8), field("Length", row: 0, offset: 8, width: 8),
      ])
  }

  /// The other way to number the tens: a digit over every bit from ten on.
  @Test func `a tens line may number every bit from ten on`() throws {
    let diagram = try #require(
      recognize(
        [
          "                        1 1 1 1 1 1",
          "    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5",
          Self.border16,
          "   |      Type     |     Length    |",
          Self.border16,
        ]))
    #expect(diagram.fields.map(\.name) == ["Type", "Length"])
  }

  /// Some leave the first ten unnumbered.
  @Test func `a tens line may leave out its leading zero`() throws {
    let diagram = try #require(
      recognize(
        [
          "                        1",
          "    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5",
          Self.border16,
          "   |      Type     |     Length    |",
          Self.border16,
        ]))
    #expect(diagram.fields.map(\.name) == ["Type", "Length"])
  }

  /// `~` is the usual mark for a field of no fixed length, and `:`, `/`, `\` and
  /// `.` the others in use; each stands where the field's delimiter would.
  @Test(arguments: [":", "/", "\\", "."])
  func `a field between other variable-length marks has a variable length`(mark: String) throws {
    let diagram = try #require(
      recognize(
        Self.ruler16 + [
          Self.border16,
          "   |      Type     |     Length    |",
          Self.border16,
          "   |                               |",
          "   \(mark)             Value             \(mark)",
          "   |                               |",
          Self.border16,
        ]))
    #expect(diagram.fields.last == field("Value", row: 1, offset: 0, width: 16, variable: true))
  }

  /// The mark belongs to the field it stands against, not to the row.
  @Test func `only the field against a variable-length mark has a variable length`() throws {
    let diagram = try #require(
      recognize(
        Self.ruler16 + [
          Self.border16,
          "   |  Kind |          Options      ~",
          Self.border16,
        ]))
    #expect(
      diagram.fields == [
        field("Kind", row: 0, offset: 0, width: 4),
        field("Options", row: 0, offset: 4, width: 12, variable: true),
      ])
  }

  /// A field that continues under part of a border takes its name from that part
  /// only, not from the rule over the fields beside it.
  @Test func `a field continued under part of a border does not take the rule as its name`()
    throws
  {
    let diagram = try #require(
      recognize(
        Self.ruler16 + [
          Self.border16,
          "   |                               |",
          "   +     Address   +-+-+-+-+-+-+-+-+",
          "   |               |      Tag      |",
          Self.border16,
        ]))
    #expect(
      diagram.fields == [
        field("Address", row: 0, offset: 0, width: 24, rows: 2),
        field("Tag", row: 1, offset: 8, width: 8),
      ])
  }

  /// A hyphen in a name written across an open border is part of the name, not a
  /// rule that closes the border under it.
  @Test func `a hyphenated name across an open border keeps the field whole`() throws {
    let diagram = try #require(
      recognize(
        Self.ruler16 + [
          Self.border16,
          "   |                               |",
          "   +          Hop-by-Hop           +",
          "   |                               |",
          Self.border16,
        ]))
    #expect(diagram.fields == [field("Hop-by-Hop", row: 0, offset: 0, width: 32, rows: 2)])
  }

  /// A rule of `=` closes a border as one of `-` does, where a header ends and what
  /// it carries begins.
  @Test func `a double rule closes the border under a field`() throws {
    let diagram = try #require(
      recognize(
        Self.ruler16 + [
          Self.border16,
          "   |             Source            |",
          "   +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+",
          "   |            Payload            |",
          Self.border16,
        ]))
    #expect(
      diagram.fields == [
        field("Source", row: 0, offset: 0, width: 16),
        field("Payload", row: 1, offset: 0, width: 16),
      ])
  }

  /// Anything further off is not the grid the ruler numbers.
  @Test func `a grid two columns off its ruler is not a packet diagram`() {
    #expect(
      recognize([
        "0                   1",
        "0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5",
        " +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+",
        " |      Type     |     Length    |",
        " +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+",
      ]) == nil)
  }

  // MARK: - Rejected

  @Test func `a box drawing with no ruler is not a packet diagram`() {
    #expect(recognize(["   +--------+", "   | Client |", "   +--------+"]) == nil)
  }

  @Test func `a table is not a packet diagram`() {
    let table = [
      "   +--------+-------------+",
      "   | Code   | Meaning     |",
      "   +--------+-------------+",
      "   | 1      | Accepted    |",
      "   +--------+-------------+",
    ]
    #expect(recognize(table) == nil)
  }

  @Test func `a delimiter off a bit boundary is not a packet diagram`() {
    var lines = Self.header
    lines[3] = "   |    Version     |     Kind     |             Length            |"
    #expect(recognize(lines) == nil)
  }

  @Test func `a ruler over prose is not a packet diagram`() {
    #expect(recognize(Self.ruler32 + ["   The bits are numbered from the left, as above."]) == nil)
  }

  /// Every line of a row has to put a field's ends in the same place.
  @Test func `a row whose lines disagree on a boundary is not a packet diagram`() {
    let lines =
      Self.ruler16 + [
        Self.border16,
        "   |      Type     |     Length    |",
        "   |      Type      Continued      |",
        Self.border16,
      ]
    // The second line has text where the first has a delimiter.
    #expect(recognize(lines) == nil)
  }

  /// Two fields in one row joined through the rows around them would make one
  /// field of bits that are not contiguous.
  @Test func `a field drawn twice in one row is not a packet diagram`() {
    let openAtBothEnds = "   +       +-+-+-+-+-+-+-+-+       +"
    let lines =
      Self.ruler16 + [
        Self.border16,
        "   |       First   |    Second     |",
        openAtBothEnds,
        "   |       |     Middle    |       |",
        openAtBothEnds,
        "   |             Last              |",
        Self.border16,
      ]
    #expect(recognize(lines) == nil)
  }

  /// A field continued into the next row picks up where it left off: it runs to
  /// the end of every row but its last, and from the start of every row but its
  /// first. The same bits of two rows are not contiguous.
  @Test func `a field over the same bits of two rows is not a packet diagram`() {
    let lines =
      Self.ruler16 + [
        Self.border16,
        "   |       |       Kind            |",
        "   +  Tall +-+-+-+-+-+-+-+-+-+-+-+-+",
        "   |       |       Size            |",
        Self.border16,
      ]
    #expect(recognize(lines) == nil)
  }

  /// A tilde standing on a boundary inside a row would be the end of a field of
  /// no fixed length, which only a row's ends can mark.
  @Test func `a tilde on a boundary inside a row is not a packet diagram`() {
    let lines =
      Self.ruler16 + [
        Self.border16,
        "   |      Type     ~     Value     ~",
        Self.border16,
      ]
    #expect(recognize(lines) == nil)
  }

  /// A corner stands where a delimiter meets a border. One inside a field that
  /// continues past the border meets none.
  @Test func `a corner inside a field continued past a border is not a packet diagram`() {
    let lines =
      Self.ruler16 + [
        Self.border16,
        "   |                               |",
        "   +               +               +",
        "   |            Address            |",
        Self.border16,
      ]
    #expect(recognize(lines) == nil)
  }

  @Test func `a ruler with nothing under it is not a packet diagram`() {
    #expect(recognize(Self.ruler32) == nil)
  }

  // MARK: - Through parse

  /// RFC 793's TCP header, as the parser hands it over, caption and all.
  @Test func `the TCP header in RFC 793 is recognized with every field`() throws {
    let document = LegacyTextParser.parse(try Fixtures.data("rfc793.txt"))
    let artwork = try #require(
      document.blocks.lazy.compactMap { block -> String? in
        guard case .preformatted(let content) = block, content.text.contains("Source Port")
        else { return nil }
        return content.text
      }.first)
    let diagram = try #require(PacketDiagram.recognize(artwork))
    #expect(diagram.bitsPerRow == 32)
    #expect(
      diagram.fields.map(\.name) == [
        "Source Port", "Destination Port", "Sequence Number", "Acknowledgment Number",
        "Data Offset", "Reserved", "URG", "ACK", "PSH", "RST", "SYN", "FIN", "Window",
        "Checksum", "Urgent Pointer", "Options", "Padding", "data",
      ])
    #expect(
      diagram.fields.map(\.bitWidth) == [
        16, 16, 32, 32, 4, 6, 1, 1, 1, 1, 1, 1, 16, 16, 16, 24, 8, 32,
      ])
  }
}
