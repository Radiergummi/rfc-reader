import Foundation

extension String {
  /// `key` from RFCReaderKit's catalog, in `locale`'s language.
  ///
  /// The models resolve their words in a locale they are given rather than in the
  /// process's, so a test can pin English on a Mac whose first language is German,
  /// and resolve German on purpose (decision "The app's chrome is localized, the
  /// reader body is not").
  init(kit key: String.LocalizationValue, locale: Locale) {
    var resource = LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    resource.locale = locale
    self.init(localized: resource)
  }
}

extension Locale {
  /// The language the chrome is shown in: the one RFCReaderKit's catalog resolves to
  /// for this process. Not `Locale.current`, whose language can be one the app does
  /// not have: French first and German second gives German here, and English there.
  public static var interface: Locale {
    Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
  }
}
