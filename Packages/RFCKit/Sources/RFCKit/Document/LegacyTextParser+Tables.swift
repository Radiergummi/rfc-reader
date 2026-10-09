import Foundation

extension LegacyTextParser {
  /// A grid's cells as text, its header's rows first.
  struct BoxTable: Equatable {
    var header: [[String]]
    var rows: [[String]]
  }

  /// A grid drawn with rules, `+---+` or `+===+`, and `|` between its columns, read as
  /// a table (#438), or nil for anything else. The columns are where the rules' `+`s
  /// are, so a `|` inside a cell's text is the cell's; every rule has its `+`s in the
  /// same columns, and every other line a `|` in each, or a cell spans columns, which
  /// the model has no way to say, and the grid stays artwork.
  ///
  /// The rows above a `+===+` rule are the header. Where a rule stands between the
  /// body's rows, as xml2rfc draws one between every two, the lines between two rules
  /// are one row, and a cell running over them is joined; where none does, a line
  /// whose first cell is empty goes on with the row above, as a wrapped cell's does,
  /// and any other line is a row of its own.
  ///
  /// A table has two columns and two rows at least: a box of one cell, or a row of
  /// fields with their widths (RFC 810's address layouts), is a drawing.
  static func boxTable(_ lines: [String]) -> BoxTable? {
    let lines = lines.map { $0.trimmingTrailingWhitespace() }.filter { !$0.isBlank }
    guard let top = lines.first, let columns = ruleColumns(top), columns.count >= 3,
      let bottom = lines.last, ruleColumns(bottom) == columns, lines.count >= 3
    else { return nil }
    // The stretches of lines between rules, and whether the rule closing each is `=`.
    var stretches: [(lines: [Substring], closedByDouble: Bool)] = []
    var current: [Substring] = []
    for line in lines.dropFirst() {
      if let ruled = ruleColumns(line) {
        guard ruled == columns else { return nil }
        guard !current.isEmpty else { return nil }
        stretches.append((current, line.contains("=")))
        current = []
        continue
      }
      let characters = Array(line)
      guard characters.count == columns.last.map({ $0 + 1 }),
        columns.allSatisfy({ characters[$0] == "|" })
      else { return nil }
      current.append(Substring(line))
    }
    guard current.isEmpty else { return nil }
    let headerCount =
      stretches.firstIndex(where: \.closedByDouble).map { $0 + 1 } ?? 0
    func cells(_ line: Substring) -> [String] {
      let characters = Array(line)
      return zip(columns, columns.dropFirst()).map { start, end in
        String(characters[(start + 1)..<end]).split(whereSeparator: \.isWhitespace)
          .joined(separator: " ")
      }
    }
    func joined(_ lines: [Substring]) -> [String] {
      let rows = lines.map(cells)
      return rows[0].indices.map { column in
        joiningWrapped(rows.map { $0[column] }.filter { !$0.isEmpty })
      }
    }
    let header = stretches.prefix(headerCount).map { joined($0.lines) }
    let body = Array(stretches.dropFirst(headerCount))
    // A rule between the body's rows says its stretches are rows; without one, its
    // one stretch is a row a line, but for the lines that go on with a wrapped cell.
    let rows =
      body.count > 1
      ? body.map { joined($0.lines) }
      : body.flatMap { stretch in
        stretch.lines.reduce(into: [[Substring]]()) { rows, line in
          if rows.isEmpty || cells(line).first?.isEmpty == false {
            rows.append([line])
          } else {
            rows[rows.count - 1].append(line)
          }
        }
        .map(joined)
      }
    guard header.count + rows.count >= 2 else { return nil }
    return BoxTable(header: header, rows: rows)
  }

  /// A cell's lines as one: joined with a space, but after a line that ends in `-` or
  /// `/`, where xml2rfc breaks a word (`Reference/` `Description`), with none.
  private static func joiningWrapped(_ pieces: [String]) -> String {
    pieces.reduce(into: "") { text, piece in
      if !text.isEmpty, text.last != "-", text.last != "/" { text += " " }
      text += piece
    }
  }

  /// The columns of a rule's `+`s: a line of `+` and runs of `-` or `=` only, starting
  /// and ending with a `+`, and no two `+`s adjacent. Nil for any other line.
  private static func ruleColumns(_ line: String) -> [Int]? {
    let characters = Array(line)
    guard characters.first == "+", characters.last == "+", characters.count >= 3 else {
      return nil
    }
    var columns: [Int] = []
    for (index, character) in characters.enumerated() {
      switch character {
      case "+":
        if let last = columns.last, last == index - 1 { return nil }
        columns.append(index)
      case "-", "=": continue
      default: return nil
      }
    }
    return columns
  }
}
