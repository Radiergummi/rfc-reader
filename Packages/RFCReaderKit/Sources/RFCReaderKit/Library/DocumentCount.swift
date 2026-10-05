import Foundation

/// How many documents a list holds, as the subtitle under the list's title says it.
public enum DocumentCount {
  /// "1 Document", "9,842 Documents": in the locale's words, and grouped the way it
  /// groups digits. One key for every count; the catalog says "Document" for one.
  public static func label(_ count: Int, locale: Locale = .interface) -> String {
    String(kit: "\(count) Documents", locale: locale)
  }
}
