import RFCReaderKit
import SwiftUI

/// "How an RFC Is Made" (#365): the stages from a first draft to a published RFC,
/// each with the glossary terms it names, which open their entries as a label does.
/// Its title is the window's on macOS and the navigation title on iOS.
struct PrimerView: View {
  var body: some View {
    let primer = Glossary.primer()
    VStack(alignment: .leading, spacing: 18) {
      Text(verbatim: primer.introduction)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      ForEach(Array(primer.stages.enumerated()), id: \.element.id) { offset, stage in
        stageView(stage, number: offset + 1)
      }
      stageView(primer.otherStreams, number: nil)
    }
    // A glossary entry opened from here is already inside the primer.
    .environment(\.offersPrimer, false)
    .padding()
    .frame(maxWidth: 560, alignment: .leading)
    .frame(maxWidth: .infinity)
  }

  private func stageView(_ stage: Glossary.Stage, number: Int?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Group {
        if let number {
          Text(verbatim: "\(number.formatted()). \(stage.title)")
        } else {
          Text(verbatim: stage.title)
        }
      }
      .font(.headline)
      .accessibilityAddTraits(.isHeader)
      // Selectable on its own, not with the term links below, which are buttons.
      Text(verbatim: stage.text)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      WrappingRowLayout(spacing: 10) {
        ForEach(stage.related) { term in
          GlossaryButton(term: term, presentation: .here) {
            Text(verbatim: Glossary.entry(for: term).title)
              .foregroundStyle(.tint)
          }
        }
      }
    }
  }
}

/// The primer scrolled, under its title: what a glossary sheet pushes on iOS.
struct PrimerScreen: View {
  var body: some View {
    ScrollView {
      PrimerView()
    }
    .navigationTitle(Glossary.primerTitle())
  }
}

/// A link to the primer: from a glossary entry, and from the empty reader. On macOS
/// it opens the primer's window. On iOS it pushes the primer when `pushes` says the
/// link is inside a navigation stack, as a glossary sheet's is, and presents it as a
/// sheet otherwise.
struct PrimerLink: View {
  /// Whether to push the primer onto the navigation stack the link is in, rather
  /// than present it. The Mac opens the primer's window either way.
  var pushes = false
  #if os(iOS)
    @State private var isPresented = false
  #endif

  var body: some View {
    let title = Glossary.primerTitle()
    #if os(macOS)
      Button(title) { PrimerWindow.show() }
    #else
      if pushes {
        NavigationLink(title) { PrimerScreen() }
      } else {
        Button(title) { isPresented = true }
          .sheet(isPresented: $isPresented) { PrimerSheet() }
      }
    #endif
  }
}

#if os(iOS)
  /// The primer as a sheet, for the empty reader, which is in no navigation stack.
  struct PrimerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        PrimerScreen()
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { dismiss() }
            }
          }
      }
    }
  }
#endif

extension EnvironmentValues {
  /// Whether a glossary entry links to the primer: not inside the primer, where the
  /// link would open what is already open (#365).
  @Entry var offersPrimer = true
}
