import Foundation

/// A section named across documents, `rfc9110#section-4.2`: the document's file stem
/// and the section's anchor, as the app's links name a place (#192). What an App
/// Intent's section entity is identified by, so Shortcuts and Spotlight can hand one
/// back without the document.
public struct SectionIdentifier: Hashable, Sendable, CustomStringConvertible {
  public var document: DocumentID
  public var anchor: String

  public init(document: DocumentID, anchor: String) {
    self.document = document
    self.anchor = anchor
  }

  /// The section `string` names, or nil unless it is exactly what `description`
  /// writes: a file stem, `#`, and an anchor.
  public init?(_ string: String) {
    guard let separator = string.firstIndex(of: "#"),
      let document = DocumentID(fileStem: String(string[..<separator]))
    else { return nil }
    let anchor = String(string[string.index(after: separator)...])
    guard !anchor.isEmpty else { return nil }
    self.init(document: document, anchor: anchor)
  }

  public var description: String { "\(document.fileStem)#\(anchor)" }
}

/// The sections of a document an App Intent's section query finds (#192).
public enum SectionLookup {
  /// What a number is announced by, `Section 4.2` or `§ 4.2`, and dropped before it
  /// is matched. An appendix's word goes too: its letter is its number.
  private static let numberWords: Set<String> = ["section", "sec", "§", "appendix"]

  /// The sections `query` names, in document order: the one whose number it is,
  /// however it is announced (`4.2`, `Section 4.2.`, `§ 4.2`, `Appendix A`); else the
  /// one whose anchor it is; else every section whose title holds all its words.
  /// Nothing typed lists them all, as the contents do.
  public static func sections(matching query: String, in document: RFCDocument) -> [Section] {
    let all = document.allSections
    let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return all }
    let number = words.drop { numberWords.contains($0.trimmingCharacters(in: ["."])) }
      .joined(separator: " ").trimmingCharacters(in: ["."])
    if let numbered = all.first(where: { $0.number?.lowercased() == number }) {
      return [numbered]
    }
    if let anchored = document.section(anchor: query.trimmingCharacters(in: .whitespaces)) {
      return [anchored]
    }
    return all.filter { section in
      let title = section.titleText.lowercased()
      return words.allSatisfy(title.contains)
    }
  }
}

extension RFCLink {
  /// The link to `section` of `document`: by its place, as a citation names it, or by
  /// its anchor where it has no number, as the acknowledgements have none. What an
  /// App Intent opens a section entity by (#192).
  public init(_ section: Section, in document: DocumentID) {
    let place = section.place
    self.init(id: document, section: place, anchor: place == nil ? section.anchor : nil)
  }
}
