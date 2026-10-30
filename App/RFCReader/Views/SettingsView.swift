import RFCKit
import RFCReaderKit
import SwiftUI

/// The app's settings, tabbed the way a Mac app's are. A tab joins as a feature
/// arrives that has something worth configuring, rather than ahead of it: Advanced
/// arrived with the April 1st RFCs and the status badges (#713).
///
/// Reading and Appearance hold the standard settings, the ones a reader expects of
/// Apple Books; Advanced holds the rest, and never the quick panel (#702). The
/// same sections make up `SettingsScreen`, iOS's, so the two cannot drift.
struct SettingsView: View {
  /// Handed in rather than read from the environment: the Settings scene is a root of
  /// its own on macOS.
  let library: LibraryModel

  var body: some View {
    TabView {
      Tab("Reading", systemImage: "textformat.size") {
        Form {
          ReadingSettings()
          Section("Keyboard") { KeyboardSettings() }
        }
        .formStyle(.grouped)
      }
      Tab("Appearance", systemImage: "paintpalette") {
        Form { AppearanceSettings() }
          .formStyle(.grouped)
      }
      Tab("General", systemImage: "gearshape") {
        Form {
          GeneralSettings()
          Section("Library") { LibrarySettingsSection() }
          Section("Sharing") { SharingSettings() }
        }
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
      Tab("Advanced", systemImage: "gearshape.2") {
        Form { AdvancedSettings(library: library) }
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
        Section("Keyboard") { KeyboardSettings() }
        Section("Appearance") { AppearanceSettings() }
        Section("General") { GeneralSettings() }
        Section("Sharing") { SharingSettings() }
        Section("Notifications") { NotificationSettings() }
        Section("Library") { LibrarySettingsSection() }
        Section("Storage") { StorageSettings(library: library) }
        Section("Advanced") { AdvancedSettings(library: library) }
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
      Text("Text Size: \(Int(settings.fontSize))")
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
      Text("Show Diagrams as Figures")
      Text(
        "Otherwise they are shown as the text they were drawn with. A diagram's own menu can still switch it."
      )
    }
  }
}

/// The reader's keys (#711), with a hardware keyboard on iOS. Here until the
/// registry of Advanced settings (#706) lands, which they move into.
private struct KeyboardSettings: View {
  @ReaderSettingsValue private var settings

  var body: some View {
    Toggle(isOn: $settings.tabsThroughLinks) {
      Text("Move through links with Tab")
      Text("Shift-Tab goes back. Return follows the link, and Space previews it.")
    }
    Toggle(isOn: $settings.vimKeys) {
      Text("Use vim-style keys")
      Text(
        """
        j and k scroll a line, d and u half a page, gg and G go to the top and the end, \
        ]] and [[ to the next and previous section, ]r and [r to the next and previous link, \
        / finds, and n and N go to the next and previous match.
        """
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
    #if os(macOS)
      @Bindable var updater = Updater.shared
      Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
        // Every build shares the release's defaults, so only a release changes them.
        .disabled(!Updater.starts)
    #endif
  }
}

/// What a copy cites in, where a shared link points and what Copy copies (#712).
private struct SharingSettings: View {
  @ReaderSettingsValue private var settings

  var body: some View {
    Picker(selection: $settings.citationStyle) {
      ForEach(CitationStyle.allCases) { style in
        Text(verbatim: style.title()).tag(style)
      }
    } label: {
      Text("Citation Style")
      Text("For Copy Citation, and the line after a quote.")
    }
    Picker(selection: $settings.linkSite) {
      ForEach(LinkSite.allCases) { site in
        Text(verbatim: site.title()).tag(site)
      }
    } label: {
      Text("Links Point To")
      Text("For Share, Copy Link and citations.")
    }
    Picker("Copy Selection As", selection: $settings.copyFormat) {
      ForEach(CopyFormat.allCases) { format in
        Text(verbatim: format.title()).tag(format)
      }
    }
  }
}

/// What a new tab's lists and searches start with (#713). A tab's View Options
/// change its own from there, and a changed setting reaches the tabs opened after it.
private struct LibrarySettingsSection: View {
  @AppStorage(LibraryPreferences.showsObsoleteInListsKey) private var showsObsoleteInLists =
    LibraryPreferences.defaultShowsObsolete
  @AppStorage(LibraryPreferences.showsObsoleteInSearchKey) private var showsObsoleteInSearch =
    LibraryPreferences.defaultShowsObsolete
  @AppStorage(LibraryPreferences.orderKey) private var order = LibraryPreferences.defaultOrder
  @AppStorage(LibraryPreferences.searchesCurrentOnlyKey) private var searchesCurrentOnly =
    LibraryPreferences.defaultSearchesCurrentOnly
  @AppStorage(LibraryPreferences.searchStreamKey) private var searchStream =
    LibraryPreferences.defaultSearchStream

  var body: some View {
    Toggle("Show obsoleted documents in lists", isOn: $showsObsoleteInLists)
    Toggle("Show obsoleted documents in search results", isOn: $showsObsoleteInSearch)
    Picker("Sort lists", selection: $order) {
      ForEach(ListOptions.Order.allCases, id: \.self) { Text(verbatim: $0.title()) }
    }
    Picker(selection: $searchesCurrentOnly) {
      Text("All documents").tag(false)
      Text("Current documents only").tag(true)
    } label: {
      Text("Search")
      Text(
        "Current documents are neither obsoleted nor Historic. The search field shows the scope, and removing it there searches everything."
      )
    }
    Picker("Search stream", selection: $searchStream) {
      Text("All streams").tag("")
      ForEach(PublicationStream.allCases, id: \.self) { stream in
        Text(verbatim: stream.displayName).tag(stream.rawValue)
      }
    }
  }
}

/// Settings few readers change (#705, #713), and how a copy treats a heading's
/// number (#712).
private struct AdvancedSettings: View {
  let library: LibraryModel
  @ReaderSettingsValue private var settings
  @AppStorage(LibraryPreferences.showsStatusBadgesKey) private var showsStatusBadges =
    LibraryPreferences.defaultShowsStatusBadges

  private var showsAprilFirst: Binding<Bool> {
    Binding(get: { library.showsAprilFirst }, set: { library.setShowsAprilFirst($0) })
  }

  var body: some View {
    Toggle(isOn: showsAprilFirst) {
      Text("Show April 1st RFCs")
      Text(
        "Otherwise the April Fools' Day RFCs are left out of lists, search and Just Published. A bookmark, a collection or a link still shows them."
      )
    }
    Toggle(isOn: $showsStatusBadges) {
      Text("Show status badges in lists")
      Text("Otherwise lists are denser, and the status is still read by VoiceOver.")
    }
    Toggle(isOn: $settings.copiesSectionNumbers) {
      Text("Copy section numbers")
      Text("A copied heading keeps its number, as in “4.2. Overview”.")
    }
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
      Text("Notify me about bookmarked RFCs and followed working groups")
      Text(
        """
        When one is obsoleted or updated, a draft starts to revise it or reaches the RFC Editor \
        queue, or errata are listed for it; and when a working group you follow publishes an RFC.
        """
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
/// either; and the full-text index (#37), Index All RFCs and its removal. On the Mac
/// a tab of its own, on iOS a section of `SettingsScreen`.
struct StorageSettings: View {
  let library: LibraryModel

  /// Read when the tab shows and after each change made here, once the keeper has
  /// moved what the change asked; not watched, so a document read meanwhile in a
  /// window counts from the next time the tab shows.
  @State private var usage: StorageReport?
  @State private var confirmsRemoval = false
  /// Read as `usage` is, and again whenever the index changes.
  @State private var textIndex: TextIndexer.Usage?
  /// How many RFCs Index All RFCs would index, read with `textIndex`.
  @State private var unindexed: Int?
  @State private var confirmsIndexRemoval = false

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
      LabeledContent("Available Offline") { UsageValue(usage: usage?.kept) }
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
      // Until the cache is counted too, when there is nothing yet to say it empties,
      // and while all it holds is in use. By its bytes: what Datatracker said of a
      // draft is no document, and may be all there is (#728).
      .disabled((usage?.clearable.bytes ?? 0) == 0)
      if let usage, usage.cache.documents > usage.clearable.documents {
        Text(
          "\(usage.cache.documents - usage.clearable.documents) documents in use stay in the cache."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      LabeledContent("Full-Text Index") { UsageValue(usage: textIndex?.usage) }
      if unindexed == 0, library.index != nil, !library.indexAllRun.isRunning {
        Text("All RFCs are indexed.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        IndexAllRFCsControl(library: library)
      }
      Button("Remove Full-Text Index…", role: .destructive) {
        confirmsIndexRemoval = true
      }
      .disabled(
        library.indexAllRun.isRemoving
          || (textIndex?.retained ?? 0) == 0 && !library.indexAllRun.isRunning
      )
      .confirmationDialog(
        "Remove the full-text index?", isPresented: $confirmsIndexRemoval,
        titleVisibility: .visible
      ) {
        Button("Remove", role: .destructive) {
          Task {
            await library.removeIndexOfAllRFCs()
            await refreshTextIndex()
          }
        }
      } message: {
        Text(
          "The index keeps only the RFCs on this device, and search finds text in those. Index All RFCs downloads the rest again."
        )
      }
    }
    .task { await refresh() }
    .task(id: [library.textIndexVersion, library.indexVersion]) { await refreshTextIndex() }
  }

  private func refresh() async {
    usage = await library.storageUsage()
  }

  private func refreshTextIndex() async {
    textIndex = await library.textIndexUsage()
    unindexed = await library.unindexedRFCCount()
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
