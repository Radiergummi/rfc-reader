import RFCKit

/// What the App Intents say back (#192), worded here so it is under test: the App
/// target has none.
public enum IntentAnswer {
  /// `There are 12 requirements in 4.2. Retries of RFC 9110.`
  ///
  /// - Parameter place: The section, `4.2. Retries of RFC 9110`, or the RFC.
  public static func requirements(_ count: Int, in place: String) -> String {
    switch count {
    case 0: "There are no BCP 14 requirements in \(place)."
    case 1: "There is one requirement in \(place)."
    default: "There are \(count) requirements in \(place)."
    }
  }

  /// `TLS alert 70, protocol_version, is defined in RFC 8446, Section 6.2.`
  ///
  /// - Parameters:
  ///   - heading: The registry and the value, `TLS alert 70`.
  ///   - name: What the registry calls it, nil where the value is its own name.
  ///   - definedIn: The citation of the defining section, nil where IANA names none.
  public static func definition(of heading: String, name: String?, definedIn: String?) -> String {
    let named = name.map { "\(heading), \($0)," } ?? heading
    guard let definedIn else { return "\(named) is in IANA's registry, which names no RFC for it." }
    return "\(named) is defined in \(definedIn)."
  }
}

/// Something asked of the reader showing one document, which that reader takes once
/// it can (#192): an App Intent's request to show a tab beside it, made before the
/// document has loaded, or before a tab has taken the link at all.
public struct DocumentRequest<Value: Equatable & Sendable>: Equatable, Sendable {
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
