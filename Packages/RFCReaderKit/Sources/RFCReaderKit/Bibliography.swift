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
  public let entries: [Reference]

  public var id: String { title }

  /// From the title, as `ReferenceList.kind` is, so the two cannot disagree.
  public var kind: ReferenceList.Kind { ReferenceList.Kind(title: title) }

  public init(title: String, entries: [Reference]) {
    self.title = title
    self.entries = entries
  }

  /// Every bibliography in the document, in document order, skipping empty ones.
  /// Read from the model rather than the built text, because the builder
  /// deliberately leaves these out of it.
  public static func groups(in document: RFCDocument) -> [ReferenceGroup] {
    document.allSections.flatMap { section in
      section.blocks.compactMap { block in
        guard case .references(let list) = block, !list.entries.isEmpty else { return nil }
        return ReferenceGroup(title: list.title, entries: list.entries)
      }
    }
  }
}

/// The kind of the list holding each bibliography entry, by the entry's anchor and
/// by the document it names, so a build asks once per chip without walking every
/// entry of every list (#184).
public struct ReferenceKinds: Sendable {
  private var byAnchor: [String: ReferenceList.Kind] = [:]
  private var byDocument: [DocumentID: ReferenceList.Kind] = [:]

  public init(_ groups: [ReferenceGroup]) {
    for group in groups {
      for entry in group.entries {
        byAnchor[entry.anchor] = Self.stronger(byAnchor[entry.anchor], group.kind)
        if let id = entry.documentID {
          byDocument[id] = Self.stronger(byDocument[id], group.kind)
        }
      }
    }
  }

  /// The kind of the list holding the entry `target` names: found by anchor, by
  /// the entry the parser resolved a document citation to, or else by the document
  /// an entry names; unknown where no list holds it or no list says.
  public func kind(of target: CrossReference.Target) -> ReferenceList.Kind {
    switch target {
    case .anchor(let anchor):
      byAnchor[anchor] ?? .unknown
    case .document(let id, _, let entry):
      entry.flatMap { byAnchor[$0] } ?? byDocument[id] ?? .unknown
    }
  }

  /// Normative where a document lists an entry in both, since it is then part of
  /// the specification.
  private static func stronger(_ current: ReferenceList.Kind?, _ other: ReferenceList.Kind)
    -> ReferenceList.Kind
  {
    if current == .normative || other == .normative { return .normative }
    if current == .informative || other == .informative { return .informative }
    return .unknown
  }
}

extension [ReferenceGroup] {
  /// Whether a citation of `target` is normative or informative: the kind of the
  /// list holding its entry. See `ReferenceKinds`, which a build keeps to answer
  /// this for every chip.
  public func kind(of target: CrossReference.Target) -> ReferenceList.Kind {
    ReferenceKinds(self).kind(of: target)
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
