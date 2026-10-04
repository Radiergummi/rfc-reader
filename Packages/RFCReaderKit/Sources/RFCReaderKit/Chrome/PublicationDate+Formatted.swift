import Foundation
import RFCKit

extension PublicationDate {
  /// "June 2022", or "2022" when the month is unknown, in `locale`'s language.
  /// RFCKit's `formatted` stays English, as RFCKit has no catalog.
  public func formatted(in locale: Locale = .interface) -> String {
    guard let month,
      let date = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: 1))
    else { return String(year) }
    return date.formatted(.dateTime.month(.wide).year().locale(locale))
  }
}
