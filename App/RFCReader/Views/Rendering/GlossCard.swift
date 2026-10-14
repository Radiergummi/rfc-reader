import RFCReaderKit
import SwiftUI

/// A gloss's card (#396): what the document says a term means, beside its use. On
/// hover and force click on macOS, on long press on iOS, as a reference's card is,
/// and as plain to read: no button, since on macOS the popover closes as the pointer
/// moves toward it. Go to Definition is in the term's menu instead.
extension Gloss {
  /// The menu item that follows `anchor`: to a term's definition, or to the section
  /// that expands an abbreviation (#67).
  var followTitle: String {
    switch self {
    case .term: String(localized: "Go to Definition")
    case .abbreviation: String(localized: "Go to Expansion")
    }
  }
}

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
