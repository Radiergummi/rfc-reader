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
  let search: (String) -> Void

  var body: some View {
    if let info {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header(info)
          FactStrip(facts: info.facts)
          ForEach(info.sections, id: \.title) { section in
            InfoSection(title: section.title) {
              SectionRows(section: section, library: library, open: open, search: search)
            }
          }
          if let document {
            // One per document, so one's size is never shown under another.
            OfflineSection(document: document, library: library)
              .id(document)
          }
        }
        .padding(16)
        #if !os(macOS)
          // Clear of the sheet's rounded top edge and its grabber.
          .padding(.top, 16)
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      Color.clear
    }
  }

  private func header(_ info: DocumentInfo) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(info.number)
          .font(.infoNumber)
          .foregroundStyle(.secondary)
        Text(info.title)
          .font(.infoTitle)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      if let summary = info.statusSummary {
        StandingBox(
          title: info.status.displayName, summary: summary,
          color: StatusBadge.color(for: info.status))
      }
      if let summary = info.obsoleteSummary {
        StandingBox(title: "Obsolete", summary: summary, color: .red)
      }
    }
  }
}

/// A status, named in full and explained in a sentence, in its tint: what the
/// list's short badge stands for, where there is room to say it.
private struct StandingBox: View {
  let title: String
  let summary: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
      Text(summary)
        .font(.infoCaption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.12), in: .rect(cornerRadius: 8))
    .accessibilityElement(children: .combine)
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
            .font(.infoFact)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text(fact.label)
            .font(.infoFactCaption)
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
        .font(.infoHeading)
        .accessibilityAddTraits(.isHeader)
      content
    }
  }
}

/// A section's rows, set the way the section says: a card of link rows, or a list
/// with related documents as chips under their relationship, keywords as tags, and
/// anything else as a caption over its value.
private struct SectionRows: View {
  let section: DocumentInfo.Section
  let library: LibraryModel
  let open: (DocumentID) -> Void
  let search: (String) -> Void

