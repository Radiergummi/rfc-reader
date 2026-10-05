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
