import Foundation
import RFCKit

extension PublicationDate {
  /// "June 2022", or "2022" when the month is unknown, in `locale`'s language.
  /// RFCKit's `formatted` stays English, as RFCKit has no catalog.
  ///
  /// Gregorian whatever the reader's calendar, as the index dates the RFC and as the
  /// year alone is written: a format style's calendar is the reader's, not `locale`'s,
  /// which would date it "June 2565 BE" under the Buddhist calendar, print too.
  public func formatted(in locale: Locale = .interface) -> String {
    let gregorian = Calendar(identifier: .gregorian)
    guard let month,
      let date = gregorian.date(from: DateComponents(year: year, month: month, day: 1))
    else { return String(year) }
    var style = Date.FormatStyle.dateTime.month(.wide).year().locale(locale)
    style.calendar = gregorian
    return date.formatted(style)
  }
}
