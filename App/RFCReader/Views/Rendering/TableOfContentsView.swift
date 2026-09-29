import RFCKit
import SwiftUI

struct TableOfContentsView: View {
  /// Only the sections the storage holds; see `DocumentView.rebuild()`.
  let sections: [RFCKit.Section]
  let current: String?
  let select: (String) -> Void

  var body: some View {
    List {
      ForEach(sections) { section in
        Button {
          select(section.anchor)
        } label: {
          Text(section.displayTitle)
            .lineLimit(2)
            .padding(.leading, CGFloat(max(0, section.depth - 1)) * 12)
            .fontWeight(section.anchor == current ? .semibold : .regular)
        }
        .buttonStyle(.plain)
        // Weight alone marks the current section only for someone who can see it
        // (#156).
        .accessibilityAddTraits(section.anchor == current ? .isSelected : [])
      }
    }
    .listStyle(.sidebar)
  }
}
