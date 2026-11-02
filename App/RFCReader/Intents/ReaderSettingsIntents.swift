import AppIntents
import RFCReaderKit

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

// The reader's appearance from Shortcuts (#714). Each intent writes through
// `ReaderSettings`, never to a user defaults key, so the open readers update as
// they do for a change made in Settings, and a Focus filter's settings stay over
// the reader's own. None opens the app.

/// A page theme, as Settings lists it: one of `ReaderPalette.all`.
struct ThemeEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Theme", numericFormat: "\(placeholder: .int) themes")
  }

  static var defaultQuery: ThemeQuery { ThemeQuery() }

  /// `ReaderPalette.id`.
  let id: String

  init(_ palette: ReaderPalette) {
    id = palette.id
  }

  var palette: ReaderPalette {
    ReaderPalette.all.first { $0.id == id } ?? .automatic
  }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: palette.title)
  }
}

/// Every theme Settings offers, in its order; `EnumerableEntityQuery` suggests them
/// from this.
struct ThemeQuery: EnumerableEntityQuery {
  func allEntities() async throws -> [ThemeEntity] {
    ReaderPalette.all.map(ThemeEntity.init)
  }

  /// Not derived from `allEntities()`, measured: the conformance fails without it.
  func entities(for identifiers: [ThemeEntity.ID]) async throws -> [ThemeEntity] {
    ReaderPalette.all.filter { identifiers.contains($0.id) }.map(ThemeEntity.init)
  }
}

/// Which of the two themes Set Reader Theme sets: the one for when the app is light,
/// or the one for when it is dark.
enum ThemeSlot: String, AppEnum {
  case light
  case dark

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Light or Dark")

  static let caseDisplayRepresentations: [ThemeSlot: DisplayRepresentation] = [
    .light: "Light",
    .dark: "Dark",
  ]

  var appearance: PaletteAppearance {
    switch self {
    case .light: .light
    case .dark: .dark
    }
  }
}

/// "Use the Black theme in RFC Reader": sets the light theme, the dark theme or
/// both, by the appearances the theme is made for, as Settings' pickers do, and
/// leaves the appearance alone. Asked for one slot, it sets that one alone, which is
/// how the two themes Get Reader Settings returns are set back.
struct SetReaderThemeIntent: AppIntent {
  static let title: LocalizedStringResource = "Set Reader Theme"
  static let description = IntentDescription(
    "Sets the page theme: a light theme for when the app is light, a dark theme for when it is dark, or one made for both. Choose Light or Dark to set only that one."
  )
  static let openAppWhenRun = false

  @Parameter(title: "Theme")
  var theme: ThemeEntity

  /// Empty for the slots the theme is made for.
  @Parameter(title: "For")
  var slot: ThemeSlot?

  static var parameterSummary: some ParameterSummary {
    Summary("Use the \(\.$theme) theme") {
      \.$slot
    }
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let palette = theme.palette
    let name = String(localized: palette.title)
    let asked = slot?.appearance
    if let asked, palette.slots(for: asked).isEmpty {
      throw IntentFailure.themeNotOffered(IntentAnswer.theme(name, notOfferedFor: asked))
    }
    ReaderSettings.change { $0.setTheme(palette, for: asked) }
    let answer = IntentAnswer.theme(name, setFor: palette.slots(for: asked))
    return .result(dialog: IntentDialog(.verbatim(answer)))
  }
}

/// "Switch RFC Reader to Dark": the whole app's appearance, as Settings sets it.
struct SetAppearanceIntent: AppIntent {
  static let title: LocalizedStringResource = "Set Appearance"
  static let description = IntentDescription(
    "Sets the app's appearance: the system's, or always light or dark.")
  static let openAppWhenRun = false

  @Parameter(title: "Appearance")
  var appearance: AppearanceOption

  static var parameterSummary: some ParameterSummary {
    Summary("Set the appearance to \(\.$appearance)")
  }

  func perform() async throws -> some IntentResult {
    let preference = appearance.preference
    ReaderSettings.change { $0.appearance = preference }
    return .result()
  }
}

/// How Set Text Size changes the size.
enum TextSizeChange: String, AppEnum {
  case size
  case bigger
  case smaller

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Change")

  static let caseDisplayRepresentations: [TextSizeChange: DisplayRepresentation] = [
    .size: "Size",
    .bigger: "Bigger",
    .smaller: "Smaller",
  ]
}

/// The reader's text size: a size in points, or a step bigger or smaller, as View ▸
/// Bigger and Smaller take, within the range Settings' slider has.
struct SetTextSizeIntent: AppIntent {
  static let title: LocalizedStringResource = "Set Text Size"
  static let description = IntentDescription(
    "Sets the reader's text size, in points from 12 to 28, or makes it a step bigger or smaller."
  )
  static let openAppWhenRun = false

  @Parameter(title: "Change", default: .bigger)
  var change: TextSizeChange

  /// Asked for only for a change to a size, and with no default: an App Shortcut's
  /// phrase is offered for each change, and "Make the text Size" must ask rather than
  /// set one. The range is `ReaderPreferences.fontSizes`: a parameter's is a constant.
  @Parameter(title: "Size", inclusiveRange: (12, 28))
  var size: Double?

