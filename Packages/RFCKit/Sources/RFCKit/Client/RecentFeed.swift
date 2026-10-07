import Foundation

/// One entry of the "Recent RFCs" RSS feed.
public struct RecentRFC: Sendable, Hashable, Identifiable {
  public var id: DocumentID
  public var title: String
  public var summary: String
  public var link: URL?
  public var publishedAt: Date?

  public init(
    id: DocumentID, title: String, summary: String, link: URL? = nil, publishedAt: Date? = nil
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.link = link
    self.publishedAt = publishedAt
  }
}

public enum RecentFeedParser {
  public enum ParseError: Error, LocalizedError, Sendable, Equatable {
    /// Well-formed XML that is not RSS, such as a sign-in page served in the feed's
    /// place: an error, not a feed with nothing in it (#757).
    case notAFeed(rootElement: String)
    case malformed(XMLSyntaxError)

    /// The syntax error's own words, which the app shows (#320).
    public var errorDescription: String? {
      switch self {
      case .notAFeed(let root): "Not an RSS feed: the document's root element is <\(root)>."
      case .malformed(let error): error.errorDescription
      }
    }
  }

  private static let titlePattern = Pattern(#/^RFC\s*(?<number>\d+):\s*(?<title>.+)$/#)

  /// An RFC 822 date, `Sat, 19 Sep 2026 00:00:00 GMT`: a `Sendable` value made once,
  /// where a `DateFormatter` was built for every parse (#148). The time zone field is
  /// read, not assumed. Strict, as the `DateFormatter` was: a date that does not
  /// exist, `31 Sep`, is no date rather than the first of the next month.
  static let dateStrategy = Date.ParseStrategy(
    format: """
      \(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \
      \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\
      \(second: .twoDigits) \(timeZone: .specificName(.short))
      """,
    locale: Locale(identifier: "en_US_POSIX"),
    timeZone: .gmt,
    isLenient: false)

  public static func parse(_ data: Data) throws(ParseError) -> [RecentRFC] {
    let root: XMLTree.Element
    do {
      root = try XMLTree.parse(data)
    } catch {
      throw .malformed(error)
    }
    guard root.name == "rss" else { throw .notAFeed(rootElement: root.name) }
    var items: [RecentRFC] = []
    for item in root.first("channel")?.all("item") ?? [] {
      let rawTitle = item.first("title")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard let match = rawTitle.firstMatch(of: titlePattern), let number = Int(match.number) else {
        continue
      }
      items.append(
        RecentRFC(
          id: .rfc(number),
          title: String(match.title).trimmingCharacters(in: .whitespaces),
          summary: item.first("description")?.text.collapsingWhitespace() ?? "",
          link: (item.first("link")?.text.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap(URL.init(string:)),
          publishedAt: (item.first("pubDate")?.text.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { try? Date($0, strategy: dateStrategy) }
        ))
    }
    return items
  }
}
