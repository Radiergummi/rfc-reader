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
    let attributes = try XMLDriver.rootElement(of: data).attributes
    var unreadable: [String] = []
    let obsoletes = numbers(
      in: attributes["obsoletes"], reading: xmlNumbers, unreadable: &unreadable)
    let updates = numbers(in: attributes["updates"], reading: xmlNumbers, unreadable: &unreadable)
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

    let block = lines.drop(while: isBlank).prefix(while: { !isBlank($0) })
    var obsoletes: [Int] = []
    var updates: [Int] = []
    var unreadable: [String] = []
    var label: Label?
    var collected = ""

    func flush() {
      let found = numbers(in: collected, reading: textNumbers, unreadable: &unreadable)
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

  /// "2616, 7230", read as the RFC parser reads its own header.
  private static func xmlNumbers(_ value: String) -> [Int] {
    RFCXMLParser.parseDocumentList(value).map(\.number)
  }

  /// "9990, RFC 9991, RFC9992 (if approved)": the numbers, past an "RFC" before any.
  private static func textNumbers(_ value: String) -> [Int] {
    value.replacingOccurrences(of: "(if approved)", with: "", options: .caseInsensitive)
      .split(whereSeparator: { $0 == "," || $0.isWhitespace })
      .compactMap { token -> Int? in
        var token = Substring(token)
        if token.uppercased().hasPrefix("RFC") { token = token.dropFirst(3) }
        return Int(token)
      }
  }

  private static func isBlank(_ line: String) -> Bool {
    line.allSatisfy(\.isWhitespace)
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
