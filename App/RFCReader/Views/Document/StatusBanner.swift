import RFCKit
import SwiftUI

/// The single most important piece of context: is this still the current document?
struct StatusBanner: View {
  /// Handed over rather than read from the environment.
  ///
  /// This view is hosted in an `NSHostingController`/`UIHostingController` in the
  /// text view's top inset — outside the SwiftUI tree that `ContentView` injects
  /// into — so an `@Environment` lookup here is a runtime trap waiting to fire
  /// rather than a compile-time requirement. The two models arrive as properties so
  /// the compiler is the thing that notices when a call site forgets one.
  let library: LibraryModel
  let navigation: NavigationModel
  let metadata: RFCMetadata

  var body: some View {
    if metadata.isObsolete || !metadata.updatedBy.isEmpty || metadata.hasErrata {
      VStack(alignment: .leading, spacing: 6) {
        if metadata.isObsolete {
          row(
            "Obsoleted by", metadata.obsoletedBy, symbol: "exclamationmark.triangle.fill",
            tint: .red)
        }
        if !metadata.updatedBy.isEmpty {
          row(
            "Updated by", metadata.updatedBy, symbol: "arrow.triangle.2.circlepath", tint: .orange)
        }
        if metadata.hasErrata, let url = metadata.errataURL {
          Link(destination: url) {
            Label("This RFC has errata", systemImage: "pencil.and.list.clipboard")
          }
          .font(.subheadline)
        }
      }
      .padding(12)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
  }

  private func row(_ title: String, _ ids: [DocumentID], symbol: String, tint: Color) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: symbol).foregroundStyle(tint)
      Text(title).fontWeight(.medium)
      ForEach(ids, id: \.self) { id in
        Button(id.displayName) { library.open(id, activation: .current, in: navigation) }
          .buttonStyle(.plain)
          .foregroundStyle(.tint)
      }
    }
    .font(.subheadline)
  }
}
