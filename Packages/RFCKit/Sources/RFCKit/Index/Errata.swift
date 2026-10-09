import Foundation

/// One erratum from the RFC Editor's feed (#387): an error reported in a published
/// RFC, which the RFC Editor records beside it, since the RFC itself never changes.
public struct Erratum: Sendable, Hashable, Identifiable {
  /// The RFC Editor's review of an erratum.
  public enum Status: Sendable, Hashable {
    case verified
    case heldForDocumentUpdate
    case reported
    case rejected
    /// One a later feed adds, as written.
    case other(String)

    init(_ written: String) {
      switch written {
      case "Verified": self = .verified
      case "Held for Document Update": self = .heldForDocumentUpdate
      case "Reported": self = .reported
      case "Rejected": self = .rejected
      default: self = .other(written)
      }
    }

    /// Whether the reader marks it: one the stream has accepted as an error, fixed
    /// now or in the next revision. One not yet reviewed, or rejected, is only
    /// counted (decision on #387).
    public var isMarked: Bool {
      self == .verified || self == .heldForDocumentUpdate
    }
  }

  public enum Kind: Sendable, Hashable {
    case technical
    case editorial
    /// One a later feed adds, as written.
    case other(String)

    init(_ written: String) {
      switch written {
      case "Technical": self = .technical
      case "Editorial": self = .editorial
      default: self = .other(written)
      }
    }
  }

  /// The RFC Editor's number for it, as its page is named.
  public let id: Int
  public let document: DocumentID
  public let status: Status
  public let type: Kind
  /// The section field as the reporter wrote it: `4.1`, `In Sections 7.8 and 7.9`,
  /// `Figure 1`, or empty.
  public let section: String
  /// The sections `section` names, in its order, each as `Section.place` names it:
  /// `4.1` or `A.2`, as a heading is numbered, or `appendix-1` for an appendix
  /// numbered like a section. Empty when it names none.
  public let sections: [String]
  public let original: String
  public let corrected: String
  public let notes: String
  /// The day it was reported, `2024-05-06`.
  public let submitted: String

  public init(
    id: Int, document: DocumentID, status: Status, type: Kind, section: String,
    original: String, corrected: String, notes: String, submitted: String
  ) {
    self.id = id
    self.document = document
    self.status = status
    self.type = type
    self.section = section
    self.sections = Self.sections(in: section, of: document)
    self.original = original
    self.corrected = corrected
    self.notes = notes
    self.submitted = submitted
  }

  /// The erratum's page on the RFC Editor's site.
  public var page: URL {
    RFCEditorEndpoints.base.appending(path: "errata/eid\(id)")
  }

  // MARK: - Sections

  /// The sections a section field names, never guessed: a number or an appendix that
  /// opens it, alone or as a list, `4.1`, `A.2`, `6.4.5.`, `2.1,1st para`, `3.2 and
  /// 3.4`; an anchor's spelling, `section-4.1`, `appendix-C`; and every one a
  /// `Section`, `Sections`, `Appendix` or `Appendices` names in prose, `In Sections
  /// 7.8, 7.9, and 8.4.1`. Anything else, `Figure 1`, `Abstract`, `GLOBAL`, names
  /// none, and so does a list of another RFC's than `document`, `Section 4 of RFC
  /// 5234`.
  public static func sections(in field: String, of document: DocumentID) -> [String] {
    let words = field.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let first = words.first else { return [] }
    var named: [String] = []
    func add(_ sections: [String]) {
      for section in sections where !named.contains(section) { named.append(section) }
    }
    if let anchored = anchorSpelling(first) {
      add([anchored])
    } else if words.count == 1, let letter = identifier(first), letter.count == 1 {
      // A field that is one letter is an appendix; a word of prose that is one
      // letter, "A typo", is not.
      add([letter])
    } else {
      add(
        list(in: words, from: 0, of: document, namesAppendix: false, accepting: opensField)
          .sections)
    }
    var index = 0
    while index < words.count {
      let keyword = words[index].lowercased()
      guard keywords.contains(keyword) else {
        index += 1
        continue
      }
      let read = list(
        in: words, from: index + 1, of: document, namesAppendix: keyword.hasPrefix("appendi"),
        accepting: { _ in true })
      add(read.sections)
      index = read.end
    }
    return named
  }

  private static let keywords: Set<String> = ["section", "sections", "appendix", "appendices"]
  private static let conjunctions: Set<String> = ["and", "or", "&"]

  /// Whether an identifier can open a field as a section: a number, or an appendix
  /// with more than its letter, since a field opening with one letter is prose.
  private static func opensField(_ identifier: String) -> Bool {
    identifier.count > 1 || identifier.first?.isNumber == true
  }

  /// The sections the list starting at `words[start]` names, joined by commas, `and`,
  /// `or` and `&`, and the index of the word after it. A list followed by `of RFC
  /// 5234` or `of [RFC5234]` is that RFC's, and names none of `document`'s unless it
  /// is `document`.
  private static func list(
    in words: [String], from start: Int, of document: DocumentID, namesAppendix: Bool,
    accepting accepts: (String) -> Bool
  ) -> (sections: [String], end: Int) {
    var sections: [String] = []
    var index = start
    while index < words.count {
      let word = words[index]
      if conjunctions.contains(word.lowercased()) {
        index += 1
        continue
      }
      guard let identifier = identifier(word, upTo: identifierEnds), accepts(identifier)
      else { break }
      sections.append(namesAppendix ? appendix(identifier) : identifier)
      index += 1
      // A list goes on after a comma or a conjunction, and ends at anything else.
      let goesOn =
        word.hasSuffix(",")
        || (index < words.count && conjunctions.contains(words[index].lowercased()))
      if !goesOn { break }
    }
    return (namesRFC(in: words, at: index, otherThan: document) ? [] : sections, index)
  }

