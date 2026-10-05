import RFCKit
import RFCReaderKit
import SwiftUI

/// The document panel's Contents tab: the sections in the document's order or A–Z,
/// narrowed by a filter.
///
/// What is listed is `ContentsOutline`'s, under test; this only draws it.
struct TableOfContentsView: View {
  /// Only the sections the storage holds; see `DocumentView.rebuild()`.
  let sections: [RFCKit.Section]
  let current: String?
  let select: (String) -> Void

  @State private var filter = ""
  @AppStorage(ReaderPreferences.contentsOrderKey) private var order = ContentsOutline.Order.document

  var body: some View {
    let groups = ContentsOutline.groups(of: sections, filter: filter, order: order)
    VStack(spacing: 0) {
      controls
      Group {
        switch order {
        case .document: documentList(groups.flatMap(\.rows))
        case .alphabetical: alphabeticalList(groups)
        }
      }
      .overlay {
        if groups.isEmpty, !sections.isEmpty {
          ContentUnavailableView.search
        }
      }
    }
  }

  private var controls: some View {
    HStack(spacing: 8) {
      Picker("Order", selection: $order) {
        Text("Document Order").tag(ContentsOutline.Order.document)
        Text("A–Z").tag(ContentsOutline.Order.alphabetical)
      }
      .labelsHidden()
      .fixedSize()
      TextField("Filter", text: $filter)
        .textFieldStyle(.roundedBorder)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func documentList(_ rows: [ContentsOutline.Row]) -> some View {
    List {
      ForEach(rows) { row in
        button(row) {
          Text(row.title)
            .lineLimit(2)
            .padding(.leading, CGFloat(max(0, row.depth - 1)) * 12)
        }
      }
    }
    .listStyle(.sidebar)
    // A sidebar list is announced as "Sidebar", which is the window's own (#300).
    .accessibilityLabel("Contents")
  }

  /// A–Z under letter headers that stay at the top while their rows scroll, as
  /// Contacts' do: a `LazyVStack` pins them the same way on both platforms.
  private func alphabeticalList(_ groups: [ContentsOutline.Group]) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        ForEach(groups) { group in
          SwiftUI.Section {
            ForEach(group.rows) { row in
              button(row) {
                HStack(alignment: .firstTextBaseline) {
                  Text(row.title)
                    .lineLimit(2)
                  Spacer(minLength: 8)
                  if let caption = row.caption {
                    Text(caption)
                      .font(.caption)
                      .monospacedDigit()
                      .foregroundStyle(.secondary)
                  }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
              }
            }
          } header: {
            Text(group.label ?? "")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
              .background(.ultraThinMaterial)
              .accessibilityAddTraits(.isHeader)
          }
        }
      }
    }
    .accessibilityLabel("Contents")
  }

  private func button(
    _ row: ContentsOutline.Row, @ViewBuilder label: () -> some View
  ) -> some View {
    Button {
      select(row.anchor)
    } label: {
      label()
        .fontWeight(row.anchor == current ? .semibold : .regular)
        .foregroundStyle(row.isContext ? .secondary : .primary)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    // Weight alone marks the current section only for someone who can see it
    // (#156).
    .accessibilityAddTraits(row.anchor == current ? .isSelected : [])
    .id(row.anchor)
  }
}
