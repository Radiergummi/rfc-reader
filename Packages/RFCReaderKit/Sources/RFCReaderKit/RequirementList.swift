import Foundation
import RFCKit

/// What the Requirements tab shows (#180): a document's requirements under their
/// sections, narrowed by key word and by what they are about, and the conformance
/// checklist exported from what it shows.
public enum RequirementList {
  /// One section's requirements, as a heading and its rows.
  public struct Section: Identifiable, Equatable, Sendable {
    public let anchor: String
    /// `7.2. Host`, or the title alone for an unnumbered section.
    public let heading: String
    public let requirements: [Requirement]

    public var id: String { anchor }
  }

  /// `requirements`, grouped by section in the order they come.
  public static func sections(of requirements: [Requirement]) -> [Section] {
    var sections: [Section] = []
    var current: [Requirement] = []
    func close() {
      guard let first = current.first else { return }
      let heading = first.sectionNumber.map { "\($0). \(first.sectionTitle)" } ?? first.sectionTitle
      sections.append(Section(anchor: first.sectionAnchor, heading: heading, requirements: current))
      current = []
    }
    for requirement in requirements {
      if let last = current.last, last.sectionAnchor != requirement.sectionAnchor { close() }
      current.append(requirement)
    }
    close()
    return sections
  }

  /// The key words `requirements` use, in BCP 14's own order: what the filter
  /// offers.
  public static func keywords(in requirements: [Requirement]) -> [BCP14Keyword] {
    let used = Set(requirements.flatMap(\.keywords))
    return BCP14Keyword.allCases.filter(used.contains)
  }

  /// What the tab is narrowed to: one key word, or all, and words the sentence
  /// contains, such as "server" for "the server MUST …".
  public struct Filter: Equatable, Sendable {
    public var keyword: BCP14Keyword?
    public var text: String

    public init(keyword: BCP14Keyword? = nil, text: String = "") {
      self.keyword = keyword
      self.text = text
    }

    public func apply(to requirements: [Requirement]) -> [Requirement] {
      let text = text.trimmingCharacters(in: .whitespaces)
      return requirements.filter { requirement in
        (keyword.map(requirement.keywords.contains) ?? true)
          && (text.isEmpty || requirement.sentence.localizedCaseInsensitiveContains(text))
      }
    }
  }

  // MARK: - Recovered from legacy text

  /// What the tab and the Markdown checklist say of requirements read from legacy
  /// text (#180), whose sentences the parser recovered rather than was given.
  public static let heuristicNote =
    "Sentences recovered from plain text: check them against the RFC."

  /// `heuristicNote` where any of `requirements` was read from legacy text.
  public static func note(for requirements: [Requirement]) -> String? {
    requirements.contains(where: \.isHeuristic) ? heuristicNote : nil
  }

  // MARK: - Checklist

  /// The checklist as a Markdown task list, one requirement a line, each citing the
  /// section it is in and linking to it.
  public static func markdownChecklist(_ requirements: [Requirement], document: DocumentID)
    -> String
  {
    var lines = ["# \(document.displayName) conformance checklist", ""]
    if let note = note(for: requirements) { lines += ["> \(note)", ""] }
    for requirement in requirements {
      let (citation, link) = cite(requirement, in: document)
      lines.append(
        "- [ ] **\(keywordList(requirement))** \(requirement.sentence) ([\(citation)](\(link)))")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  /// The checklist as CSV (RFC 4180): every field quoted, quotes doubled, lines
  /// ended with CRLF. The last column says whether a requirement was read from
  /// legacy text.
  public static func csvChecklist(_ requirements: [Requirement], document: DocumentID)
    -> String
  {
    func row(_ fields: [String]) -> String {
      fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        .joined(separator: ",") + "\r\n"
    }
    var csv = row(["Key words", "Requirement", "Citation", "Link", "Heuristic"])
    for requirement in requirements {
      let (citation, link) = cite(requirement, in: document)
      let heuristic = requirement.isHeuristic ? "Yes" : "No"
      csv += row([keywordList(requirement), requirement.sentence, citation, link, heuristic])
    }
    return csv
  }

  private static func keywordList(_ requirement: Requirement) -> String {
    requirement.keywords.map(\.rawValue).joined(separator: ", ")
  }

  /// "RFC 9110, Section 7.2" (or "Appendix A.1") and its `rfc://` link, or the
  /// document alone for an unnumbered section.
  private static func cite(_ requirement: Requirement, in document: DocumentID) -> (
    citation: String, link: String
  ) {
    let link = RFCLink(id: document, section: requirement.sectionNumber)
    let citation = CitationFormatter.shortCitation(document, section: requirement.sectionNumber)
    return (citation, link.appURL.absoluteString)
  }
}
