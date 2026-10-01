#if os(macOS)
  import AppKit
  import RFCKit
  import RFCReaderKit
  import SwiftUI

  /// ⌘L on the Mac: one field, and what it finds underneath.
  ///
  /// A palette rather than a dialog, the way Spotlight and Open Quickly are: no title,
  /// no label, no buttons. What was typed is resolved exactly on the keystroke — a
  /// number, `BCP 14`, a link — and searched for as well, so `http caching` offers
  /// candidates where the sheet this replaces could only say it did not recognize it.
  ///
  /// The models are properties, not `@Environment` lookups: this is the root of a
  /// hosting view in a panel of its own, outside every environment chain.
  struct QuickOpenPalette: View {
    let library: LibraryModel
    let navigation: NavigationModel
    let dismiss: () -> Void

    @State private var input = ""
    @State private var results = QuickOpenResults()

    static let width: CGFloat = 620

    /// What a search depends on. The index is part of it so that a palette opened
    /// before the index loaded searches again once it has.
    private struct SearchKey: Equatable {
      var query: String
      var hasIndex: Bool
    }

    /// What is typed, less the spaces around it, which change nothing it finds.
    private var query: String {
      input.normalizedQuery
    }

    /// Resolves on the keystroke itself, before any ↵ queued behind it can read the
    /// selection: an `onChange` or the search's task would only run a turn later.
    private var text: Binding<String> {
      Binding {
        input
      } set: { text in
        input = text
        resolve(text.normalizedQuery)
      }
    }

    var body: some View {
      VStack(spacing: 0) {
        field
        if !results.rows.isEmpty {
          Divider()
          rows
        } else if let message {
          Divider()
          Text(message)
            .lineLimit(2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
      }
      .frame(width: Self.width)
      .glassEffect(.regular, in: .rect(cornerRadius: 18))
      // The check at launch alone goes stale in an app left open for weeks.
      .onAppear { library.refreshRegistriesIfDue() }
      // A series typed before the index loaded is listed as its members once it has.
      .onChange(of: library.index != nil) { resolve(query) }
      .task(id: SearchKey(query: query, hasIndex: library.index != nil)) { await search(query) }
    }

    /// Said in place of rows, once there is something to say: not while a search is
    /// still running, so it does not flash on every keystroke.
    private var message: String? {
      let query = results.query
      guard !query.isEmpty, !results.isSearching else { return nil }
      if library.index == nil { return "The RFC index is still loading." }
      return "Nothing in the index matches “\(query)”."
    }

    private var field: some View {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .font(.title2)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        TextField("RFC number, BCP 14, or a link", text: text)
          .textFieldStyle(.plain)
          .font(.title2)
          .accessibilityLabel("Go to RFC")
          .onKeyPress(.upArrow) { moveSelection(by: -1) }
          .onKeyPress(.downArrow) { moveSelection(by: 1) }
          // Any modifiers: `LinkActivation.current` reads them off the key press, so
          // ⌘↵ opens a tab behind this one and ⇧↵ one in front, as a click does.
          .onKeyPress(.return) {
            guard !isComposing else { return .ignored }
            openSelection()
            return .handled
          }
          // The same, should the field editor take Return before the key press
          // reaches SwiftUI; a handled press never submits, so it cannot open twice.
          .onSubmit(openSelection)
          .onExitCommand(perform: dismiss)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 14)
    }

    /// No hover selection: rows move under a resting pointer as hits arrive, and a
    /// row the pointer merely found itself over must not take ↵ from the one the
    /// keyboard chose. A click opens the row it lands on.
    private var rows: some View {
      VStack(spacing: 2) {
        ForEach(results.rows, id: \.self) { row in
          self.row(for: row)
        }
      }
      .padding(6)
    }

    private func row(for row: QuickOpenResults.Row) -> some View {
      let link = row.link
      let isSelected = row == results.selected
      let title = QuickOpenResults.title(
        library.metadata(link.id)?.title, isIndexLoaded: library.index != nil)
      return HStack(spacing: 12) {
        if let entry = row.entry {
          // What was looked up, then where it is defined: "HTTP status 425 · Too
          // Early", RFC 8470.
          Text("\(entry.registry.displayName) \(entry.value)")
            .fontWeight(.semibold)
            .monospacedDigit()
            .lineLimit(1)
          if let name = entry.name {
            Text(name)
              .lineLimit(1)
              .truncationMode(.tail)
              .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
          }
          Spacer(minLength: 0)
          Text(link.id.displayName)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        } else {
          Text(link.id.displayName)
            .fontWeight(.semibold)
            .monospacedDigit()
            .frame(width: 84, alignment: .leading)
          Text(title)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
          Spacer(minLength: 0)
        }
        if let section = link.section {
          Text(PlaceName.abbreviated(section))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 10).fill(.selection)
        }
      }
      .contentShape(.rect)
      .onTapGesture { open(link) }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
      .accessibilityAction { open(link) }
    }

    /// An input method's uncommitted text owns the arrows and Return: they pick and
    /// confirm the composition, not a row.
    private var isComposing: Bool {
      (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
      guard !isComposing else { return .ignored }
      results.moveSelection(by: offset)
      return .handled
    }

    /// What was typed, resolved exactly.
    private func resolve(_ query: String) {
      let exact = DocumentReference.link(from: query)
      let members = exact.flatMap { library.index?.series($0.id)?.members } ?? []
      results.show(
        query: query, exact: exact, members: members,
        registry: library.registryMatches(for: query),
        isObsolete: { library.metadata($0)?.isObsolete ?? false })
    }

    private func search(_ query: String) async {
      if let hits = await library.quickOpenHits(for: query) {
        finish(with: hits, for: query)
      }
    }

    private func finish(with hits: [DocumentID], for query: String) {
      if let opening = results.show(hits: hits, for: query) {
        open(opening.link, activation: opening.activation)
      }
    }

    private func openSelection() {
      if let opening = results.activate(.current) {
        open(opening.link, activation: opening.activation)
      }
    }

    private func open(_ link: RFCLink, activation: LinkActivation = .current) {
      library.open(link, activation: activation, in: navigation)
      dismiss()
    }
  }
#endif
