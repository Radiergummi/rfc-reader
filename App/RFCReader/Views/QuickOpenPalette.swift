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
    /// ↵ was pressed while the selection was a hit of an earlier query: open what
    /// the search for the current one selects, as soon as it lands, the way the key
    /// press asked for — its modifiers are long released by then.
    @State private var pendingActivation: LinkActivation?
    @FocusState private var isFocused: Bool

    static let width: CGFloat = 620

    /// What a search depends on. The index is part of it so that a palette opened
    /// before the index loaded searches again once it has.
    private struct SearchKey: Equatable {
      var input: String
      var hasIndex: Bool
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
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
      }
      .frame(width: Self.width)
      .glassEffect(.regular, in: .rect(cornerRadius: 18))
      .task(id: SearchKey(input: input, hasIndex: library.index != nil)) { await update() }
      .onAppear { isFocused = true }
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
        TextField("RFC number, BCP 14, or a link", text: $input)
          .textFieldStyle(.plain)
          .font(.title2)
          .focused($isFocused)
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
        Text(library.summary(of: link.id) ?? "Not in the index")
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

    /// Runs per keystroke and is cancelled by the next one, which is the debounce:
    /// only a pause long enough to outlast the sleep reaches the search.
    private func update() async {
      // Typing on after ↵ is a change of mind.
      pendingActivation = nil
      let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
      let exact = DocumentReference.link(from: query)
      results.show(query: query, exact: exact)
      guard !query.isEmpty else { return }
      // A link names its document outright, and no title or abstract contains one:
      // scanning the index for it would take the whole scan to find nothing.
      if exact != nil, query.contains("://") {
        finish(with: [], for: query)
        return
      }
      guard library.index != nil else {
        finish(with: [], for: query)
        return
      }
      do {
        try await Task.sleep(for: .milliseconds(120))
      } catch {
        return
      }
      let hits = await library.suggestions(for: query, limit: QuickOpenResults.limit)
      guard !Task.isCancelled else { return }
      finish(with: hits, for: query)
    }

    private func finish(with hits: [DocumentID], for query: String) {
      results.show(hits: hits, for: query)
      if let activation = pendingActivation, !results.isSearching {
        pendingActivation = nil
        open(results.openable, activation: activation)
      }
    }

    private func openSelection() {
      if let link = results.openable {
        open(link)
      } else if results.isSearching {
        pendingActivation = .current
      }
    }

    private func open(_ link: RFCLink?, activation: LinkActivation = .current) {
      guard let link else { return }
      library.open(link, activation: activation, in: navigation)
      dismiss()
    }
  }
#endif
