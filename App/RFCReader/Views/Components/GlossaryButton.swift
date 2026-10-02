import RFCReaderKit
import SwiftUI

/// Where a glossary entry is presented from.
///
/// A view hosted outside the view-controller hierarchy cannot present on iOS: the
/// reader header's `UIHostingController` is a subview of the text view, not a child
/// controller. Such a view hands the term to its tab's `NavigationModel`, and
/// `ReaderScene`, which is in the window, presents it. Required of every button, so
/// a hosted view that forgets is a compile error rather than a tap that does nothing.
enum GlossaryPresentation {
  /// By the button itself: a view in the window.
  case here
  /// By the tab's scene, on iOS; by the button on macOS, where a popover anchors to
  /// any view in a window.
  case scene(NavigationModel)
}

/// A label that opens its glossary entry (#362): a popover on macOS, a sheet on iOS.
/// The label looks as it did; its summary is also its tooltip.
struct GlossaryButton<Label: View>: View {
  let term: Glossary.Term
  let presentation: GlossaryPresentation
  @ViewBuilder let label: Label

  @State private var isPresented = false

  var body: some View {
    Button(action: present) {
      label.contentShape(.rect)
    }
    .buttonStyle(.plain)
    .glossaryTooltip(term)
    .accessibilityHint("Explains \(Glossary.entry(for: term).title)")
    #if os(macOS)
      .popover(isPresented: $isPresented, arrowEdge: .bottom) {
        GlossaryCard(term: term)
        .frame(width: GlossaryCard.width)
      }
    #else
      .sheet(isPresented: $isPresented) {
        GlossarySheet(term: term)
      }
    #endif
  }

  private func present() {
    #if os(iOS)
      if case .scene(let navigation) = presentation {
        navigation.glossaryTerm = term
        return
      }
    #endif
    isPresented = true
  }
}

extension View {
  /// A term's summary as this view's tooltip: on its own, all a list row gets, since a
  /// row is selected by a click and a popover inside it would fight that (#362).
  func glossaryTooltip(_ term: Glossary.Term) -> some View {
    help(Glossary.entry(for: term).summary)
  }
}

/// An entry, with its related terms as links that open theirs in its place: the
/// popover's content on macOS, and the sheet's on iOS.
struct GlossaryCard: View {
  static let width: CGFloat = 320

  @State private var term: Glossary.Term

  init(term: Glossary.Term) {
    _term = State(initialValue: term)
  }

  var body: some View {
    let entry = Glossary.entry(for: term)
    VStack(alignment: .leading, spacing: 10) {
      Text(entry.title)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Text(entry.explanation)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      VStack(alignment: .leading, spacing: 4) {
        Text("See also")
          .font(.caption)
          .foregroundStyle(.secondary)
        WrappingRowLayout(spacing: 10) {
          ForEach(entry.related) { related in
            Button(Glossary.entry(for: related).title) { term = related }
              .buttonStyle(.plain)
              .foregroundStyle(.tint)
          }
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// An entry as a sheet on iOS: a medium detent, so the reader stays in view above it.
struct GlossarySheet: View {
  let term: Glossary.Term
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        GlossaryCard(term: term)
      }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
