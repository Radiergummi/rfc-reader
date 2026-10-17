import RFCReaderKit
import SwiftUI

/// Index All RFCs (#37): the button that starts it, asking first, since it downloads
/// the whole series; while it runs, how far it has got and a button that stops it;
/// and after a run that could not index some RFCs, how many. In Settings, and in the
/// search's footer while the index holds fewer than all.
struct IndexAllRFCsControl: View {
  let library: LibraryModel

  @State private var confirms = false

  var body: some View {
    let run = library.indexAllRun
    if run.isRunning {
      HStack {
        if let progress = run.progress {
          ProgressView(value: Double(progress.indexed), total: Double(max(progress.total, 1))) {
            Text("Indexing \(progress.indexed) of \(progress.total) RFCs")
          }
        } else {
          ProgressView()
            .controlSize(.small)
        }
        Button("Stop") { run.stop() }
      }
    } else {
      VStack(alignment: .leading, spacing: 4) {
        Button("Index All RFCs…") { confirms = true }
          .disabled(!library.hasTextIndex || library.index == nil)
          .confirmationDialog(
            "Index all RFCs?", isPresented: $confirms, titleVisibility: .visible
          ) {
            Button("Index All RFCs") { library.indexAllRFCs() }
          } message: {
            Text(
              "Every RFC not yet indexed is downloaded, about 650 MB, when the network is not metered. Only its text is kept, in an index of about 700 MB. You can stop at any time and go on later."
            )
          }
        if let failed = run.progress?.failed, failed > 0 {
          Text("\(failed) RFCs could not be indexed. Index All RFCs tries them again.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
