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
  /// Handed in rather than read from the environment: the Settings scene is a root of
  /// its own on macOS.
  let library: LibraryModel

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
      Tab("Notifications", systemImage: "bell") {
        Form {
          NotificationSettings()
        }
        .formStyle(.grouped)
      }
      Tab("Storage", systemImage: "internaldrive") {
        Form { StorageSettings(library: library) }
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
  let library: LibraryModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Reading") { ReadingSettings() }
        Section("Appearance") { AppearanceSettings() }
        Section("General") { GeneralSettings() }
        Section("Notifications") { NotificationSettings() }
        Section("Storage") { StorageSettings(library: library) }
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
      set: { settings.measure = $0 ? .fullWidth : .recommended }
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

/// Notifications about bookmarked RFCs (#191), off until turned on here. Turning
/// them on is when permission is asked for; refused, the toggle goes back off and
/// says where to allow them. On the Mac it is a tab of its own, and on iOS a
/// section of `SettingsScreen` (#703).
struct NotificationSettings: View {
  @AppStorage(ReaderPreferences.notifyAboutBookmarksKey) private var isOn =
    ReaderPreferences.defaultNotifyAboutBookmarks
  @State private var wasRefused = false

  private var toggle: Binding<Bool> {
    Binding(
      get: { isOn },
      set: { turnedOn in
        guard turnedOn else {
          isOn = false
          BookmarkNotifications.disable()
          return
        }
        isOn = true
        Task {
          let granted = await BookmarkNotifications.requestPermission()
          wasRefused = !granted
          if !granted { isOn = false }
        }
      }
    )
  }

  var body: some View {
    Toggle(isOn: toggle) {
      Text("Notify me about bookmarked RFCs")
      Text(
        "When one is obsoleted or updated, a draft starts to revise it or reaches the RFC Editor queue, or errata are listed for it."
      )
    }
    if wasRefused {
      Text("Notifications for RFC Reader are turned off in System Settings.")
        .foregroundStyle(.secondary)
    }
  }
}

/// Where documents are kept (#358): what the kept tier and the reading cache each
/// hold, keeping the bookmarks offline as well as the marked documents, and emptying
/// either. On the Mac a tab of its own, on iOS a section of `SettingsScreen`.
struct StorageSettings: View {
  let library: LibraryModel

  /// Read when the tab shows and after each change made here, once the keeper has
  /// moved what the change asked; not watched, so a document read meanwhile in a
  /// window counts from the next time the tab shows.
  @State private var usage: (kept: StorageUsage, cache: StorageUsage)?
  @State private var confirmsRemoval = false

  private var keepsBookmarks: Binding<Bool> {
    Binding(
      get: { library.keepsBookmarksOffline },
      set: {
        library.setKeepsBookmarksOffline($0)
        Task { await refresh() }
      }
    )
  }

  var body: some View {
    Group {
      Toggle(isOn: keepsBookmarks) {
        Text("Keep bookmarked documents offline")
        Text("Downloaded when the network is not metered, and kept while bookmarked.")
      }
      LabeledContent("Kept Offline") { UsageValue(usage: usage?.kept) }
      Button("Remove All Offline Documents…", role: .destructive) {
        confirmsRemoval = true
      }
      .disabled(library.offlineMarks.isEmpty && !library.keepsBookmarksOffline)
      .confirmationDialog(
        "Remove all offline documents?", isPresented: $confirmsRemoval, titleVisibility: .visible
      ) {
        Button("Remove All", role: .destructive) {
          library.removeAllOffline()
          Task { await refresh() }
        }
      } message: {
        Text(
          "Documents marked Keep Offline are unmarked on all your devices. Their copies stay in the reading cache until it needs the room."
        )
      }
      LabeledContent("Reading Cache") { UsageValue(usage: usage?.cache) }
      Button("Clear Cache") {
        Task {
          await library.clearCache()
          await refresh()
        }
      }
      // Until the cache is counted too, when there is nothing yet to say it empties.
      .disabled((usage?.cache.documents ?? 0) == 0)
    }
    .task { await refresh() }
  }

  private func refresh() async {
    usage = await library.storageUsage()
  }
}

/// A tier's size over how many documents it holds; nothing until it has been read.
private struct UsageValue: View {
  let usage: StorageUsage?

  var body: some View {
    if let usage {
      VStack(alignment: .trailing, spacing: 1) {
        Text(Int64(usage.bytes), format: .byteCount(style: .file))
        Text("\(usage.documents) documents")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } else {
      ProgressView().controlSize(.small)
    }
  }
}
