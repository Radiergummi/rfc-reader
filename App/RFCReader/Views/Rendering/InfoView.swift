import RFCKit
import RFCReaderKit
import SwiftUI

/// The inspector's Info tab (#25): what the index knows about the document, from
/// `DocumentInfo`, and whether it is downloaded.
///
/// Takes the library rather than reading it from the environment: this is hosted in
/// the panel's split item on macOS, outside the SwiftUI tree the window injects into.
struct InfoView: View {
  let sections: [DocumentInfo.Section]
  let document: DocumentID?
  let library: LibraryModel
  let open: (DocumentID) -> Void

  var body: some View {
    List {
      ForEach(sections, id: \.title) { section in
        Section(section.title) {
          ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
            InfoRow(row: row, open: open)
          }
        }
      }
      if let document {
        // A section per document, so one's size is never shown under another.
        DownloadSection(document: document, library: library)
          .id(document)
      }
    }
    #if os(macOS)
      .listStyle(.sidebar)
    #endif
  }
}

private struct InfoRow: View {
  let row: DocumentInfo.Row
  let open: (DocumentID) -> Void

  var body: some View {
    if row.label.isEmpty {
      value
    } else {
      LabeledContent(row.label) { value }
    }
  }

  @ViewBuilder
  private var value: some View {
    switch row.value {
    case .text(let text):
      Text(text).textSelection(.enabled)
    case .copyable(let text):
      Text(text)
        .textSelection(.enabled)
        .contextMenu {
          Button("Copy") { Clipboard.copy(text) }
        }
    case .documents(let documents):
      // A list, one per line: "obsoletes RFC 2616, 7230, 7231, 7232" is a list,
      // not a sentence.
      VStack(alignment: .trailing, spacing: 2) {
        ForEach(documents, id: \.self) { id in
          Button(id.displayName) { open(id) }
            #if os(macOS)
              .buttonStyle(.link)
            #else
              .buttonStyle(.borderless)
            #endif
        }
      }
    case .link(let url):
      Link(url.host() ?? url.absoluteString, destination: url)
    }
  }
}

/// Whether the document is on disk, how much it takes, and Remove Download: the one
/// part of the tab that is the store's rather than the index's.
///
/// Whether it is downloaded is the library's set, so it is right the moment the tab
/// shows, and a download or a removal re-reads the size. Only an RFC has a body of
/// its own; a series number the index has not resolved yet has none.
private struct DownloadSection: View {
  let document: DocumentID
  let library: LibraryModel
  /// Nil until read, and for as long as there is nothing to read.
  @State private var size: Int?

  private var isDownloaded: Bool {
    document.series == .rfc && library.downloadedNumbers.contains(document.number)
  }

  var body: some View {
    Section("Download") {
      if isDownloaded {
        LabeledContent("Downloaded") {
          Text(size?.formatted(.byteCount(style: .file)) ?? "")
        }
        Button("Remove Download", role: .destructive) {
          Task { await library.removeDownload(document) }
        }
      } else {
        Text("Not downloaded").foregroundStyle(.secondary)
      }
    }
    .task(id: DownloadKey(document: document, isDownloaded: isDownloaded)) {
      size = isDownloaded ? await library.downloadedSize(document) : nil
    }
  }

  private struct DownloadKey: Hashable {
    let document: DocumentID
    let isDownloaded: Bool
  }
}
