import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI

struct SidebarView: View {
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// For Recently Read's count, which is every document with a place kept.
    @Query private var readingPositions: [ReadingPosition]
  #endif
  // Which sections are open, kept across launches (#344).
  @AppStorage("sidebar.libraryExpanded") private var libraryExpanded = true
  @AppStorage("sidebar.browseExpanded") private var browseExpanded = true
  @AppStorage("sidebar.workingGroupsExpanded") private var workingGroupsExpanded = true

  var body: some View {
    List(selection: Bindable(navigation).sidebarSelection) {
      Section("Library", isExpanded: $libraryExpanded) {
        row(.bookmarks)
        row(.recent)
        row(.downloaded)
      }
      Section("Browse", isExpanded: $browseExpanded) {
        row(.all)
        row(.standards)
        row(.bestCurrentPractice)
        ForEach([RFCKit.Stream.ietf, .irtf, .iab, .independent], id: \.self) { stream in
          row(.stream(stream))
        }
      }
      if !library.topWorkingGroups.isEmpty {
        Section("Working Groups", isExpanded: $workingGroupsExpanded) {
          ForEach(library.topWorkingGroups, id: \.self) { group in
            row(.workingGroup(group))
          }
        }
      }
      // Not on iOS, where the sidebar is a list of places to go and this puts
      // documents among them (#343). It is the top of All RFCs anyway.
      #if os(macOS)
        justPublished
      #endif
    }
    .navigationTitle("RFCs")
    // Search lives on the sidebar, not on the list it filters, and not in the
    // toolbar: the toolbar's trailing end belongs to the panel's toggle, and the
    // document's section of it is the wrong place for something that filters the
    // library. The text it binds to lives on `NavigationModel`, so `RFCListView`
    // filters on it exactly as before.
    #if os(macOS)
      // Written out rather than `.searchable`, which draws nothing here: the
      // sidebar is its own hosting controller now, with no `NavigationSplitView`
      // around it to give `.sidebar` placement a meaning. Measured — the window
      // contained no text field at all.
      .safeAreaInset(edge: .top) {
        SidebarSearchField(navigation: navigation)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
      }
    #else
      .searchable(text: Bindable(navigation).searchText, placement: .sidebar, prompt: "Search")
      // A list of places, titled and headed the way Notes' folders are (#343).
      .navigationBarTitleDisplayMode(.large)
      .headerProminence(.increased)
    #endif
    .labelStyle(SidebarLabelStyle())
  }

  private func row(_ filter: LibraryFilter) -> some View {
    HStack {
      Label(filter.title, systemImage: filter.systemImage)
      #if !os(macOS)
        Spacer()
        // Written out rather than `.badge`, which would draw after the chevron.
        if let count = count(filter) {
          Text(count, format: .number)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        // Collapsed, a row pushes the list, and nothing said so: the rows are
        // selection-tagged rather than `NavigationLink`s, which is what draws the
        // system's own chevron.
        if horizontalSizeClass == .compact {
          Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
      #endif
    }
    .tag(filter)
  }

  #if !os(macOS)
    /// How many documents a row leads to (#344): the index's own count, or the
    /// reader's data for the Library rows. Nil while the index loads, and for a
    /// filter it lists nothing in.
    private func count(_ filter: LibraryFilter) -> Int? {
      switch filter {
      case .bookmarks: library.bookmarkedNumbers.count
      case .downloaded: library.downloadedNumbers.count
      case .recent: readingPositions.count { $0.document?.series == .rfc }
      default: library.indexCounts[filter]
      }
    }
  #endif

  #if os(macOS)
    @ViewBuilder
    private var justPublished: some View {
      if !library.recent.isEmpty {
        Section("Just Published") {
          ForEach(library.recent.prefix(5)) { recent in
            Button {
              library.open(recent.id, activation: .current, in: navigation)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(recent.id.displayName).font(.caption).foregroundStyle(.secondary)
                Text(recent.title).lineLimit(2)
              }
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  #endif
}

#if os(macOS)
  /// The sidebar's search field: AppKit's own `NSSearchField`, so it draws, clears and
  /// behaves as every other Mac search field does (#157).
  ///
  /// Takes the model rather than a binding out of `SidebarView.body`: a binding made
  /// up there makes the whole sidebar — the filter list, the working groups, the index
  /// status — depend on the search text and re-evaluate on every keystroke. In here
  /// the dependency reaches no further than the field.
  private struct SidebarSearchField: NSViewRepresentable {
    let navigation: NavigationModel

    func makeNSView(context: Context) -> NSSearchField {
      let field = NSSearchField()
      field.placeholderString = "Search"
      field.delegate = context.coordinator
      return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
      context.coordinator.navigation = navigation
      // Only when it differs: assigning moves the insertion point to the end, which
      // mid-edit would jump the caret on every keystroke.
      if field.stringValue != navigation.searchText {
        field.stringValue = navigation.searchText
      }
    }

    func makeCoordinator() -> Coordinator { Coordinator(navigation: navigation) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
      var navigation: NavigationModel

      init(navigation: NavigationModel) {
        self.navigation = navigation
      }

      /// Every edit, the clear button included, rather than `searchFieldDidEndSearching`
      /// or the field's action: the list filters as the reader types.
      func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        navigation.searchText = field.stringValue
      }
    }
  }
#endif

/// Gives every sidebar row's icon a column of its own, so the titles line up however
/// wide the glyph is.
///
/// `Label` sizes the icon to the symbol and leaves it at that. Most of the sidebar's
/// symbols carry enough of their own whitespace to look spaced anyway; the wide ones
/// do not, and `person.3` — 28 pt against `bookmark`'s 14 — ran straight into its
/// title. Spacing alone would fix that row and leave the titles on a ragged edge, so
/// the icon gets a fixed column instead and the two problems go away together.
private struct SidebarLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    Row(icon: configuration.icon, title: configuration.title)
  }

  private struct Row: View {
    let icon: LabelStyleConfiguration.Icon
    let title: LabelStyleConfiguration.Title
    /// Wide enough for the widest symbol the sidebar uses, and scaled with the
    /// text so the column still holds at larger accessibility sizes.
    @ScaledMetric(relativeTo: .body) private var column: CGFloat = 22

    var body: some View {
      HStack(spacing: 6) {
        icon
          .frame(width: column)
          #if !os(macOS)
            // In the accent colour, as Notes draws its folders (#343). Not on
            // macOS, whose sidebar tints its icons already and turns them white
            // on a selected row, which an explicit style would override.
            .foregroundStyle(.tint)
          #endif
        title
      }
    }
  }
}
