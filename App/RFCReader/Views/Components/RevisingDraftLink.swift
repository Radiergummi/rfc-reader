import RFCKit
import RFCReaderKit
import SwiftUI

/// A draft revising an RFC, opening the revision it names in the reader (#728)
/// through `open`. The whole row is the link, and reads as the one sentence the
/// summary wrote for it. A name the file gives that is no draft's opens its
/// Datatracker page in the browser instead.
struct RevisingDraftLink<Label: View>: View {
  let line: RevisionsSummary.Line
  /// Opens the revision, as a link followed in the reader: by the caller, since the
  /// panel's sheet closes first on iOS (`PanelHost.leave`).
  let open: (DraftID) -> Void
  @ViewBuilder let label: Label

  var body: some View {
    // On the link's own element, which keeps its trait and its action.
    Group {
      if let draft = line.draft {
        Button {
          open(draft)
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
