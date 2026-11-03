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
    @State private var controller: QuickOpenController

    static let width: CGFloat = 620

    init(library: LibraryModel, navigation: NavigationModel, dismiss: @escaping () -> Void) {
      self.library = library
      _controller = State(
        initialValue: QuickOpenController(
          library: library, navigation: navigation, dismiss: dismiss))
    }

    private var results: QuickOpenResults { controller.results }

    private var text: Binding<String> {
      Binding {
        controller.input
      } set: {
        controller.type($0)
      }
    }

    var body: some View {
      VStack(spacing: 0) {
        field
        if !results.rows.isEmpty || results.draft != nil {
          Divider()
          rows
        } else if controller.query.isEmpty {
          // What the field takes (#761).
          Divider()
          Text(verbatim: QuickOpenResults.example)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        } else if let message = controller.message {
          Divider()
          HStack {
            Text(message)
              .lineLimit(2)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
            if case .failed = library.indexState {
              Button("Retry") { library.retryIndex() }
            }
          }
          .padding(.horizontal, 18)
          .padding(.vertical, 12)
        }
      }
      .frame(width: Self.width)
      .glassEffect(.regular, in: .rect(cornerRadius: 18))
      // The check at launch alone goes stale in an app left open for weeks.
      .onAppear { library.refreshRegistriesIfDue() }
      // A series typed before the index loaded is listed as its members once it has.
      .onChange(of: library.index != nil) { controller.resolve() }
      .task(id: controller.searchKey) { await controller.search() }
    }

    private var field: some View {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .font(.title2)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        TextField(QuickOpenResults.placeholder(), text: text)
          .textFieldStyle(.plain)
          .font(.title2)
          .accessibilityLabel("Go to RFC")
          .onKeyPress(.upArrow) { moveSelection(by: -1) }
          .onKeyPress(.downArrow) { moveSelection(by: 1) }
          // Any modifiers: `LinkActivation.current` reads them off the key press, so
          // ⌘↵ opens a tab behind this one and ⇧↵ one in front, as a click does.
          .onKeyPress(.return) {
            guard !isComposing else { return .ignored }
            controller.openSelection()
            return .handled
          }
          // The same, should the field editor take Return before the key press
          // reaches SwiftUI; a handled press never submits, so it cannot open twice.
          .onSubmit(controller.openSelection)
          .onExitCommand(perform: controller.close)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 14)
    }

    /// No hover selection: rows move under a resting pointer as hits arrive, and a
    /// row the pointer merely found itself over must not take ↵ from the one the
    /// keyboard chose. A click opens the row it lands on.
    private var rows: some View {
      VStack(spacing: 2) {
        if let draft = results.draft {
          draftRow(for: draft)
        }
        ForEach(results.rows, id: \.self) { row in
          self.row(for: row)
        }
      }
      .padding(6)
    }

    /// The draft typed (#728), the one row while it is, and selected: ↵ opens it.
    private func draftRow(for draft: DraftLink) -> some View {
      HStack(spacing: 12) {
        Text(verbatim: draft.id.displayName)
          .fontWeight(.semibold)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 0)
        Text("Internet-Draft")
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background {
        RoundedRectangle(cornerRadius: 10).fill(.selection)
      }
      .contentShape(.rect)
      .onTapGesture { controller.open(.draft(draft)) }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits([.isButton, .isSelected])
      .accessibilityAction { controller.open(.draft(draft)) }
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
          Text(verbatim: "\(entry.registry.displayName) \(entry.value)")
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
      .onTapGesture { controller.open(link) }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
      .accessibilityAction { controller.open(link) }
    }

    /// An input method's uncommitted text owns the arrows and Return: they pick and
    /// confirm the composition, not a row.
    private var isComposing: Bool {
      (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
      guard !isComposing else { return .ignored }
      controller.moveSelection(by: offset)
      return .handled
    }
  }
#endif