  var body: some View {
    switch section.style {
    case .card:
      VStack(spacing: 0) {
        ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
          if index > 0 {
            Divider().padding(.leading, 38)
          }
          LinkRow(row: row, library: library)
        }
      }
      .background(.fill.quaternary, in: .rect(cornerRadius: 10))
    case .list:
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
        WrappingRowLayout(spacing: 6) {
          ForEach(documents, id: \.self) { id in
            DocumentChip(id: id) { open(id) }
          }
        }
      }
    case .drafts(let lines):
      VStack(alignment: .leading, spacing: 4) {
        caption(row.label)
        ForEach(lines) { line in
          DraftLink(line: line) {
            VStack(alignment: .leading, spacing: 1) {
              Text(line.title).foregroundStyle(.tint)
              Text(line.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    case .authors(let authors):
      AuthorChips(authors: authors)
    case .keywords(let keywords):
      VStack(alignment: .leading, spacing: 4) {
        caption(row.label)
        WrappingRowLayout(spacing: 6) {
          ForEach(Array(keywords.enumerated()), id: \.offset) { _, keyword in
            KeywordTag(keyword: keyword) { search(keyword) }
          }
        }
      }
    case .text(let text):
      VStack(alignment: .leading, spacing: 1) {
        caption(row.label)
        Text(text)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    case .link, .file, .copyable:
      // A card's rows, which a list section does not hold.
      EmptyView()
    }
  }

  @ViewBuilder
  private func caption(_ label: String) -> some View {
    if !label.isEmpty {
      Text(label)
        .font(.infoCaption)
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

/// A keyword, set as Apple sets tags: a capsule in the secondary fill, searching the
/// library for itself.
private struct KeywordTag: View {
  let keyword: String
  let search: () -> Void

  var body: some View {
    Button(action: search) {
      Text(keyword)
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(.fill.secondary, in: .capsule)
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .help("Search the library for “\(keyword)”")
    .accessibilityHint("Searches the library for it")
  }
}

/// A page elsewhere, a file, or the DOI to copy: an icon, the label, and what the
/// row does.
///
/// A file opens in the browser like a page, and on a Mac Option-click saves it to
/// Downloads instead, as it does in Safari; while Option is held its arrow turns into
/// a download, so the row says what a click will do.
private struct LinkRow: View {
  let row: DocumentInfo.Row
  let library: LibraryModel
  /// A check for a moment after a copy or a download, a warning after a failed one.
  @State private var outcome: Outcome?
  @State private var isOptionHeld = false
  @Environment(\.openURL) private var openURL

  private enum Outcome {
    case done
    case failed
  }

  var body: some View {
    switch row.value {
    case .link(let url):
      Link(destination: url) {
        content(detail: nil, trailing: "arrow.up.right")
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .help(url.absoluteString)
    case .file(let document, let format):
      let url = RFCEditorEndpoints.document(document, format: format)
      Button {
        open(url, saving: (document, format))
      } label: {
        content(
          detail: nil, trailing: outcomeSymbol ?? (isOptionHeld ? "arrow.down" : "arrow.up.right"))
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      #if os(macOS)
        .onModifierKeysChanged(mask: .option, initial: true) { _, keys in
          isOptionHeld = keys.contains(.option)
        }
        .help("Open \(url.lastPathComponent) on rfc-editor.org. Option-click to download it.")
        .contextMenu {
          Button("Download") { save(document, format) }
        }
      #endif
      .task(id: outcome) { await settle() }
    case .copyable(let text):
      Button {
        Clipboard.copy(text)
        outcome = .done
      } label: {
        content(detail: text, trailing: outcomeSymbol ?? "doc.on.doc")
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .help("Copy \(row.label)")
      .task(id: outcome) { await settle() }
    default:
      content(detail: nil, trailing: nil)
    }
  }

  private var outcomeSymbol: String? {
    switch outcome {
    case .done: "checkmark"
    case .failed: "exclamationmark.triangle"
    case nil: nil
    }
  }

  /// The check or the warning stands for a moment, then the row's own icon returns.
  private func settle() async {
    guard outcome != nil else { return }
    try? await Task.sleep(for: .seconds(1.5))
    outcome = nil
  }

  private func open(_ url: URL, saving file: (DocumentID, FileFormat)) {
    #if os(macOS)
      if NSEvent.modifierFlags.contains(.option) {
        save(file.0, file.1)
        return
      }
    #endif
    openURL(url)
  }

  private func save(_ document: DocumentID, _ format: FileFormat) {
    #if os(macOS)
      Task {
        do {
          try await library.saveToDownloads(document, format: format)
          outcome = .done
        } catch {
          outcome = .failed
        }
      }
    #endif
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
            .font(.infoCaption)
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

/// Whether the document is kept offline, and how much it takes: the one part of the
/// pane that is the store's rather than the index's.
///
/// One row whose icon is the control, as a download is in Safari's list: the filled
/// arrow turns to a cross under the pointer and removes the copy, and the outline
/// arrow of a document not kept downloads it. Removing leaves the document on
/// screen, since it is already in memory, and deletes the file, so the next open
/// downloads it again; the tooltip says so. Whether it is kept is the library's set,
/// so it is right the moment the pane shows, and a download or a removal re-reads
/// the size. Only an RFC has a body of its own; a series number the index has not
/// resolved yet has none.
private struct OfflineSection: View {
  let document: DocumentID
  let library: LibraryModel
  /// Nil until read, and for as long as there is nothing to read.
  @State private var size: Int?
  @State private var isHovering = false
  @State private var isWorking = false

  private var isKept: Bool {
    document.series == .rfc && library.downloadedNumbers.contains(document.number)
  }

  var body: some View {
    InfoSection(title: "Offline") {
      HStack(spacing: 10) {
        Button(action: toggle) {
          Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(isKept && isHovering ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(isWorking || document.series != .rfc)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(isKept ? "Remove Offline Copy" : "Keep Offline")
        .accessibilityHint(help)
        Text(isKept ? "Kept offline" : "Not kept offline")
          .foregroundStyle(isKept ? .primary : .secondary)
        Spacer()
        if isKept, let size {
          Text(size.formatted(.byteCount(style: .file)))
            .foregroundStyle(.secondary)
        }
      }
    }
    // Per document already: the section is given the document's identity.
    .task(id: isKept) {
      size = isKept ? await library.downloadedSize(document) : nil
    }
  }

  private var symbol: String {
    if isKept { return isHovering ? "xmark.circle.fill" : "arrow.down.circle.fill" }
    return "arrow.down.circle"
  }

  private var help: String {
    isKept
      ? "Remove the offline copy. It stays open here, and is downloaded again the next time you open it."
      : "Keep a copy to read offline."
  }

  private func toggle() {
    isWorking = true
    Task {
      if isKept {
        await library.removeDownload(document)
      } else {
        try? await library.download(document)
      }
      isWorking = false
    }
  }
}

/// The pane's type, a size larger on iOS. The Mac's inspector is a narrow column of
/// 13 pt text, where a `.title3` title already stands out; an iPhone's sheet is the
/// width of the screen, where the same styles read small beside the rest of iOS,
/// whose item pages (the App Store's, Books') set the name in `.title2` bold and
/// their section headings in `.title3`.
extension Font {
  fileprivate static var infoNumber: Font {
    #if os(macOS)
      .subheadline.weight(.medium)
    #else
      .headline
    #endif
  }

  fileprivate static var infoTitle: Font {
    #if os(macOS)
      .title3.weight(.semibold)
    #else
      .title2.bold()
    #endif
  }

  /// Semibold, not bold, on the Mac: against the pane's regular text and its cards,
  /// bold section headings outweighed what they head.
  fileprivate static var infoHeading: Font {
    #if os(macOS)
      .body.weight(.semibold)
    #else
      .title3.weight(.semibold)
    #endif
  }

  fileprivate static var infoFact: Font {
    #if os(macOS)
      .headline
    #else
      .title3.weight(.semibold)
    #endif
  }

  fileprivate static var infoFactCaption: Font {
    #if os(macOS)
      .caption2
    #else
      .caption
    #endif
  }

  fileprivate static var infoCaption: Font {
    #if os(macOS)
      .caption
    #else
      .footnote
    #endif
  }
}
