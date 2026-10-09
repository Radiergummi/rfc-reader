import Foundation
import Testing

@testable import RFCKit

/// A grid drawn with `+---+` rules and `|` columns is a table (#438). Guard-level,
/// over hand-written grids in the shape of the ones xml2rfc and authors draw.
@Suite("Legacy text parser: box-drawn tables")
struct BoxTableTests {
  private static func cells(_ table: LegacyTextParser.BoxTable?) -> [[String]]? {
    table.map { $0.header + $0.rows }
  }

  /// The rows above a `+===+` rule are the header; every rule between the body's rows
  /// says each stretch between two rules is one row, its cells joined over its lines.
  @Test func `a ruled grid is a table, its header above the double rule`() throws {
    let table = try #require(
      LegacyTextParser.boxTable([
        "+=======+========================+",
        "| Kind  | Meaning                |",
        "+=======+========================+",
        "| 0x01  | The first kind of      |",
        "|       | message                |",
        "+-------+------------------------+",
        "| 0x02  | The second             |",
        "+-------+------------------------+",
      ]))
    #expect(table.header == [["Kind", "Meaning"]])
    #expect(table.rows == [["0x01", "The first kind of message"], ["0x02", "The second"]])
  }

  /// With no rule between the body's rows, each line is a row, and with no double rule
  /// there is no header.
  @Test func `a grid ruled only around it has a row a line`() {
    let table = LegacyTextParser.boxTable([
      "+-----+-----+",
      "| one | 1   |",
      "| two | 2   |",
      "+-----+-----+",
    ])
    #expect(table?.header == [])
    #expect(Self.cells(table) == [["one", "1"], ["two", "2"]])
  }

  /// A body of one row has no rule between rows: a line whose first cell is empty goes
  /// on with the row above, and a word broken after `/` or `-` is joined whole.
  @Test func `a wrapped cell in a body of one row is one cell`() {
    let table = LegacyTextParser.boxTable([
      "+=======+==================+",
      "| Kind  | Reference/       |",
      "|       | Description      |",
      "+=======+==================+",
      "| one   | The only row, it |",
      "|       | wraps once       |",
      "+-------+------------------+",
    ])
    #expect(table?.header == [["Kind", "Reference/Description"]])
    #expect(table?.rows == [["one", "The only row, it wraps once"]])
  }

  /// The columns come from the rules' `+`s: a `|` inside a cell is the cell's text.
  @Test func `a bar inside a cell is text`() {
    let table = LegacyTextParser.boxTable([
      "+--------+-----+",
      "| a | b  | yes |",
      "| c      | no  |",
      "+--------+-----+",
    ])
    #expect(Self.cells(table) == [["a | b", "yes"], ["c", "no"]])
  }

  /// A cell spanning columns has no `|` where the rules have a `+`: the model has no
  /// span, so the grid stays artwork. So does one whose rules disagree, and a drawing
  /// with a box in it.
  @Test(arguments: [
    ["+-----+-----+", "| spans both |", "+-----+-----+"],
    ["+-----+-----+", "| a   | b   |", "+---+-------+"],
    ["+-----+", "| box |--->", "+-----+"],
    ["+-----+-----+", "| a   | b   |"],
  ])
  func `a grid that is not a plain table stays artwork`(lines: [String]) {
    #expect(LegacyTextParser.boxTable(lines) == nil)
  }

  /// A box of one cell, or one row of fields, is a drawing.
  @Test(arguments: [
    ["+-------+", "| Front |", "+-------+"],
    ["+------+----------+", "| kind |  value   |", "+------+----------+"],
  ])
  func `a box or a row of fields is no table`(lines: [String]) {
    #expect(LegacyTextParser.boxTable(lines) == nil)
  }

  /// A cell's text has its white space collapsed, as XML's does.
  @Test func `a cell's spaces collapse`() {
    let table = LegacyTextParser.boxTable([
      "+-----+-----------+", "| a   | two  words|", "| b   | three     |", "+-----+-----------+",
    ])
    #expect(table?.rows.first == ["a", "two words"])
  }

  /// A packet ruler is ruled with `+-+-+`, and its rows are no cells of words.
  @Test func `a packet diagram is no table`() {
    #expect(
      LegacyTextParser.boxTable([
        " 0                   1",
        " 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5",
        "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+",
        "|     Kind      |    Length     |",
        "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+",
      ]) == nil)
  }
}
