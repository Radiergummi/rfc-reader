import Foundation
import RFCKit

/// What the App Intents say back (#192), worded here so it is under test: the App
/// target has none.
public enum IntentAnswer {
  /// `There are 12 requirements in 4.2. Retries of RFC 9110.`
  ///
  /// - Parameter place: The section, `4.2. Retries of RFC 9110`, or the RFC.
  public static func requirements(
    _ count: Int, in place: String, locale: Locale = .interface
  ) -> String {
    // One key for every count: the catalog says "one requirement" for 1.
    count == 0
      ? String(kit: "There are no BCP 14 requirements in \(place).", locale: locale)
      : String(kit: "There are \(count) requirements in \(place).", locale: locale)
  }

  /// Where requirements are counted: `4.2. Retries of RFC 9110`, or `RFC 9110` when
  /// no section is asked for.
  public static func place(
    _ section: String?, of document: DocumentID, locale: Locale = .interface
  ) -> String {
    guard let section else { return document.displayName }
    return String(kit: "\(section) of \(document.displayName)", locale: locale)
  }

  /// `TLS alert 70, protocol_version, is defined in RFC 8446, Section 6.2.`
  ///
  /// - Parameters:
  ///   - heading: The registry and the value, `TLS alert 70`.
  ///   - name: What the registry calls it, nil where the value is its own name.
  ///   - definedIn: The citation of the defining section, nil where IANA names none.
  public static func definition(
    of heading: String, name: String?, definedIn: String?, locale: Locale = .interface
  ) -> String {
    let named = name.map { "\(heading), \($0)," } ?? heading
    guard let definedIn else {
      return String(
        kit: "\(named) is in IANA's registry, which names no RFC for it.", locale: locale)
    }
    return String(kit: "\(named) is defined in \(definedIn).", locale: locale)
  }

  /// `Black is now the dark theme.`: what Set Reader Theme says (#714), naming the
  /// slot, since a dark theme set while the app is light shows nothing yet.
  ///
  /// - Parameters:
  ///   - name: The theme, as Settings calls it.
  ///   - appearances: The slots it was set in: `ReaderPalette.appearances`.
  public static func theme(
    _ name: String, setFor appearances: Set<PaletteAppearance>, locale: Locale = .interface
  ) -> String {
    switch (appearances.contains(.light), appearances.contains(.dark)) {
    case (true, false): String(kit: "\(name) is now the light theme.", locale: locale)
    case (false, true): String(kit: "\(name) is now the dark theme.", locale: locale)
    default: String(kit: "\(name) is now the light and the dark theme.", locale: locale)
    }
  }

  /// `Sepia is not a dark theme.`: why Set Reader Theme set nothing, asked for a slot
  /// the theme is not made for.
  public static func theme(
    _ name: String, notOfferedFor slot: PaletteAppearance, locale: Locale = .interface
  ) -> String {
    switch slot {
    case .light: String(kit: "\(name) is not a light theme.", locale: locale)
    case .dark: String(kit: "\(name) is not a dark theme.", locale: locale)
    }
  }
}

/// Something asked of the reader showing one document, which that reader takes once
/// it can (#192): an App Intent's request to show a tab beside it, made before the
/// document has loaded, or before a tab has taken the link at all.
///
/// Not bound to `Sendable`: what is asked may be an app type, such as a tab, whose
/// conformances are the main actor's, and the request never leaves it.
public struct DocumentRequest<Value: Equatable>: Equatable {
  public let id: DocumentID
  public let value: Value

  public init(id: DocumentID, value: Value) {
    self.id = id
    self.value = value
  }

  /// What `request` asks of `id`'s reader, which is then no longer asked; nil, with
  /// `request` left as it is, when it asks nothing or asks another document's.
  public static func take(_ request: inout Self?, for id: DocumentID) -> Value? {
    guard let asked = request, asked.id == id else { return nil }
    request = nil
    return asked.value
  }
}

extension DocumentRequest: Sendable where Value: Sendable {}
