import RFCReaderKit
import SwiftUI

/// A gloss's card (#396): what the document says a term means, beside its use. On
/// hover and force click on macOS, on long press on iOS, as a reference's card is,
/// and as plain to read: no button, since on macOS the popover closes as the pointer
/// moves toward it. Go to Definition is in the term's menu instead.
struct GlossCard: View {
  let gloss: Gloss

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // The document's own words, never looked up in a catalog.
      Text(verbatim: gloss.title).font(.headline)
      Text(verbatim: gloss.text).font(.callout).foregroundStyle(.secondary).lineLimit(10)
    }
    .padding(12)
    .frame(width: ReferencePreview.width, alignment: .leading)
  }
}
