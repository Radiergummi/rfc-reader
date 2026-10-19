import RFCKit
import RFCReaderKit
import SwiftUI

/// A draft revising an RFC, opening the revision it names in the reader (#728), as
/// a link followed in it: Command opens it in a tab of its own. The whole row is the
/// link, and reads as the one sentence the summary wrote for it. A name the file
/// gives that is no draft's opens its Datatracker page in the browser instead.
struct RevisingDraftLink<Label: View>: View {
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  let line: RevisionsSummary.Line
  @ViewBuilder let label: Label

  var body: some View {
    // On the link's own element, which keeps its trait and its action.
    Group {
      if let draft = line.draft {
        Button {
          library.open(
            .draft(DraftLink(id: draft)), activation: .current, in: navigation,
            arrival: .citation)
        } label: {
          label
        }
      } else {
        Link(destination: line.url) { label }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(line.accessibilityLabel)
  }
}
