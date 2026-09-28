#if os(macOS)
  import RFCKit
  import RFCReaderKit
  import SwiftUI

  /// ⌘L on the Mac: one field, and what it finds underneath.
  ///
  /// A palette rather than a dialog, the way Spotlight and Open Quickly are: no title,
  /// no label, no buttons. What was typed is resolved exactly on the keystroke — a
  /// number, `BCP 14`, a link — and searched for as well, so `http caching` offers
  /// candidates where the sheet this replaces could only say it did not recognise it.
  ///
  /// The models are properties, not `@Environment` lookups: this is the root of a
  /// hosting view in a panel of its own, outside every environment chain.
  struct QuickOpenPalette: View {
    let library: LibraryModel
    let navigation: NavigationModel
    let dismiss: () -> Void

    @State private var input = ""
    @State private var results = QuickOpenResults()
    /// Whether the hits on screen are for what is typed now, so "nothing matches"
    /// waits for the search rather than flashing on every keystroke.
    @State private var isSearching = false
    @FocusState private var isFocused: Bool

    static let width: CGFloat = 620

    var body: some View {
      VStack(spacing: 0) {
        field
        if !results.rows.isEmpty {
          Divider()
          rows
        } else if !trimmedInput.isEmpty, !isSearching {
          Divider()
          Text("Nothing in the index matches “\(trimmedInput)”.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
      }
      .frame(width: Self.width)
      .glassEffect(.regular, in: .rect(cornerRadius: 18))
      .task(id: input) { await update() }
      .onAppear { isFocused = true }
    }

    private var field: some View {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .font(.title2)
          .foregroundStyle(.secondary)
        TextField("RFC number, BCP 14, or a link", text: $input)
          .textFieldStyle(.plain)
          .font(.title2)
          .focused($isFocused)
          .onKeyPress(.upArrow) {
            results.moveSelection(by: -1)
            return .handled
          }
          .onKeyPress(.downArrow) {
            results.moveSelection(by: 1)
            return .handled
          }
          // Any modifiers: `LinkActivation.current` reads them off the key press, so
          // ⌘↵ opens a tab behind this one and ⇧↵ one in front, as a click does.
          .onKeyPress(.return) {
            open(results.selected)
            return .handled
          }
          .onExitCommand(perform: dismiss)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 14)
    }

    private var rows: some View {
      VStack(spacing: 2) {
        ForEach(results.rows, id: \.self) { link in
          row(for: link)
        }
      }
      .padding(6)
    }

    private func row(for link: RFCLink) -> some View {
      let isSelected = link == results.selected
      return HStack(spacing: 12) {
        Text(link.id.displayName)
          .fontWeight(.semibold)
          .monospacedDigit()
          .frame(width: 84, alignment: .leading)
        Text(library.metadata(link.id)?.title ?? "Not in the index")
          .lineLimit(1)
          .truncationMode(.tail)
          .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        Spacer(minLength: 0)
        if let section = link.section {
          Text("§ \(section)")
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
      .onHover { inside in
        if inside { results.select(link) }
      }
      .onTapGesture { open(link) }
    }

    private var trimmedInput: String {
      input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs per keystroke and is cancelled by the next one, which is the debounce:
    /// only a pause long enough to outlast the sleep reaches the search.
    private func update() async {
      results.show(exact: DocumentReference.link(from: input))
      let query = trimmedInput
      guard !query.isEmpty else {
        results.show(hits: [])
        isSearching = false
        return
      }
      isSearching = true
      do {
        try await Task.sleep(for: .milliseconds(120))
      } catch {
        return
      }
      let hits = await library.suggestions(for: query, limit: QuickOpenResults.limit)
      guard !Task.isCancelled else { return }
      results.show(hits: hits)
      isSearching = false
    }

    private func open(_ link: RFCLink?) {
      guard let link else { return }
      library.open(link, activation: .current, in: navigation)
      dismiss()
    }
  }
#endif
