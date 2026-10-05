import Foundation

/// A document's index, as prep generates it from the document's `<iref>`s: terms
/// under letters, each with the places that mention it, the defining one primary.
///
/// Only an RFC authored in RFCXML has one from prep: 9051, 9110, 9111, 9112, 9114
/// and 9499 when this was written. Read by `RFCXMLParser` from prep's markup, which
/// is the only shape it takes, and written back in it by `RFCXMLSerializer`.
public struct IndexBlock: Sendable, Hashable, Codable {
  /// The anchor prep gives the index's first paragraph, and nothing else carries:
  /// what tells an index from any other section.
  public static let anchor = "rfc.index.index"

  private static let groupAnchorPrefix = "rfc.index.u"

  /// `A` for `rfc.index.u65`: prep anchors a letter group by its letter's code point.
  /// Nil for an anchor of any other form.
  public static func label(ofGroupAnchor anchor: String) -> String? {
    guard anchor.hasPrefix(groupAnchorPrefix),
      let value = UInt32(anchor.dropFirst(groupAnchorPrefix.count)),
      let scalar = Unicode.Scalar(value)
    else { return nil }
    return String(Character(scalar))
  }

  public var groups: [Group]

  public init(groups: [Group]) {
    self.groups = groups
  }

  /// The entries under one letter or digit.
  public struct Group: Sendable, Hashable, Codable {
    public var label: String
    /// Prep's own, `rfc.index.u65`: what the index's letters link to.
    public var anchor: String
    public var entries: [Entry]

    public init(label: String, anchor: String, entries: [Entry]) {
      self.label = label
      self.anchor = anchor
      self.entries = entries
    }
  }

  /// A term and the places that mention it. One without locators heads its
  /// subentries, as `Grammar` heads the rule names of RFC 9110.
  public struct Entry: Sendable, Hashable, Codable {
    public var term: [Inline]
    public var locators: [Locator]
    public var subentries: [Entry]

    public init(term: [Inline], locators: [Locator] = [], subentries: [Entry] = []) {
      self.term = term
      self.locators = locators
      self.subentries = subentries
    }
  }

  /// A place a term is mentioned, and whether it is the one that defines it, which
  /// prep sets in bold.
  public struct Locator: Sendable, Hashable, Codable {
    public var reference: CrossReference
    public var isPrimary: Bool

    public init(reference: CrossReference, isPrimary: Bool) {
      self.reference = reference
      self.isPrimary = isPrimary
    }
  }

  /// Each entry's term, depth first: what a walk over a document's prose finds of
  /// its index. Not its locators: an index's mention of a section is not a reference
  /// the text makes, and counted as a backlink it was noise.
  public var proseRuns: [[Inline]] {
    func runs(_ entries: [Entry]) -> [[Inline]] {
      entries.flatMap { [$0.term] + runs($0.subentries) }
    }
    return groups.flatMap { runs($0.entries) }
  }
}
