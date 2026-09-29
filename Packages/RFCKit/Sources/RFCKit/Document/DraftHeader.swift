import Foundation

/// What an Internet-Draft says it will do to published RFCs, read from its header:
/// the `obsoletes` and `updates` attributes of its XML root, or the `Obsoletes:` and
/// `Updates:` lines of its text front page. Datatracker records neither relation
/// until the draft is published, so the revisions scanner reads them here
/// (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md).
public struct DraftHeader: Equatable, Sendable {
  public var obsoletes: [Int]
  public var updates: [Int]
  /// Attributes or lines that were there but named no RFC number, such as
  /// `obsoletes="RFC6265"`. Worth logging: the entry is lost.
  public var unreadable: [String]

  public init(obsoletes: [Int] = [], updates: [Int] = [], unreadable: [String] = []) {
    self.obsoletes = obsoletes
    self.updates = updates
    self.unreadable = unreadable
  }

  public static func parse(xml data: Data) throws(XMLSyntaxError) -> DraftHeader {
    let attributes = try XMLDriver.rootAttributes(of: data)
    var unreadable: [String] = []
    let obsoletes = numbers(
      in: attributes["obsoletes"], reading: listedNumbers, unreadable: &unreadable)
    let updates = numbers(
      in: attributes["updates"], reading: listedNumbers, unreadable: &unreadable)
    return DraftHeader(obsoletes: obsoletes, updates: updates, unreadable: unreadable)
  }

  public static func parse(text data: Data) -> DraftHeader {
    // Split on `Character.isNewline`, where "\r\n" is one character: `.newlines` would
    // see a line and a blank one, and end the header block after its first line.
    parse(
      frontPage: String(decoding: data, as: UTF8.self)
        .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init))
  }

  /// The header block is the lines from the first that is not blank to the next blank
  /// one. Its left column, up to the first run of two spaces, carries the labels; a
  /// list that runs on continues on the next line, indented, starting with a number.
  static func parse(frontPage lines: [String]) -> DraftHeader {
    enum Label {
      case obsoletes
      case updates
    }

    let block = lines.drop(while: \.isBlank).prefix(while: { !$0.isBlank })
    var obsoletes: [Int] = []
    var updates: [Int] = []
    var unreadable: [String] = []
    var label: Label?
    var collected = ""

    func flush() {
      let found = numbers(in: collected, reading: listedNumbers, unreadable: &unreadable)
      switch label {
      case .obsoletes: obsoletes += found
      case .updates: updates += found
      case nil: break
      }
      label = nil
      collected = ""
    }

    for line in block {
      let left = leftColumn(line)
      if let rest = value(of: "Obsoletes:", in: left) {
        flush()
        label = .obsoletes
        collected = rest
      } else if let rest = value(of: "Updates:", in: left) {
        flush()
        label = .updates
        collected = rest
      } else if label != nil, line.first?.isWhitespace == true,
        left.first?.isNumber == true || left.uppercased().hasPrefix("RFC")
      {
        collected += " " + left
      } else {
        flush()
      }
    }
    flush()
    return DraftHeader(obsoletes: obsoletes, updates: updates, unreadable: unreadable)
  }

  /// The numbers in `value`, read by `read`. A value that is there and not blank but
  /// yields none goes to `unreadable`.
  private static func numbers(
    in value: String?, reading read: (String) -> [Int], unreadable: inout [String]
  ) -> [Int] {
    guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
    let numbers = read(value)
    if numbers.isEmpty { unreadable.append(value) }
    return numbers
  }

  /// "9990, RFC 9991, rfc9992, [9993] (if approved)": the numbers, past an "RFC" or the
  /// brackets around any. One
  /// reading for the XML attribute and the text line alike: drafts write the prefix in
  /// both, where a published RFC's own header never does.
  private static func listedNumbers(_ value: String) -> [Int] {
    value.replacingOccurrences(of: "(if approved)", with: "", options: .caseInsensitive)
      .split(whereSeparator: { $0 == "," || $0.isWhitespace })
      .compactMap { token -> Int? in
        // "[6265]" as a citation would write it.
        var token = token.trimmingPrefix("[")
        if token.hasSuffix("]") { token = token.dropLast() }
        if token.uppercased().hasPrefix("RFC") { token = token.dropFirst(3) }
        return Int(token)
      }
  }

  /// The line's text up to its first run of two spaces, past its indent: the author
  /// column on the right never reaches it.
  private static func leftColumn(_ line: String) -> String {
    let trimmed = line.drop(while: \.isWhitespace)
    guard let gap = trimmed.range(of: "  ") else {
      return String(trimmed).trimmingCharacters(in: .whitespaces)
    }
    return String(trimmed[..<gap.lowerBound])
  }

  private static func value(of label: String, in left: String) -> String? {
    guard left.hasPrefix(label) else { return nil }
    return String(left.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
  }
}
