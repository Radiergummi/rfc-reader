import AppIntents
import RFCReaderKit

/// The appearance setting as Shortcuts offers it (#714), and where Settings takes
/// the names of its choices from, so each is written once. Nonisolated, as the
/// titles are, since an intent reads them off the main actor.
nonisolated enum AppearanceOption: String, AppEnum {
  case system
  case light
  case dark

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Appearance")

  static let caseDisplayRepresentations: [AppearanceOption: DisplayRepresentation] = [
    .system: "System",
    .light: "Light",
    .dark: "Dark",
  ]

  init(_ preference: AppearancePreference) {
    switch preference {
    case .system: self = .system
    case .light: self = .light
    case .dark: self = .dark
    }
  }

  var preference: AppearancePreference {
    switch self {
    case .system: .system
    case .light: .light
    case .dark: .dark
    }
  }
}

extension AppearancePreference {
  /// What Settings and Shortcuts call it.
  nonisolated var title: LocalizedStringResource {
    AppearanceOption.caseDisplayRepresentations[AppearanceOption(self)]?.title
      ?? .verbatim(rawValue)
  }
}

extension ReaderPalette {
  /// What Settings and Shortcuts call it.
  nonisolated var title: LocalizedStringResource {
    switch id {
    case ReaderPalette.paper.id: "Paper"
    case ReaderPalette.sepia.id: "Sepia"
    case ReaderPalette.gray.id: "Gray"
    case ReaderPalette.night.id: "Night"
    case ReaderPalette.black.id: "Black"
    case ReaderPalette.highContrast.id: "High Contrast"
    default: "Automatic"
    }
  }
}
