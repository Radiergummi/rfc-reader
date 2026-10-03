import RFCReaderKit
import SwiftUI

/// The app's settings, tabbed the way a Mac app's are. A tab joins as a feature
/// arrives that has something worth configuring, rather than ahead of it: Advanced
/// arrives with the first setting that belongs there (#705).
///
/// Reading and Appearance hold the standard settings, the ones a reader expects of
/// Apple Books; Advanced will hold the rest, and never the quick panel (#702). The
/// same sections make up `SettingsScreen`, iOS's, so the two cannot drift.
struct SettingsView: View {
  var body: some View {
    TabView {
      Tab("Reading", systemImage: "textformat.size") {
        Form { ReadingSettings() }
          .formStyle(.grouped)
      }
      Tab("Appearance", systemImage: "paintpalette") {
        Form { AppearanceSettings() }
          .formStyle(.grouped)
      }
      Tab("General", systemImage: "gearshape") {
        Form { GeneralSettings() }
          .formStyle(.grouped)
      }
    }
    // A grouped form is scroll-backed and has no height of its own to offer, so
    // the window is told to size to it rather than left to guess.
    .frame(width: 460)
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// iOS's settings, a sheet from the reader's text size menu and the library's
/// menu: the Mac's tabs as sections of one list (#703).
///
/// In the app rather than in the Settings app: a settings bundle shows no preview,
/// no color picker and no list made at run time, such as a reader's own themes, and
/// Apple keeps it for settings changed rarely. What the Settings app will hold is
/// the system-level kind, such as downloads.
struct SettingsScreen: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Reading") { ReadingSettings() }
        Section("Appearance") { AppearanceSettings() }
        Section("General") { GeneralSettings() }
      }
      .navigationTitle("Settings")
      #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

/// How the text is set: the build-time settings a reader changes while reading.
private struct ReadingSettings: View {
  @ReaderSettingsValue private var settings

  /// A toggle over the preference rather than a picker: there are two choices,
  /// and one of them is the default the reader opts out of. #705 makes it a
  /// picker, with a narrow width.
  private var usesFullWidth: Binding<Bool> {
    Binding(
      get: { settings.measure == .fullWidth },
      set: { $settings.measure.wrappedValue = $0 ? .fullWidth : .recommended }
    )
  }

  var body: some View {
    Slider(
      value: $settings.fontSize, in: ReaderPreferences.fontSizes,
      step: ReaderPreferences.fontSizeStep
    ) {
      Text("Reading font size: \(Int(settings.fontSize))")
    } minimumValueLabel: {
      Image(systemName: "textformat.size.smaller")
    } maximumValueLabel: {
      Image(systemName: "textformat.size.larger")
    }
    .accessibilityValue(ReaderPreferences.percentage(of: settings.fontSize))
    Toggle(isOn: usesFullWidth) {
      Text("Use the full window width for text")
      Text("Otherwise lines stop at a comfortable reading length, and the text is centered.")
    }
    Toggle("Underline links", isOn: $settings.underlineLinks)
    Toggle(isOn: $settings.drawDiagrams) {
      Text("Draw diagrams")
      Text(
        "Otherwise they are shown as the text they were drawn with. A diagram's own menu can still switch it."
      )
    }
  }
}

/// The colors: the page's, which only redraw, and the code's. Each picker lists
/// what the reader offers, one choice each until page themes (#704) and syntax
/// themes (#707) add theirs.
private struct AppearanceSettings: View {
  @ReaderSettingsValue private var settings

  var body: some View {
    Picker("Page", selection: $settings.palette) {
      ForEach(ReaderPalette.all) { palette in
        Text(palette.title).tag(palette)
      }
    }
    Picker("Code", selection: $settings.syntaxTheme) {
      ForEach(SyntaxTheme.all) { theme in
        Text(theme.title).tag(theme)
      }
    }
  }
}

private struct GeneralSettings: View {
  @ReaderSettingsValue private var settings

  var body: some View {
    Toggle(
      "Show the original text rendering by default", isOn: $settings.preferOriginalText)
  }
}

extension ReaderPalette {
  /// What Settings calls it.
  fileprivate var title: String {
    switch id {
    case ReaderPalette.automatic.id: "Automatic"
    default: id.capitalized
    }
  }
}

extension SyntaxTheme {
  /// What Settings calls it.
  fileprivate var title: String {
    switch id {
    case SyntaxTheme.standard.id: "Standard"
    default: id.capitalized
    }
  }
}
