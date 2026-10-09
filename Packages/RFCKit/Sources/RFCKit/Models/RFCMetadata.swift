import Foundation

/// Maturity level of an RFC, as tracked by the RFC Editor.
public enum PublicationStatus: String, Sendable, Codable, CaseIterable, Hashable {
  case internetStandard = "INTERNET STANDARD"
  case draftStandard = "DRAFT STANDARD"
  case proposedStandard = "PROPOSED STANDARD"
  case bestCurrentPractice = "BEST CURRENT PRACTICE"
  case informational = "INFORMATIONAL"
  case experimental = "EXPERIMENTAL"
  case historic = "HISTORIC"
  case unknown = "UNKNOWN"

  public var isStandardsTrack: Bool {
    switch self {
    case .internetStandard, .draftStandard, .proposedStandard: true
    default: false
    }
  }

  public var displayName: String {
    switch self {
    case .internetStandard: "Internet Standard"
    case .draftStandard: "Draft Standard"
    case .proposedStandard: "Proposed Standard"
    case .bestCurrentPractice: "Best Current Practice"
    case .informational: "Informational"
    case .experimental: "Experimental"
    case .historic: "Historic"
    case .unknown: "Unknown"
    }
  }

  /// Short enough for a list row's badge, and a word: "STD" is the series' name
  /// rather than a status, and "Info" was a clipped word. BCP stays, being what the
  /// IETF itself calls them.
  public var shortName: String {
    switch self {
    case .internetStandard: "Standard"
    case .draftStandard: "Draft Standard"
    case .proposedStandard: "Proposed"
    case .bestCurrentPractice: "BCP"
    case .informational: "Informational"
    case .experimental: "Experimental"
    case .historic: "Historic"
    case .unknown: "Unknown"
    }
  }
}

/// The publication stream an RFC came through.
public enum PublicationStream: String, Sendable, Codable, CaseIterable, Hashable {
  case ietf = "IETF"
  case irtf = "IRTF"
  case iab = "IAB"
  case independent = "INDEPENDENT"
  case editorial = "Editorial"
  case legacy = "Legacy"

  public var displayName: String {
    switch self {
    case .ietf: "IETF"
    case .irtf: "IRTF"
    case .iab: "IAB"
    case .independent: "Independent Submission"
    case .editorial: "Editorial"
    case .legacy: "Legacy"
    }
  }
}

/// File formats the RFC Editor publishes for a given RFC.
public enum FileFormat: String, Sendable, Codable, CaseIterable, Hashable {
  case text = "TXT"
  case html = "HTML"
  case xml = "XML"
  case pdf = "PDF"
  case postScript = "PS"

  /// File extension used on rfc-editor.org.
  public var pathExtension: String {
    switch self {
    case .text: "txt"
    case .html: "html"
    case .xml: "xml"
    case .pdf: "pdf"
    case .postScript: "ps"
    }
  }
}

public struct Author: Hashable, Sendable, Codable {
  /// The one role a source states: RFCXML's `role` allows only `editor`, and the
  /// index and a legacy header state nothing else.
  public enum Role: String, Hashable, Sendable, Codable {
    case editor

    /// Reads a role however a source spells it: the index and RFCXML write
    /// "editor", and a legacy header "Editor", "Ed." or "Ed". Nil for any other.
    public init?(parsing text: String) {
      guard text.lowercased().hasPrefix("ed") else { return nil }
      self = .editor
    }
  }

  public var name: String
  public var role: Role?
  /// What the document itself publishes about the author beyond the name: RFCXML's
  /// `<organization>` and `<address>`. Nil when it publishes nothing, which is
  /// every author the RFC index or a legacy header names. Nothing here is looked
  /// up or inferred (#19).
  public var contact: AuthorContact?

  public init(name: String, role: Role? = nil, contact: AuthorContact? = nil) {
    self.name = name
    self.role = role
    self.contact = contact
  }

  public var isEditor: Bool {
    role == .editor
  }

  /// The name as the reader shows it, an editor's marked as one: "R. Fielding, Ed."
  public var displayName: String {
    isEditor ? "\(name), Ed." : name
  }

  /// The name past its given names, which is what a citation inverts, a page footer
  /// names and the `author:` filter matches: "R. Fielding" is "Fielding", "F. Le
  /// Faucheur" is "Le Faucheur", "D. Eastlake 3rd" is "Eastlake 3rd". A name with no
  /// initials before its last word, one word or an organization's ("Internet
  /// Architecture Board"), is all surname.
  public var surname: String {
    Self.split(name).surname.joined(separator: " ")
  }

  /// The initials before the surname, "R." or "J.K. L.": empty when the name is all
  /// surname.
  public var givenNames: String {
    Self.split(name).given.joined(separator: " ")
  }

  /// The leading words that are initials, "J.K." or "SN", are the given names; the
  /// rest is the surname, "Le Faucheur" or "St. Johns". The last word is always
  /// surname.
  static func split(_ name: String) -> (given: [Substring], surname: [Substring]) {
    let words = name.split(separator: " ")
    let given = words.dropLast().prefix(while: isInitials)
    return (Array(given), Array(words.dropFirst(given.count)))
  }

