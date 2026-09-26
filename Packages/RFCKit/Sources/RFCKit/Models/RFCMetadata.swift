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
}

/// The publication stream an RFC came through.
public enum Stream: String, Sendable, Codable, CaseIterable, Hashable {
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
  public var name: String
  /// Role such as `Editor`, when present.
  public var role: String?
  /// What the document itself publishes about the author beyond the name: RFCXML's
  /// `<organization>` and `<address>`. Nil when it publishes nothing, which is
  /// every author the RFC index or a legacy header names. Nothing here is looked
  /// up or inferred (#19).
  public var contact: AuthorContact?

  public init(name: String, role: String? = nil, contact: AuthorContact? = nil) {
    self.name = name
    self.role = role
    self.contact = contact
  }
}

/// An author's affiliation and address, as RFCXML's `<author>` states them.
public struct AuthorContact: Hashable, Sendable, Codable {
  public var organization: String?
  public var postal: PostalAddress?
  public var phone: String?
  public var facsimile: String?
  /// In the document's order; the schema allows several.
  public var emails: [String]
  public var uri: URL?

  public init(
    organization: String? = nil, postal: PostalAddress? = nil, phone: String? = nil,
    facsimile: String? = nil, emails: [String] = [], uri: URL? = nil
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

/// A postal address as RFCXML's `<postal>` gives it: either structured, as the
/// fields a contact card has, or as the author's own lines (`<postalLine>`), which
/// have no structure to recover and are kept as written in `street`.
public struct PostalAddress: Hashable, Sendable, Codable {
  /// `<street>`, `<extaddr>` and `<pobox>` lines in order, or every `<postalLine>`.
  public var street: [String]
  public var city: String?
  public var region: String?
  public var code: String?
  public var country: String?

  public init(
    street: [String] = [], city: String? = nil, region: String? = nil, code: String? = nil,
    country: String? = nil
  ) {
    self.street = street
    self.city = city
    self.region = region
    self.code = code
    self.country = country
  }

  /// The address as lines, the way the RFC Editor's plain-text rendering sets it:
  /// the street lines, then city, region and code on one line, then the country.
  public var lines: [String] {
    let locality = [city, region, code].compactMap { $0 }.joined(separator: " ")
    return street + [locality, country ?? ""].filter { !$0.isEmpty }
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
  public var stream: Stream
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
    stream: Stream = .legacy,
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
  public var rfcs: [RFCMetadata]
  public var series: [SeriesEntry]
  /// RFC numbers that were allocated but never issued.
  public var notIssued: [Int]

  private var byNumber: [Int: Int]

  public init(rfcs: [RFCMetadata], series: [SeriesEntry] = [], notIssued: [Int] = []) {
    self.rfcs = rfcs.sorted { $0.number < $1.number }
    self.series = series
    self.notIssued = notIssued
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

  /// Highest RFC number in the index.
  public var latestNumber: Int? { rfcs.last?.number }

  /// RFCs that reference the given one via obsoletes/updates; useful for a lineage view.
  public func documentsAffecting(_ number: Int) -> [RFCMetadata] {
    let target = DocumentID.rfc(number)
    return rfcs.filter { $0.obsoletes.contains(target) || $0.updates.contains(target) }
  }
}
