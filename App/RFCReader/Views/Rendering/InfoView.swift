import RFCKit
import RFCReaderKit
import SwiftUI

/// The Info pane (#25): what the index knows about the document, from
/// `DocumentInfo`, and whether it is kept offline.
///
/// Laid out as Books and the App Store present an item: a header naming it and its
/// standing, a strip of key facts, then sections — related documents as the
/// reader's own chips, pages elsewhere as rows with an icon, and the details.
///
/// Takes the library rather than reading it from the environment: this is hosted in
/// the panel's split item on macOS, outside the SwiftUI tree the window injects into.
struct InfoView: View {
  let info: DocumentInfo?
  let document: DocumentID?
  let library: LibraryModel
  let open: (DocumentID) -> Void

  var body: some View {
    if let info {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header(info)
          FactStrip(facts: info.facts)
          ForEach(info.sections, id: \.title) { section in
            InfoSection(title: section.title) {
              SectionRows(section: section, open: open)
            }
          }
          if let document {
            // One per document, so one's size is never shown under another.
            OfflineSection(document: document, library: library)
              .id(document)
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      Color.clear
    }
  }

  private func header(_ info: DocumentInfo) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(info.number)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
      Text(info.title)
        .font(.title3.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      HStack(spacing: 6) {
        if info.status != .unknown {
          StatusBadge(status: info.status)
        }
        if info.isObsolete {
          Text("Obsolete")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red.opacity(0.15), in: Capsule())
            .foregroundStyle(.red)
        }
      }
      .padding(.top, 2)
    }
  }
}

/// A few short values over their captions, side by side, as the App Store sets an
/// app's age rating, size and category under its name.
private struct FactStrip: View {
  let facts: [DocumentInfo.Fact]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
        if index > 0 {
          Divider().frame(height: 28)
        }
        VStack(spacing: 2) {
          Text(fact.value)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text(fact.label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
      }
    }
    .padding(.vertical, 10)
    .background(.fill.quaternary, in: .rect(cornerRadius: 10))
  }
}

private struct InfoSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      content
    }
  }
}

/// A section's rows, in the shape their values call for: links as a card of rows,
/// related documents as chips under their relationship, and anything else as a
/// caption over its value.
private struct SectionRows: View {
  let section: DocumentInfo.Section
  let open: (DocumentID) -> Void

  var body: some View {
    if section.rows.allSatisfy({ $0.symbol != nil }) {
      VStack(spacing: 0) {
        ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
          if index > 0 {
            Divider().padding(.leading, 38)
          }
          LinkRow(row: row)
        }
      }
      .background(.fill.quaternary, in: .rect(cornerRadius: 10))
    } else {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
          rowView(row)
        }
      }
    }
  }

  @ViewBuilder
  private func rowView(_ row: DocumentInfo.Row) -> some View {
    switch row.value {
    case .documents(let documents):
      VStack(alignment: .leading, spacing: 4) {
        caption(row.label)
        // A list, not a sentence: "obsoletes RFC 2616, 7230, 7231, 7232" is several
        // documents, each one to open.
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 76), spacing: 6, alignment: .leading)],
          alignment: .leading, spacing: 6
        ) {
          ForEach(documents, id: \.self) { id in
            DocumentChip(id: id) { open(id) }
          }
        }
      }
    case .text(let text), .copyable(let text):
      VStack(alignment: .leading, spacing: 1) {
        caption(row.label)
        Text(text)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    case .link(let url):
      Link(row.label, destination: url)
    }
  }

  @ViewBuilder
  private func caption(_ label: String) -> some View {
    if !label.isEmpty {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

/// Another document, as the reader draws a reference to one: the accent-tinted chip,
/// opening it in the reader.
private struct DocumentChip: View {
  let id: DocumentID
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      Text(id.displayName)
        .lineLimit(1)
        .foregroundStyle(.tint)
        // `FragmentGeometry.chipPadding` and the radius `RFCTextLayoutFragment`
        // draws the reader's chips with.
        .padding(.horizontal, FragmentGeometry.chipPadding)
        .padding(.vertical, FragmentGeometry.chipVerticalPadding)
        .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    // The system's focus ring drew round the first chip as soon as the pane showed.
    .focusEffectDisabled()
    .accessibilityHint("Opens the document")
  }
}

/// A page elsewhere, or the DOI to copy: an icon, the label, and what the row does.
private struct LinkRow: View {
  let row: DocumentInfo.Row
  @State private var copied = false

  var body: some View {
    switch row.value {
    case .link(let url):
      Link(destination: url) {
        content(detail: nil, trailing: "arrow.up.right")
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .help(url.absoluteString)
    case .copyable(let text):
      Button {
        Clipboard.copy(text)
        copied = true
      } label: {
        content(detail: text, trailing: copied ? "checkmark" : "doc.on.doc")
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .help("Copy \(row.label)")
      .task(id: copied) {
        guard copied else { return }
        try? await Task.sleep(for: .seconds(1.5))
        copied = false
      }
    default:
      content(detail: nil, trailing: nil)
    }
  }

  private func content(detail: String?, trailing: String?) -> some View {
    HStack(spacing: 10) {
      Image(systemName: row.symbol ?? "link")
        .foregroundStyle(.tint)
        .frame(width: 18)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(row.label)
        if let detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      Spacer(minLength: 4)
      if let trailing {
        Image(systemName: trailing)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .contentShape(.rect)
  }
}

/// Whether the document is kept offline, how much it takes, and removing the copy:
/// the one part of the pane that is the store's rather than the index's.
///
/// Removing it leaves the document on screen — it is already in memory — and
/// deletes the file, so the next open downloads it again; the footnote says so,
/// because otherwise the button looks like it did nothing. Whether it is kept is the
/// library's set, so it is right the moment the pane shows, and a download or a
/// removal re-reads the size. Only an RFC has a body of its own; a series number the
/// index has not resolved yet has none.
private struct OfflineSection: View {
  let document: DocumentID
  let library: LibraryModel
  /// Nil until read, and for as long as there is nothing to read.
  @State private var size: Int?

  private var isKept: Bool {
    document.series == .rfc && library.downloadedNumbers.contains(document.number)
  }

  var body: some View {
    InfoSection(title: "Offline") {
      if isKept {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
              .foregroundStyle(.tint)
              .accessibilityHidden(true)
            Text("Kept offline")
            Spacer()
            Text(size?.formatted(.byteCount(style: .file)) ?? "")
              .foregroundStyle(.secondary)
          }
          Button("Remove Offline Copy", role: .destructive) {
            Task { await library.removeDownload(document) }
          }
          .buttonStyle(.bordered)
          .focusEffectDisabled()
          Text("It stays open here, and is downloaded again the next time you open it.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        Text("Not kept offline. Opening it downloads it again.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .task(id: OfflineKey(document: document, isKept: isKept)) {
      size = isKept ? await library.downloadedSize(document) : nil
    }
  }

  private struct OfflineKey: Hashable {
    let document: DocumentID
    let isKept: Bool
  }
}
