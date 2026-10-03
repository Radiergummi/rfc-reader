#if !os(macOS)
  import RFCReaderKit
  import SwiftUI

  /// The notices the licenses of code the app adapts ask for. iOS has no Settings
  /// screen of the app's own, so the list's menu opens this.
  struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        ScrollView {
          Text(Acknowledgements.text)
            .font(.footnote)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
      }
    }
  }
#endif
