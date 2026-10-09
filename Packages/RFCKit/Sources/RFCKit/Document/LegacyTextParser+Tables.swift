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
  /// The rows above a `+===+` rule are the header; the bottom rule closes the grid
  /// whatever it is drawn with. Where a rule stands between the body's rows, as xml2rfc
  /// draws one between every two, the lines between two rules are one row, and a cell
  /// running over them is joined. Where none does, a line whose first cell is empty
  /// goes on with the row above, as a wrapped cell's does, and any other line is a row
  /// of its own. A grid ruled once inside, under its first stretch, with no `=` to say
  /// which, is headed by that stretch, as an author draws a header with a single rule.
  ///
  /// A table has two columns and two rows at least: a box of one cell, or a row of
  /// fields with their widths (RFC 810's address layouts), is a drawing.
  static func boxTable(_ lines: [String]) -> BoxTable? {
    let lines = lines.map { $0.trimmingTrailingWhitespace() }.filter { !$0.isBlank }
    guard lines.count >= 3, let columns = ruleColumns(lines[0]), columns.count >= 3 else {
      return nil
    }
    // The stretches of lines between rules, each line as its cells, and whether the
    // rule closing each is `=`.
    var stretches: [(lines: [[String]], closedByDouble: Bool)] = []
    var current: [[String]] = []
    for line in lines.dropFirst() {
      if let ruled = ruleColumns(line) {
        guard ruled == columns, !current.isEmpty else { return nil }
        stretches.append((current, line.contains("=")))
        current = []
        continue
      }
      let characters = Array(line)
      guard characters.count == columns[columns.count - 1] + 1,
        columns.allSatisfy({ characters[$0] == "|" })
      else { return nil }
      current.append(
        zip(columns, columns.dropFirst()).map { start, end in
          String(characters[(start + 1)..<end]).collapsingWhitespace()
        })
    }
    // The grid ends with a rule.
    guard current.isEmpty else { return nil }
    func joined(_ lines: [[String]]) -> [String] {
      lines[0].indices.map { column in
        joiningWrapped(lines.map { $0[column] }.filter { !$0.isEmpty })
      }
    }
    /// A line a row, but for the lines that go on with a wrapped cell.
    func rows(_ lines: [[String]]) -> [[String]] {
      lines.reduce(into: [[[String]]]()) { rows, line in
        if rows.isEmpty || line.first?.isEmpty == false {
          rows.append([line])
        } else {
          rows[rows.count - 1].append(line)
        }
      }
      .map(joined)
    }
    let headerCount =
      stretches.dropLast().firstIndex(where: \.closedByDouble).map { $0 + 1 } ?? 0
    let header: [[String]]
    let body: [[String]]
    if headerCount > 0 {
      header = stretches.prefix(headerCount).map { joined($0.lines) }
      let rest = stretches.dropFirst(headerCount)
      body = rest.count > 1 ? rest.map { joined($0.lines) } : rest.flatMap { rows($0.lines) }
    } else if stretches.count == 2 {
      header = [joined(stretches[0].lines)]
      body = rows(stretches[1].lines)
    } else {
      header = []
      body =
        stretches.count > 1
        ? stretches.map { joined($0.lines) } : stretches.flatMap { rows($0.lines) }
    }
    guard header.count + body.count >= 2, !body.isEmpty else { return nil }
    return BoxTable(header: header, rows: body)
  }

  /// A cell's lines as one, joined with a space; but where xml2rfc broke a word after
  /// its `-` or `/` (`Reference/` `Description`), with none. A `-` or `/` standing on
  /// its own, as in `0x00 -` `0x3F`, keeps its space.
  private static func joiningWrapped(_ pieces: [String]) -> String {
    pieces.reduce(into: "") { text, piece in
      let breaksWord =
        (text.last == "-" || text.last == "/")
        && text.dropLast().last.map { $0.isLetter || $0.isNumber } == true
        && piece.first.map { $0.isLetter || $0.isNumber } == true
      if !text.isEmpty, !breaksWord { text += " " }
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
