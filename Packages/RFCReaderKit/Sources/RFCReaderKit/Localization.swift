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

extension LocalizedStringResource {
  /// Text that is data, for an API that only takes a resource, such as an App
  /// Intent's display representation: looked up in a table no catalog has, so a
  /// section titled "Acknowledgements" is never translated as the About window's.
  public static func verbatim(_ text: String) -> LocalizedStringResource {
    LocalizedStringResource(String.LocalizationValue(text), table: "Verbatim", bundle: .main)
  }
}

extension Locale {
  /// The language the chrome is shown in: the one RFCReaderKit's catalog resolves to
  /// for this process. Not `Locale.current`, whose language can be one the app does
  /// not have: French first and German second gives German here, and English there.
  /// The region stays the reader's, so dates and numbers are written as it writes
  /// them: English in Britain dates "17 September", not "September 17".
  public static var interface: Locale {
    interface(localization: catalogLocalization, current: .current)
  }

  /// The localization RFCReaderKit's catalog resolves to for this process, found
  /// once: the languages it chooses from change only with a relaunch.
  private static let catalogLocalization = Bundle.module.preferredLocalizations.first ?? "en"

  /// `current` itself when it is in the catalog's language, so a variant keeps its
  /// own ways and the reader's settings stay: British English lists "RFC 1, RFC 2
  /// and RFC 3". Otherwise the catalog's language, in `current`'s region.
  static func interface(localization: String, current: Locale) -> Locale {
    let language = Locale.Language(identifier: localization)
    if current.language.languageCode == language.languageCode,
      current.language.script == language.script
    {
      return current
    }
    var components = Locale.Components(identifier: localization)
    components.region = current.region
    return Locale(components: components)
  }

  /// English, for what must not change with the interface's language: the names a
  /// script reads and sets filters by, and what tests expect.
  public static let english = Locale(identifier: "en")
}
