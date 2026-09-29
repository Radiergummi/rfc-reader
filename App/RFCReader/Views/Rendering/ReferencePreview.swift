import RFCKit
import SwiftUI

/// A card previewing a cross reference's target: hover on macOS, long press on
/// iOS. Reads the target from the library's index rather than the reference's
/// own text, which is deliberately terse ("Section 4.2 of [RFC9110]"). Purely
/// informational — no button: on macOS the popover closes on `mouseExited` the
/// moment the pointer moves toward it, so a button inside could never be
/// clicked, and on iOS the same view is a non-interactive context-menu preview.
/// Clicking the chip itself already opens the document, through `clickedOnLink`
/// on macOS and `primaryActionFor` on iOS.
struct ReferencePreview: View {
  let reference: CrossReference
  let library: LibraryModel
  /// The section heading an in-document reference points at.
  var heading: String?
  /// The bibliography entry a citation names, for one that names no RFC (#198).
  /// The body leaves the bibliography to the panel, so this card is the only place
  /// the entry shows beside its citation. The coordinator sets this or `heading`
  /// for an anchor, and shows no card when it has neither.
  var entry: Reference?
  /// Whether the document cites it as part of the specification or as background
  /// (#184), which the card says under its title. Nothing for `.unknown`: a list that
  /// says neither, and every in-document reference.
  var kind: ReferenceList.Kind = .unknown

  /// The card's fixed width, which the iOS preview is also sized at.
  static let width: CGFloat = 280

  private var documentID: DocumentID? {
    guard case .document(let id, _, _) = reference.target else { return nil }
    return id
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let metadata = documentID.flatMap(library.metadata) {
        HStack(alignment: .firstTextBaseline) {
          Text(metadata.title).font(.headline).lineLimit(2)
          Spacer()
          StatusBadge(status: metadata.currentStatus)
        }
        kindLine
        if let abstract = metadata.abstract {
          Text(abstract).font(.callout).foregroundStyle(.secondary).lineLimit(4)
        }
      } else if let documentID {
        // Referenced but not in the library's index — an unpublished draft,
        // or a corpus gap. Never a blank card: name what we do know.
        Text(documentID.displayName).font(.headline)
        kindLine
        Text("Not available in the library.").font(.callout).foregroundStyle(.secondary)
      } else if let heading {
        // A section of this document: "Section 4.2" says where, the heading
        // says what.
        Text(heading).font(.headline)
      } else if let entry {
        entryDescription(entry)
      }
    }
    .padding(12)
    .frame(width: Self.width, alignment: .leading)
  }

  @ViewBuilder
  private var kindLine: some View {
    switch kind {
    case .normative:
      Text("Normative reference").font(.caption).foregroundStyle(.secondary)
    case .informative:
      Text("Informative reference").font(.caption).foregroundStyle(.secondary)
    case .unknown:
      EmptyView()
    }
  }

  /// What the References panel shows for the entry, without its button: the tag
  /// the document cites it by, the title — or, for a legacy entry that could not be
  /// structured, its own words — whether it is normative or informative, the
  /// authors and where it was published, and the host it links to.
  @ViewBuilder
  private func entryDescription(_ entry: Reference) -> some View {
    Text(entry.displayAnchor).font(.subheadline.weight(.semibold))
    if entry.title.isEmpty {
      if let raw = entry.rawText {
        Text(raw).font(.callout).foregroundStyle(.secondary).lineLimit(6)
      }
      kindLine
    } else {
      Text(entry.title).font(.headline).lineLimit(3)
      kindLine
      let byline = entry.authors.map(\.displayName).joined(separator: ", ")
      let detail = [byline, entry.provenance].filter { !$0.isEmpty }.joined(separator: " · ")
      if !detail.isEmpty {
        Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(3)
      }
    }
    if let host = entry.url?.host() {
      Text(host).font(.caption).foregroundStyle(.secondary)
    }
  }
}
