import RFCKit
import RFCReaderKit
import SwiftUI

enum InspectorTab {
    case contents
    case references
}

/// The document's two navigational views, sharing one panel.
///
/// The bibliography is here rather than in the reading flow: every citation in the
/// prose already links straight to the document it names, so the section was several
/// screens of rows nobody reads in order. As a panel it can be consulted beside the
/// text instead of interrupting it.
struct DocumentInspector: View {
    /// The sections the body actually contains, and the bibliography it does not.
    /// Both are derived once per document by `DocumentView` rather than here, where
    /// every section crossing re-evaluates this body.
    let sections: [RFCKit.Section]
    let groups: [ReferenceGroup]
    @Binding var tab: InspectorTab
    let current: String?
    let selectSection: (String) -> Void
    let openDocument: (DocumentID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            InspectorTabBar(tab: $tab)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            switch tab {
            case .contents:
                TableOfContentsView(sections: sections, current: current, select: selectSection)
            case .references:
                // A document with no bibliography says so here rather than being
                // steered away from the tab.
                ReferencesView(groups: groups, open: openDocument)
            }
        }
    }
}

/// The panel's two tabs, drawn the way an inspector's are rather than as a segmented
/// control.
///
/// `.pickerStyle(.segmented)` draws a bordered control sized to its labels, which
/// reads as a form field sitting on the panel rather than as the panel's own
/// navigation. Pages, Numbers and Keynote all use this shape instead: the full width
/// of the inspector, no enclosing border, the selected tab a filled pill, and a hair
/// divider only between two unselected labels.
private struct InspectorTabBar: View {
    @Binding var tab: InspectorTab

    private static let tabs: [(tab: InspectorTab, title: String)] = [
        (.contents, "Contents"),
        (.references, "References"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    // Between two unselected labels only: beside the pill it would be
                    // a second edge a pixel from the first. With two tabs one of them
                    // is always selected, so this never draws — as in Pages, where the
                    // rule shows a divider between its second and third tabs and none
                    // beside the first.
                    Divider()
                        .frame(height: 14)
                        .opacity(touchesSelection(index) ? 0 : 1)
                }
                segment(item.tab, item.title)
            }
        }
        // The track the segments sit in, and the inset that keeps the selected pill
        // inside it rather than flush with its edge.
        .padding(2)
        .background(.quaternary.opacity(0.7), in: .capsule)
    }

    private func segment(_ value: InspectorTab, _ title: String) -> some View {
        let isSelected = tab == value
        return Button {
            tab = value
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        // Fully rounded, not a rounded rectangle: the selected tab in
                        // an inspector is a capsule, and at this height the difference
                        // between a 7 pt radius and a capsule is the whole look.
                        Capsule().fill(Color.accentColor)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Whether the divider at `index` sits against the selected tab.
    private func touchesSelection(_ index: Int) -> Bool {
        Self.tabs[index].tab == tab || Self.tabs[index - 1].tab == tab
    }
}

struct ReferencesView: View {
    let groups: [ReferenceGroup]
    let open: (DocumentID) -> Void

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView("No References", systemImage: "book.closed")
        } else {
            List {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.entries) { entry in
                            ReferenceRow(entry: entry, open: open)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

/// One entry, as a row rather than the four stacked indented paragraphs the body
/// used to render: what it is, then who wrote it and when.
struct ReferenceRow: View {
    let entry: Reference
    let open: (DocumentID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if entry.documentID != nil {
                    Image(systemName: "doc.text").foregroundStyle(.tint).imageScale(.small)
                }
                Text(entry.anchor)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.documentID != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            if entry.title.isEmpty {
                // A legacy-text entry that could not be structured keeps its own words.
                if let raw = entry.rawText {
                    Text(raw).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(entry.title).font(.callout).fixedSize(horizontal: false, vertical: true)
                let byline = entry.authors.joined(separator: ", ")
                let detail = [byline, entry.provenance].filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { if let id = entry.documentID { open(id) } }
    }
}
