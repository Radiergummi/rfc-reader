import RFCReaderKit
import SwiftUI

/// Where to open the help: a section, or its top. A new value each time it is asked
/// for, so asking for the section already in view scrolls back to it.
struct HelpTarget: Identifiable, Equatable {
  var section: HelpSection?
  let id = UUID()
}

/// RFC Reader Help (#780): the search syntax, the shortcuts, the gestures, the reading
/// modes and the backlinks, from `HelpContent`. Native text in a window on the Mac
/// and a sheet on iOS, never a web view. Its title is the window's or the navigation
/// bar's.
struct HelpView: View {
  var target: HelpTarget?

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          ForEach(HelpSection.allCases) { section in
            sectionView(section)
              .id(section)
          }
          // How the documents come to be, which the glossary's labels name.
          PrimerLink(pushes: true)
        }
        .padding()
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
      .onChange(of: target, initial: true) { _, target in
        guard let section = target?.section else { return }
        proxy.scrollTo(section, anchor: .top)
      }
    }
  }

  private func sectionView(_ section: HelpSection) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(verbatim: section.title())
        .font(.title3.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
      Text(verbatim: HelpContent.introduction(to: section))
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      if section == .shortcuts {
        shortcuts
      } else {
        ForEach(HelpContent.entries(in: section), id: \.self) { entry in
          VStack(alignment: .leading, spacing: 2) {
            // A filter is syntax, written as it is typed.
            Text(verbatim: entry.term)
              .font(section == .search ? .body.monospaced() : .body.weight(.medium))
            Text(verbatim: entry.text)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .textSelection(.enabled)
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  private var shortcuts: some View {
    ForEach(ReaderShortcut.Group.allCases, id: \.self) { group in
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: group.title())
          .font(.caption.weight(.medium))
          .textCase(.uppercase)
          .tracking(0.6)
          .foregroundStyle(.secondary)
          .accessibilityAddTraits(.isHeader)
        ForEach(ReaderShortcut.rows(in: group), id: \.self) { row in
          HStack(alignment: .firstTextBaseline) {
            Text(verbatim: row.title)
            Spacer(minLength: 12)
            Text(verbatim: row.chords.map(\.symbols).formatted(.list(type: .or).locale(.interface)))
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
        }
      }
      .padding(.top, 4)
    }
  }
}

#if os(iOS)
  /// The help as a sheet: from the library's More menu, and from Help in the iPad's
  /// menu bar.
  struct HelpSheet: View {
    var target: HelpTarget?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        HelpView(target: target)
          .navigationTitle(HelpContent.title())
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { dismiss() }
            }
          }
      }
    }
  }
#endif
