import Foundation

/// The four-character codes of the AppleScript dictionary's enumerations, as Apple
/// events carry them (#762). The dictionary, `RFCReader.sdef`, declares them too, and
/// `ScriptCodeTests` holds the two to the same codes.
public enum ScriptCode {
  /// `code` as the 32-bit value an Apple event carries.
  public static func value(_ code: String) -> FourCharCode {
    code.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
  }
}

/// The dictionary's `placement`: where `open rfc` opens it.
public enum ScriptPlacement: CaseIterable, Sendable {
  case frontTab
  case newTab
  case newWindow

  /// Its enumerator's name in the dictionary.
  public var name: String {
    switch self {
    case .frontTab: "front tab"
    case .newTab: "new tab"
    case .newWindow: "new window"
    }
  }

  public var code: FourCharCode {
    switch self {
    case .frontTab: ScriptCode.value("RPfT")
    case .newTab: ScriptCode.value("RPnT")
    case .newWindow: ScriptCode.value("RPnW")
    }
  }

  /// The placement `code` names; nil for none, which a script means as the front tab.
  public init?(code: FourCharCode) {
    guard let placement = Self.allCases.first(where: { $0.code == code }) else { return nil }
    self = placement
  }
}

/// The dictionary's `inspector pane`: what a window's panel shows, its navigation's
/// three tabs and the information pane in one list.
public enum ScriptPane: CaseIterable, Sendable {
  case contents
  case references
  case requirements
  case annotations
  case information

  /// Its enumerator's name in the dictionary.
  public var name: String {
    switch self {
    case .contents: "contents"
    case .references: "references"
    case .requirements: "requirements"
    case .annotations: "annotations"
    case .information: "information"
    }
  }

  public var code: FourCharCode {
    switch self {
    case .contents: ScriptCode.value("RIpC")
    case .references: ScriptCode.value("RIpR")
    case .requirements: ScriptCode.value("RIpQ")
    case .annotations: ScriptCode.value("RIpA")
    case .information: ScriptCode.value("RIpI")
    }
  }

  /// The pane `code` names; nil for none.
  public init?(code: FourCharCode) {
    guard let pane = Self.allCases.first(where: { $0.code == code }) else { return nil }
    self = pane
  }

  /// The inspector pane it is shown in.
  public var pane: InspectorPane {
    self == .information ? .info : .navigation
  }
}

/// The dictionary's `export format`: what `export` saves an RFC as (#383). Named in
/// English whatever the interface's language, as everything a script names is.
extension ExportFormat {
  /// Its enumerator's name in the dictionary.
  public var scriptName: String {
    switch self {
    case .pdf: "PDF"
    case .epub: "EPUB"
    case .html: "HTML"
    case .markdown: "Markdown"
    case .text: "plain text"
    case .xml: "XML"
    case .abnf: "ABNF"
    case .annotations: "highlights and notes"
    }
  }

  public var scriptCode: FourCharCode {
    switch self {
    case .pdf: ScriptCode.value("REfP")
    case .epub: ScriptCode.value("REfE")
    case .html: ScriptCode.value("REfH")
    case .markdown: ScriptCode.value("REfM")
    case .text: ScriptCode.value("REfT")
    case .xml: ScriptCode.value("REfX")
    case .abnf: ScriptCode.value("REfA")
    case .annotations: ScriptCode.value("REfN")
    }
  }

  /// The format a script names, without regard to case; nil for none.
  public init?(scriptName: String) {
    let name = scriptName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let format = Self.allCases.first(where: {
        $0.scriptName.caseInsensitiveCompare(name) == .orderedSame
      })
    else { return nil }
    self = format
  }

  /// The format `code` names; nil for none.
  public init?(scriptCode code: FourCharCode) {
    guard let format = Self.allCases.first(where: { $0.scriptCode == code }) else { return nil }
    self = format
  }
}
