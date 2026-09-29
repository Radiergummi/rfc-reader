import RFCReaderKit
import SwiftUI

/// A draft revising an RFC, opening its datatracker page in the browser, as the errata
/// link does: drafts are not read in the app (VISION.md, Tier 2). The whole row is the
/// link, and reads as the one sentence the summary wrote for it.
struct DraftLink<Label: View>: View {
  let line: RevisionsSummary.Line
  @ViewBuilder let label: Label

  var body: some View {
    // On the link's own element, which keeps its trait and its action.
    Link(destination: line.url) { label }
      .buttonStyle(.plain)
      .accessibilityLabel(line.accessibilityLabel)
  }
}
