import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif

/// Whether a converted document is RFCXML, and if it is not, why.
///
/// Validity is `xmllint --relaxng` against xml2rfc's `v3.rng`, committed beside this
/// tool with the SVG schema it includes: libxml2's own verdict, not ours. Its messages
/// are no use for saying why, though. They cascade -- one attribute the schema refuses
/// on `<section>` is hundreds of thousands of lines over the corpus, all of them about
/// elements that are fine -- so the causes are found in the document instead, by
/// looking for each mechanical way the serializer is known to leave the schema.
///
/// A document xmllint refuses and none of those checks explains is `unexplained`. That
/// is the bucket a new kind of failure lands in, and the first thing to read after a run.
/// It only sees documents with no known cause, though: a document that already has one
/// can hold a new kind of failure behind it, and the report lists the known cause
/// alone. So the causes say what a document *contains*, not everything xmllint refused,
/// and the bucket watches more of the corpus the fewer documents a known cause is in.
/// What cannot hide is a regression: a document that validated and stops is `[]` no more.
public enum SchemaCheck {
  public enum Cause: String, CaseIterable, Codable, Sendable {
    /// `author+` is required in the document's `<front>` and every reference's.
    case frontWithoutAuthor = "front-without-author"
    /// `anchor` and `pn` are both `xsd:ID`, so one element declaring the same value
    /// in both declares that ID twice.
    case anchorEqualsPartNumber = "anchor-equals-pn"
    /// An ID or IDREF that is not an `NCName`: `anchor="1"`.
    case idNotNCName = "id-not-ncname"
    /// `li`, `dd`, `td`, `th` and `blockquote` hold inline content or blocks, never both.
    case inlineBesideBlocks = "inline-beside-blocks"
    /// The same ID on two elements.
    case duplicateID = "duplicate-id"
    /// An `<xref>`, `<relref>` or `<displayreference>` target, or an `iprExtract`, no
    /// element declares. xmllint resolves IDREFs, so a citation that links nowhere is a
    /// schema failure too, not only a dead link.
    case danglingTarget = "dangling-target"
    /// `<references>` belongs in `<back>`, ahead of its sections, or in another
    /// `<references>` that holds no entries of its own: not in a section, not after
    /// an appendix, and not beside a list's entries.
    case misplacedReferences = "misplaced-references"
    /// `<middle>` requires a section.
    case emptyMiddle = "empty-middle"
    /// `<abstract>` holds `t`, `dl`, `ol` and `ul` only; RFC 391's has artwork.
    case blockInAbstract = "block-in-abstract"
    /// Refused by xmllint, and by none of the checks above.
    case unexplained
  }

  /// Every known cause present in `data`, in declaration order.
  public static func causes(in data: Data) -> [Cause] {
    let finder = CauseFinder()
    let parser = XMLParser(data: data)
    parser.delegate = finder
    parser.parse()
    return Cause.allCases.filter(finder.found.contains)
  }
}

/// Walks a document once and notes every `SchemaCheck.Cause` it finds in it.
private final class CauseFinder: NSObject, XMLParserDelegate {
  var found: Set<SchemaCheck.Cause> = []

  private static let abstractBlocks: Set<String> = ["t", "dl", "ol", "ul"]
  /// The elements whose `target` is an `xsd:IDREF`. `<eref target>` is a URI.
  private static let targetElements: Set<String> = ["xref", "relref", "displayreference"]
  private static let mixedContent: Set<String> = ["li", "dd", "td", "th", "blockquote"]
  private static let inline: Set<String> = [
    "bcp14", "br", "cref", "em", "eref", "iref", "relref", "strong", "sub", "sup", "tt", "u",
    "xref",
  ]

  private struct Open {
    var name: String
    var hasAuthor = false
    var hasSection = false
    var hasInline = false
    var hasBlock = false
    var hasEntries = false
    var hasLists = false
  }

  private var stack: [Open] = []
  private var ids: Set<String> = []
  private var targets: Set<String> = []

  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if let parent = stack.indices.last {
      if name == "author" { stack[parent].hasAuthor = true }
      if name == "section" { stack[parent].hasSection = true }
      if stack[parent].name == "abstract", !Self.abstractBlocks.contains(name) {
        found.insert(.blockInAbstract)
      }
      if name == "references",
        !["back", "references"].contains(stack[parent].name) || stack[parent].hasSection
      {
        found.insert(.misplacedReferences)
      }
      if stack[parent].name == "references" {
        if name == "references" { stack[parent].hasLists = true }
        if name == "reference" || name == "referencegroup" { stack[parent].hasEntries = true }
      }
      if Self.mixedContent.contains(stack[parent].name) {
        if Self.inline.contains(name) {
          stack[parent].hasInline = true
        } else {
          stack[parent].hasBlock = true
        }
      }
    }

    let anchor = attributes["anchor"]
    let partNumber = attributes["pn"]
    if let anchor, anchor == partNumber { found.insert(.anchorEqualsPartNumber) }
    // Every attribute `v3.rng` types `xsd:ID`. Counted once per element, so
    // `anchor == pn` is that cause and not also this one.
    let declared = [anchor, partNumber, attributes["slugifiedName"]].compactMap(\.self)
    for id in Set(declared) where !ids.insert(id).inserted {
      found.insert(.duplicateID)
    }
    // And every one it types `xsd:IDREF`.
    var referenced: [String] = []
    if Self.targetElements.contains(name), let target = attributes["target"] {
      referenced.append(target)
    }
    if name == "rfc", let extract = attributes["iprExtract"] { referenced.append(extract) }
    targets.formUnion(referenced)
    if (declared + referenced).contains(where: { !Self.isNCName($0) }) {
      found.insert(.idNotNCName)
    }

    stack.append(Open(name: name))
  }

  func parserDidEndDocument(_ parser: XMLParser) {
    if !targets.isSubset(of: ids) { found.insert(.danglingTarget) }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard let top = stack.indices.last, Self.mixedContent.contains(stack[top].name),
      string.contains(where: { !$0.isWhitespace })
    else { return }
    stack[top].hasInline = true
  }

  func parser(
    _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
  ) {
    guard let element = stack.popLast() else { return }
    if name == "front", !element.hasAuthor { found.insert(.frontWithoutAuthor) }
    if name == "middle", !element.hasSection { found.insert(.emptyMiddle) }
    if element.hasInline, element.hasBlock { found.insert(.inlineBesideBlocks) }
    if element.hasEntries, element.hasLists { found.insert(.misplacedReferences) }
  }

  /// XML's `NCName`, closely enough for what a converted RFC can contain: a letter or
  /// underscore, then letters, digits, `.`, `-` and `_`. No colon.
  static func isNCName(_ value: String) -> Bool {
    guard let first = value.first, first.isLetter || first == "_" else { return false }
    return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
  }
}