  /// Initials are capitals, and either carry a dot ("R.", "J.K.", "L-E.", "JP.") or
  /// are at most two letters without one ("SN"). "St." has a small letter, and
  /// "RFC" or "IAB" is three capitals without a dot, so both are surname.
  static func isInitials(_ word: Substring) -> Bool {
    let letters = word.filter(\.isLetter)
    guard !letters.isEmpty, letters.allSatisfy(\.isUppercase) else { return false }
    return word.contains(".") || letters.count <= 2
  }
}

/// An author's affiliation and address, as RFCXML's `<author>` states them.
///
/// The `ascii` attributes RFCXML allows beside these (and `asciiFullname` beside the
/// name) are not kept. They transliterate what the document already gives in its
/// own script, for renderings limited to ASCII, and the reader shows the document's
/// own; the schema makes them optional, so a round trip without them still validates.
public struct AuthorContact: Hashable, Sendable, Codable {
  public var organization: String?
  public var postal: PostalAddress?
  public var phone: String?
  public var facsimile: String?
  /// In the document's order; the schema allows several.
  public var emails: [String]
  /// As written, not as a `URL`: one that `URL(string:)` refuses is still the
  /// author's, and is shown and written back as text rather than lost.
  public var uri: String?

  public init(
    organization: String? = nil, postal: PostalAddress? = nil, phone: String? = nil,
    facsimile: String? = nil, emails: [String] = [], uri: String? = nil
  ) {
    self.organization = organization
    self.postal = postal
    self.phone = phone
    self.facsimile = facsimile
    self.emails = emails
    self.uri = uri
  }

  /// Whether there is anything to show.
  public var isEmpty: Bool {
    organization == nil && postal == nil && phone == nil && facsimile == nil && emails.isEmpty
      && uri == nil
  }
}

/// A postal address as RFCXML's `<postal>` gives it. The schema offers a choice:
/// the fields a contact card has, one per element, or the author's own lines
/// (`<postalLine>`), which have no structure to recover. Whichever the author chose
/// is kept, so the other is empty, and a round trip writes the same form back.
public struct PostalAddress: Hashable, Sendable, Codable {
  /// `<street>`, in order.
  public var street: [String]
  /// `<extaddr>`: a building, a floor or a suite, in order.
  public var extendedAddress: [String]
  /// `<pobox>`.
  public var postOfficeBox: String?
  /// `<cityarea>`: a district within the city.
  public var cityArea: String?
  public var city: String?
  public var region: String?
  /// `<code>`, the postal code.
  public var code: String?
  /// `<sortingcode>`, which some countries use beside the postal code.
  public var sortingCode: String?
  public var country: String?
  /// Every `<postalLine>`, when the author wrote the address as lines.
  public var postalLines: [String]

  public init(
    street: [String] = [], extendedAddress: [String] = [], postOfficeBox: String? = nil,
    cityArea: String? = nil, city: String? = nil, region: String? = nil, code: String? = nil,
    sortingCode: String? = nil, country: String? = nil, postalLines: [String] = []
  ) {
    self.street = street
    self.extendedAddress = extendedAddress
    self.postOfficeBox = postOfficeBox
    self.cityArea = cityArea
    self.city = city
    self.region = region
    self.code = code
    self.sortingCode = sortingCode
    self.country = country
    self.postalLines = postalLines
  }

  /// The address as lines: the author's own, or the fields in the order the RFC
  /// Editor's plain-text rendering commonly sets them: the building before the
  /// street (RFC 9283's "School of Computer Science", then "PB 92019"), the city,
  /// region and code on one line, the country last. That rendering follows each
  /// country's conventions beyond this; the reader does not try to.
  public var lines: [String] {
    guard postalLines.isEmpty else { return postalLines }
    let locality = [city, region, code].compactMap { $0 }.joined(separator: " ")
    let rest = [postOfficeBox, cityArea, locality, sortingCode, country].compactMap { $0 }
    return extendedAddress + street + rest.filter { !$0.isEmpty }
  }
}

public struct PublicationDate: Hashable, Sendable, Codable, Comparable {
  public var year: Int
  public var month: Int?
  public var day: Int?

  public init(year: Int, month: Int? = nil, day: Int? = nil) {
    self.year = year
    self.month = month
    self.day = day
  }

  public static func < (lhs: PublicationDate, rhs: PublicationDate) -> Bool {
    (lhs.year, lhs.month ?? 0, lhs.day ?? 0) < (rhs.year, rhs.month ?? 0, rhs.day ?? 0)
  }

  private static let monthNames = [
    "january", "february", "march", "april", "may", "june",
    "july", "august", "september", "october", "november", "december",
  ]

  /// Maps `May`, `Sept`, `09` and friends to a month number.
  public static func month(from text: String) -> Int? {
    let lowered = text.trimmingCharacters(in: .whitespaces).lowercased()
    if let numeric = Int(lowered), (1...12).contains(numeric) { return numeric }
    guard lowered.count >= 3 else { return nil }
    return monthNames.firstIndex { $0.hasPrefix(lowered) || lowered.hasPrefix($0) }.map { $0 + 1 }
  }

