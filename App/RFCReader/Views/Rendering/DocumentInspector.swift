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
            Picker("View", selection: $tab) {
                Text("Contents").tag(InspectorTab.contents)
                Text("References").tag(InspectorTab.references)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

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
