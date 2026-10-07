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
      ForEach(Array(primer.stages.enumerated()), id: \.element.id) { offset, stage in
        stageView(stage, number: offset + 1)
      }
      stageView(primer.otherStreams, number: nil)
    }
    .textSelection(.enabled)
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
      Text(verbatim: stage.text)
        .fixedSize(horizontal: false, vertical: true)
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
    .navigationTitle(Glossary.primer().title)
  }
}

/// A link to the primer: from a glossary entry, and from the empty reader. On macOS
/// it opens the primer's window; on iOS it pushes the primer when it is inside a
/// navigation stack, as a glossary sheet is, and presents it as a sheet otherwise.
struct PrimerLink: View {
  #if os(iOS)
    /// Whether to push the primer onto the navigation stack the link is in, rather
    /// than present it.
    var pushes = false
    @State private var isPresented = false
  #endif

  var body: some View {
    let title = Glossary.primer().title
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
