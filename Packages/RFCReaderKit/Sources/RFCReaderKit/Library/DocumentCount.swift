import Foundation

/// How many documents a list holds, as the subtitle under the list's title says it.
public enum DocumentCount {
  /// "1 Document", "9,842 Documents" — grouped the way the locale groups digits,
  /// which is why the locale is a parameter: the tests pin one, the app passes none.
  public static func label(_ count: Int, locale: Locale = .current) -> String {
    let number = count.formatted(.number.locale(locale))
    return count == 1 ? "\(number) Document" : "\(number) Documents"
  }
}