  static var parameterSummary: some ParameterSummary {
    When(\.$change, .equalTo, .size) {
      Summary("Set the text \(\.$change) to \(\.$size)")
    } otherwise: {
      Summary("Make the text \(\.$change)")
    }
  }

  func perform() async throws -> some IntentResult & ReturnsValue<Double> {
    let change = change
    // Whole points, as the slider and Bigger and Smaller step.
    let size = size?.rounded()
    if change == .size, size == nil { throw $size.needsValueError() }
    ReaderSettings.change { settings in
      switch change {
      case .size: if let size { settings.fontSize = size }
      case .bigger: settings.fontSize = ReaderPreferences.fontSize(steppingUp: settings.fontSize)
      case .smaller:
        settings.fontSize = ReaderPreferences.fontSize(steppingDown: settings.fontSize)
      }
    }
    return .result(value: ReaderSettings(defaults: .standard).fontSize)
  }
}

/// The reader's appearance, themes and text size, as Get Reader Settings returns
/// them, so that a shortcut can hand each to the Set intents to restore it: the
/// light theme to Set Reader Theme for Light, the dark theme for Dark, since a theme
/// made for both would otherwise set both.
struct ReaderSettingsEntity: TransientAppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Reader Settings")
  }

  @Property(title: "Appearance")
  var appearance: AppearanceOption

  @Property(title: "Light Theme")
  var lightTheme: ThemeEntity

  @Property(title: "Dark Theme")
  var darkTheme: ThemeEntity

  @Property(title: "Text Size")
  var textSize: Double

  init() {}

  init(_ settings: ReaderSettings) {
    appearance = AppearanceOption(settings.appearance)
    lightTheme = ThemeEntity(settings.lightPalette)
    darkTheme = ThemeEntity(settings.darkPalette)
    textSize = settings.fontSize
  }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "Reader Settings",
      subtitle: .verbatim(
        [
          String(localized: appearance.preference.title),
          String(localized: lightTheme.palette.title),
          String(localized: darkTheme.palette.title),
          String(localized: "\(Int(textSize)) pt"),
        ]
        .formatted(.list(type: .and, width: .narrow))))
  }
}

/// What the reader draws now: under a Focus filter, the Focus's settings.
struct GetReaderSettingsIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Reader Settings"
  static let description = IntentDescription(
    "Gets the reader's appearance, light and dark themes and text size, as they are now.")
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult & ReturnsValue<ReaderSettingsEntity> {
    .result(value: ReaderSettingsEntity(ReaderSettings(defaults: .standard)))
  }
}

/// A Focus filter (#714): the theme, appearance and text size the reader takes while
/// a Focus is on, such as Black and larger text under Sleep. Each is optional, and
/// one left empty leaves that setting alone.
///
/// What it sets is a `FocusOverride` over the reader's own settings, never written
/// over them: when the Focus ends, the system performs it with every parameter
/// empty, which removes the override, and the reader's own are drawn again.
struct ReaderFocusFilter: SetFocusFilterIntent {
  static let title: LocalizedStringResource = "Reader Appearance"
  static let description: IntentDescription? = IntentDescription(
    "Sets the reader's theme, appearance and text size while the Focus is on.")

  @Parameter(title: "Theme")
  var theme: ThemeEntity?

  @Parameter(title: "Appearance")
  var appearance: AppearanceOption?

  @Parameter(title: "Text Size", inclusiveRange: (12, 28))
  var textSize: Double?

  var displayRepresentation: DisplayRepresentation {
    let parts = [
      theme.map { String(localized: $0.palette.title) },
      appearance.map { String(localized: $0.preference.title) },
      textSize.map { String(localized: "\(Int($0)) pt") },
    ]
    .compactMap { $0 }
    return DisplayRepresentation(
      title: "Reader Appearance",
      subtitle: parts.isEmpty ? nil : .verbatim(parts.formatted(.list(type: .and, width: .narrow))))
  }

  func perform() async throws -> some IntentResult {
    // Whole points, as the slider steps.
    var focus = FocusOverride(
      appearance: appearance?.preference, fontSize: textSize?.rounded())
    if let theme { focus.setTheme(theme.palette) }
    // An empty one removes the override: the Focus has ended.
    focus.write(to: .standard)
    return .result()
  }

  /// Clears an override the Focus has outlived: one left when the app was killed or
  /// reinstalled while a Focus was on, whose end it never heard. Only ever clears,
  /// never writes one: a Focus that is on performs the filter itself.
  static func clearIfEnded() async {
    guard let read = FocusOverride.stored(in: .standard),
      let current = try? await ReaderFocusFilter.current,
      current.theme == nil, current.appearance == nil, current.textSize == nil
    else { return }
    // Only what was read: a Focus that started during the wait, or a size the
    // reader stepped, is kept.
    FocusOverride.remove(from: .standard, ifStill: read)
  }

  /// Checks once now and again whenever the app becomes active, for as long as it
  /// runs: launch on the Mac, and every scene's activation on iOS.
  static func clearWhenEnded() {
    Task { await clearIfEnded() }
    #if os(macOS)
      let didBecomeActive = NSApplication.didBecomeActiveNotification
    #else
      let didBecomeActive = UIApplication.didBecomeActiveNotification
    #endif
    NotificationCenter.default.addObserver(
      forName: didBecomeActive, object: nil, queue: .main
    ) { _ in
      Task { await clearIfEnded() }
    }
  }
}