  public var monthName: String? {
    guard let month, (1...12).contains(month) else { return nil }
    return Self.monthNames[month - 1].capitalized
  }

  /// `June 2022` or `2022` when the month is unknown.
  public var formatted: String {
    if let monthName { return "\(monthName) \(year)" }
    return String(year)
  }
}

/// Everything the RFC Editor's index knows about one RFC.
public struct RFCMetadata: Hashable, Sendable, Codable, Identifiable {
  public var id: DocumentID
  public var title: String
  public var authors: [Author]
  public var date: PublicationDate
  public var formats: [FileFormat]
  public var pageCount: Int?
  public var keywords: [String]
  public var abstract: String?
  /// The Internet-Draft this RFC was published from, e.g. `draft-ietf-httpbis-semantics-19`.
  public var draft: String?
  /// Series documents this RFC is part of (BCP, STD, FYI).
  public var isAlso: [DocumentID]
  public var obsoletes: [DocumentID]
  public var obsoletedBy: [DocumentID]
  public var updates: [DocumentID]
  public var updatedBy: [DocumentID]
  public var currentStatus: PublicationStatus
  public var publicationStatus: PublicationStatus
  public var stream: PublicationStream
  public var area: String?
  public var workingGroup: String?
  public var errataURL: URL?
  public var doi: String?

  public init(
    id: DocumentID,
    title: String,
    authors: [Author] = [],
    date: PublicationDate,
    formats: [FileFormat] = [],
    pageCount: Int? = nil,
    keywords: [String] = [],
    abstract: String? = nil,
    draft: String? = nil,
    isAlso: [DocumentID] = [],
    obsoletes: [DocumentID] = [],
    obsoletedBy: [DocumentID] = [],
    updates: [DocumentID] = [],
    updatedBy: [DocumentID] = [],
    currentStatus: PublicationStatus = .unknown,
    publicationStatus: PublicationStatus = .unknown,
    stream: PublicationStream = .legacy,
    area: String? = nil,
    workingGroup: String? = nil,
    errataURL: URL? = nil,
    doi: String? = nil
  ) {
    self.id = id
    self.title = title
    self.authors = authors
    self.date = date
    self.formats = formats
    self.pageCount = pageCount
    self.keywords = keywords
    self.abstract = abstract
    self.draft = draft
    self.isAlso = isAlso
    self.obsoletes = obsoletes
    self.obsoletedBy = obsoletedBy
    self.updates = updates
    self.updatedBy = updatedBy
    self.currentStatus = currentStatus
    self.publicationStatus = publicationStatus
    self.stream = stream
    self.area = area
    self.workingGroup = workingGroup
    self.errataURL = errataURL
    self.doi = doi
  }

  public var number: Int { id.number }
  public var isObsolete: Bool { !obsoletedBy.isEmpty }
  public var hasErrata: Bool { errataURL != nil }
  /// True when the semantic RFCXML v3 source is available (RFCs from roughly 8650 onward).
  public var hasXMLSource: Bool { formats.contains(.xml) }
}

/// A BCP, STD or FYI series entry grouping one or more RFCs.
public struct SeriesEntry: Hashable, Sendable, Codable, Identifiable {
  public var id: DocumentID
  public var members: [DocumentID]

  public init(id: DocumentID, members: [DocumentID]) {
    self.id = id
    self.members = members
  }
}

/// The parsed RFC Editor index: every RFC plus the series groupings.
public struct RFCIndex: Sendable {
  public let rfcs: [RFCMetadata]
  public let series: [SeriesEntry]

  private let byNumber: [Int: Int]

  public init(rfcs: [RFCMetadata], series: [SeriesEntry] = []) {
    self.rfcs = rfcs.sorted { $0.number < $1.number }
    self.series = series
    var lookup: [Int: Int] = [:]
    lookup.reserveCapacity(rfcs.count)
    for (offset, rfc) in self.rfcs.enumerated() {
      lookup[rfc.number] = offset
    }
    self.byNumber = lookup
  }

  public subscript(number: Int) -> RFCMetadata? {
    guard let offset = byNumber[number] else { return nil }
    return rfcs[offset]
  }

  public subscript(id: DocumentID) -> RFCMetadata? {
    guard id.series == .rfc else { return nil }
    return self[id.number]
  }

  public func series(_ id: DocumentID) -> SeriesEntry? {
    series.first { $0.id == id }
  }
}

/// Coded as what the RFC Editor's index says, and nothing derived from it: the
/// lookup by number is rebuilt on decoding. The app keeps a snapshot of the index
/// in this form, because decoding it is about a third of the time the XML parse
/// takes, and the parse ran at every launch.
extension RFCIndex: Codable {
  private enum CodingKeys: String, CodingKey {
    case rfcs, series
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      rfcs: try container.decode([RFCMetadata].self, forKey: .rfcs),
      series: try container.decode([SeriesEntry].self, forKey: .series)
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(rfcs, forKey: .rfcs)
    try container.encode(series, forKey: .series)
  }
}
