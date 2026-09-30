import RFCKit
import RFCReaderKit
import SwiftUI

/// The document panel's Requirements tab (#180): every BCP 14 sentence the document
/// states, under its section, narrowed by key word and by what it is about, and
/// exported as a conformance checklist of what it shows.
///
/// What is listed, and what the checklist says, is `RequirementList`'s, under test;
/// this only draws it.
struct RequirementsView: View {
  /// Nil while they are still being extracted, which is not the same as none.
  let requirements: [Requirement]?
  /// The document shown, which the checklist cites.
  let document: DocumentID?
  /// Goes to a requirement's paragraph, the way a Contents row goes to its section.
  let select: (String) -> Void

  @State private var filter = RequirementList.Filter()

  var body: some View {
    if let requirements, !requirements.isEmpty {
      let shown = filter.apply(to: requirements)
      VStack(spacing: 0) {
        controls(shown: shown, keywords: RequirementList.keywords(in: requirements))
        if let note = RequirementList.note(for: requirements) {
          Text(note)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        List {
          ForEach(RequirementList.sections(of: shown)) { section in
            Section(section.heading) {
              // By position: one section can state the same sentence twice, as
              // field after field says "MUST be set to zero".
              ForEach(Array(section.requirements.enumerated()), id: \.offset) { _, requirement in
                row(requirement)
              }
            }
          }
        }
        .listStyle(.sidebar)
        // A sidebar list is announced as "Sidebar", which is the window's own (#300).
        .accessibilityLabel("Requirements")
        .overlay {
          if shown.isEmpty {
            ContentUnavailableView.search
          }
        }
      }
    } else if requirements != nil {
      ContentUnavailableView(
        "No Requirements", systemImage: "checklist",
        description: Text("This document does not use the BCP 14 key words."))
    } else {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func controls(shown: [Requirement], keywords: [BCP14Keyword]) -> some View {
    HStack(spacing: 8) {
      Picker("Key Word", selection: $filter.keyword) {
        Text("All Key Words").tag(BCP14Keyword?.none)
        Divider()
        ForEach(keywords, id: \.self) { keyword in
          Text(keyword.rawValue).tag(BCP14Keyword?.some(keyword))
        }
      }
      .labelsHidden()
      .fixedSize()
      TextField("Filter", text: $filter.text)
        .textFieldStyle(.roundedBorder)
      if let document {
        exportMenu(shown, document: document)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  /// The checklist of what the filter shows, to copy or to share.
  private func exportMenu(_ shown: [Requirement], document: DocumentID) -> some View {
    let markdown = RequirementList.markdownChecklist(shown, document: document)
    return Menu {
      Button("Copy Checklist as Markdown") { Clipboard.copy(markdown) }
      Button("Copy Checklist as CSV") {
        Clipboard.copy(RequirementList.csvChecklist(shown, document: document))
      }
      ShareLink("Share Checklist…", item: markdown)
    } label: {
      Label("Export Checklist", systemImage: "square.and.arrow.up")
    }
    .labelStyle(.iconOnly)
    .fixedSize()
    .disabled(shown.isEmpty)
  }

  private func row(_ requirement: Requirement) -> some View {
    Button {
      select(requirement.anchor)
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          ForEach(requirement.keywords, id: \.self) { keyword in
            Text(keyword.rawValue)
              .font(.caption2.weight(.semibold))
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.tint.opacity(0.15), in: .capsule)
          }
        }
        // The whole sentence: it is what the row is for, and a sidebar list cuts a
        // row to one line unless told otherwise.
        Text(requirement.sentence)
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }
}
