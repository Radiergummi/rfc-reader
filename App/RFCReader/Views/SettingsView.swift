import RFCReaderKit
import SwiftUI

/// The app's settings, tabbed the way a Mac app's are. A tab joins as a feature
/// arrives that has something worth configuring, rather than ahead of it.
struct SettingsView: View {
  var body: some View {
    TabView {
      Tab("Reading", systemImage: "textformat.size") {
        ReadingSettings()
      }
      Tab("General", systemImage: "gearshape") {
        GeneralSettings()
      }
      Tab("Notifications", systemImage: "bell") {
        Form {
          NotificationSettings()
        }
        .formStyle(.grouped)
      }
    }
    // A grouped form is scroll-backed and has no height of its own to offer, so
    // the window is told to size to it rather than left to guess.
    .frame(width: 460)
    .fixedSize(horizontal: false, vertical: true)
  }
}

private struct ReadingSettings: View {
  @AppStorage(ReaderPreferences.fontSizeKey) private var fontSize = ReaderPreferences
    .defaultFontSize
  @AppStorage(ReaderPreferences.measureKey) private var measure = ReaderPreferences.defaultMeasure
  @AppStorage(ReaderPreferences.underlineLinksKey) private var underlineLinks =
    ReaderPreferences.defaultUnderlineLinks
  @AppStorage(ReaderPreferences.drawDiagramsKey) private var drawDiagrams =
    ReaderPreferences.defaultDrawDiagrams

  /// A toggle over the preference rather than a picker: there are two choices,
  /// and one of them is the default the reader opts out of.
  private var usesFullWidth: Binding<Bool> {
    Binding(
      get: { measure == .fullWidth },
      set: { measure = $0 ? .fullWidth : .recommended }
    )
  }

  var body: some View {
    Form {
      Slider(
        value: $fontSize, in: ReaderPreferences.fontSizes, step: ReaderPreferences.fontSizeStep
      ) {
        Text("Reading font size: \(Int(fontSize))")
      }
      Toggle(isOn: usesFullWidth) {
        Text("Use the full window width for text")
        Text("Otherwise lines stop at a comfortable reading length, and the text is centered.")
      }
      Toggle("Underline links", isOn: $underlineLinks)
      Toggle(isOn: $drawDiagrams) {
        Text("Draw diagrams")
        Text(
          "Otherwise they are shown as the text they were drawn with. A diagram's own menu can still switch it."
        )
      }
    }
    .formStyle(.grouped)
  }
}

private struct GeneralSettings: View {
  @AppStorage(ReaderPreferences.preferOriginalTextKey) private var preferOriginalText =
    ReaderPreferences.defaultPreferOriginalText

  var body: some View {
    Form {
      Toggle("Show the original text rendering by default", isOn: $preferOriginalText)
    }
    .formStyle(.grouped)
  }
}

/// Notifications about bookmarked RFCs (#191), off until turned on here. Turning
/// them on is when permission is asked for; refused, the toggle goes back off and
/// says where to allow them.
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
