import Foundation
import RFCKit

/// One bibliography heading — "Normative References" — and its entries.
///
/// The reader shows these in a panel rather than in the text: every citation in the
/// prose already links straight to the document it names, so the section was several
/// screens of rows nobody reads in order. `DocumentTextBuilder` skips those sections
/// when building the body (`holdsOnlyReferences`); this is the other half of that
/// decision, and it lives here beside it rather than in a view, so both halves are
/// under test.
public struct ReferenceGroup: Identifiable, Sendable {
  public let title: String
  public let kind: ReferenceList.Kind
  public let entries: [Reference]

  public var id: String { title }

  public init(title: String, kind: ReferenceList.Kind, entries: [Reference]) {
    self.title = title
    self.kind = kind
    self.entries = entries
  }

  /// Every bibliography in the document, in document order, skipping empty ones.
  /// Read from the model rather than the built text, because the builder
  /// deliberately leaves these out of it.
  public static func groups(in document: RFCDocument) -> [ReferenceGroup] {
    document.allSections.flatMap { section in
      section.blocks.compactMap { block in
        guard case .references(let list) = block, !list.entries.isEmpty else { return nil }
        return ReferenceGroup(title: list.title, kind: list.kind, entries: list.entries)
      }
    }
  }
}

extension [ReferenceGroup] {
  /// Whether a citation of `target` is normative or informative: the kind of the
  /// list holding its entry, found by anchor or by the document the entry names.
  /// Normative where a document lists the entry in both, since it is then part of
  /// the specification; unknown where no list holds it or no list says.
  public func kind(of target: CrossReference.Target) -> ReferenceList.Kind {
    let holding = filter { group in
      group.entries.contains { entry in
        switch target {
        case .anchor(let anchor): entry.anchor == anchor
        case .document(let id, _): entry.documentID == id
        }
      }
    }
    if holding.contains(where: { $0.kind == .normative }) { return .normative }
    if holding.contains(where: { $0.kind == .informative }) { return .informative }
    return .unknown
  }

  /// The entry a citation names by `anchor`, from whichever bibliography holds it:
  /// what a preview of the citation shows, since the body leaves the entries out.
  public func entry(anchor: String) -> Reference? {
    for group in self {
      if let entry = group.entries.first(where: { $0.anchor == anchor }) { return entry }
    }
    return nil
  }
}

extension Reference {
  /// The entry's `<annotation>`, for the panel to show under its provenance line,
  /// or nil when it has none. External links stay links, since the usual annotation
  /// is the commit a living standard was cited at and a snapshot nobody can open is
  /// only half kept; everything else reads as its words.
  public var annotationText: AttributedString? {
    annotation.isEmpty ? nil : Self.attributedText(annotation)
  }

  private static func attributedText(_ inlines: [Inline]) -> AttributedString {
    var result = AttributedString()
    for inline in inlines {
      switch inline {
      case .link(let url, let inner):
        var linked = AttributedString(inner.plainText)
        linked.link = url
        result += linked
      case .emphasis(let inner), .strong(let inner):
        result += attributedText(inner)
      default:
        result += AttributedString([inline].plainText)
      }
    }
    return result
  }
}
