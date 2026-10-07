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
  /// The sections `section` names, in its order: `4.1` or `A.2`, as a heading is
  /// numbered. Empty when it names none, and the erratum is the whole document's.
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
    self.sections = Self.sections(in: section)
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
  /// opens it, `4.1`, `A.2`, `6.4.5.`, `2.1,1st para`; or every one a `Section`,
  /// `Sections`, `Appendix` or `Appendices` names in prose, `In Sections 7.8, 7.9,
  /// and 8.4.1`. Anything else, `Figure 1`, `Abstract`, `GLOBAL`, names none.
  public static func sections(in field: String) -> [String] {
    let words = field.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
      .map(String.init)
    let named = namedInProse(words)
    if !named.isEmpty { return named }
    guard let first = words.first else { return [] }
    // A field that is one letter is an appendix; a word of prose that is one letter,
    // "A typo", is not.
    if words.count == 1, let letter = identifier(first), letter.count == 1 { return [letter] }
    guard let opening = identifier(first, upTo: [",", ";", ":"]),
      opening.count > 1
        || opening.first?.isNumber == true
    else { return [] }
    return [opening]
  }

  /// Every section a `Section`, `Sections`, `Appendix` or `Appendices` names, with
  /// the identifiers after it joined by commas, `and`, `or` and `&`.
  private static func namedInProse(_ words: [String]) -> [String] {
    let keywords: Set<String> = ["section", "sections", "appendix", "appendices"]
    let conjunctions: Set<String> = ["and", "or", "&"]
    var named: [String] = []
    var index = 0
    while index < words.count {
      guard keywords.contains(words[index].lowercased()) else {
        index += 1
        continue
      }
      index += 1
      while index < words.count {
        let word = words[index]
        if conjunctions.contains(word.lowercased()) {
          index += 1
          continue
        }
        guard let section = identifier(word, upTo: [",", ";", ":", ")"]) else { break }
        if !named.contains(section) { named.append(section) }
        index += 1
        // A list goes on after a comma or a conjunction, and ends at anything else.
        let goesOn =
          word.hasSuffix(",")
          || (index < words.count && conjunctions.contains(words[index].lowercased()))
        if !goesOn { break }
      }
    }
    return named
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

  /// How many errata there are, of every document.
  public var count: Int {
    byDocument.values.reduce(0) { $0 + $1.count }
  }

  /// The feed as the RFC Editor serves it: a list of entries. An entry whose
  /// document or number can't be read is skipped rather than failing the feed.
  public static func decode(_ data: Data) throws -> Errata {
    let entries = try JSONDecoder().decode([ErrataFeedEntry].self, from: data)
    return Errata(entries.compactMap(\.erratum))
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