  /// Whether `words[index]` opens `of RFC 5234` or `of [RFC5234]` naming an RFC other
  /// than `document`.
  private static func namesRFC(
    in words: [String], at index: Int, otherThan document: DocumentID
  ) -> Bool {
    guard index + 1 < words.count, words[index].lowercased() == "of" else { return false }
    let cited = words[(index + 1)...].prefix(2).joined(separator: " ")
      .trimmingCharacters(in: ["[", "("])
    guard cited.lowercased().hasPrefix("rfc") else { return false }
    let number = cited.dropFirst(3).drop(while: \.isWhitespace).prefix(while: \.isASCIIDigit)
    return Int(number) != document.number
  }

  /// What ends a section's number within a word: `2.1,1st para`, `4.1)`.
  private static let identifierEnds: Set<Character> = [",", ";", ":", ")"]

  /// An appendix's place: `A.2` as it is, `1.2` as `appendix-1.2`, so it is never
  /// taken for the body's section 1.2 (#429).
  private static func appendix(_ identifier: String) -> String {
    identifier.first?.isNumber == true ? "appendix-\(identifier)" : identifier
  }

  /// A section named as its anchor is spelled, `section-4.1` or `appendix-C`, read
  /// as `SectionAnchor` reads an anchor.
  private static func anchorSpelling(_ word: String) -> String? {
    var anchor = Substring(word)
    if let end = anchor.firstIndex(where: identifierEnds.contains) { anchor = anchor[..<end] }
    while anchor.last == "." { anchor = anchor.dropLast() }
    return SectionAnchor.sectionNumber(fromAnchor: String(anchor))
  }

  /// `word` read as a section's number, `4.1` or `A.2`, without a trailing full stop
  /// or anything from the first of `ends` on; nil when it is none.
  private static func identifier(_ word: String, upTo ends: Set<Character> = []) -> String? {
    var text = Substring(word)
    if let end = text.firstIndex(where: ends.contains) { text = text[..<end] }
    while text.last == "." { text = text.dropLast() }
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard let head = parts.first, !head.isEmpty else { return nil }
    let headIsNumber = head.allSatisfy(\.isASCIIDigit)
    let headIsAppendix =
      head.count == 1 && head.first?.isUppercase == true
      && head.first?.isASCII == true
    guard headIsNumber || headIsAppendix,
      parts.dropFirst().allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) })
    else { return nil }
    return String(text)
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}

/// The RFC Editor's errata feed, `errata.json`, read into each document's errata.
public struct Errata: Sendable {
  private let byDocument: [DocumentID: [Erratum]]

  public init(_ errata: [Erratum]) {
    byDocument = Dictionary(grouping: errata, by: \.document).mapValues { errata in
      errata.sorted { ($0.submitted, $0.id) < ($1.submitted, $1.id) }
    }
  }

  /// The document's errata, in the order they were submitted.
  public subscript(document: DocumentID) -> [Erratum] {
    byDocument[document] ?? []
  }

  /// The feed as the RFC Editor serves it: a list of entries. An entry whose
  /// document or number can't be read, or that isn't shaped as one, is skipped
  /// rather than failing the feed.
  /// A feed none of whose entries can be read has changed its shape, and fails,
  /// rather than reading as one without errata.
  public static func decode(_ data: Data) throws -> Errata {
    let entries = try JSONDecoder().decode([SkippingMalformed].self, from: data)
    let errata = entries.compactMap { $0.entry?.erratum }
    if errata.isEmpty, !entries.isEmpty { throw DecodingError.unreadableEntries(entries.count) }
    return Errata(errata)
  }

  public enum DecodingError: Error, Equatable {
    /// Not one of this many entries could be read as an erratum.
    case unreadableEntries(Int)
  }
}

/// An entry of the feed, or nil for one that doesn't decode as one.
private struct SkippingMalformed: Decodable {
  let entry: ErrataFeedEntry?

  init(from decoder: any Decoder) throws {
    entry = try? ErrataFeedEntry(from: decoder)
  }
}

/// One entry, as the feed writes it. Every field may be missing or null.
private struct ErrataFeedEntry: Decodable {
  let id: String?
  let document: String?
  let status: String?
  let type: String?
  let section: String?
  let original: String?
  let corrected: String?
  let notes: String?
  let submitted: String?

  enum CodingKeys: String, CodingKey {
    case id = "errata_id"
    case document = "doc-id"
    case status = "errata_status_code"
    case type = "errata_type_code"
    case section
    case original = "orig_text"
    case corrected = "correct_text"
    case notes
    case submitted = "submit_date"
  }

  var erratum: Erratum? {
    guard let id = id.flatMap(Int.init),
      let document = document.flatMap(DocumentID.init(label:)), document.series == .rfc
    else { return nil }
    return Erratum(
      id: id, document: document, status: .init(status ?? ""), type: .init(type ?? ""),
      section: section?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      original: original ?? "", corrected: corrected ?? "", notes: notes ?? "",
      submitted: submitted ?? "")
  }
}
