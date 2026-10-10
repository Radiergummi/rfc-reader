import Foundation

/// Turns plain prose into inlines with cross references and links.
struct InlineLinker: Sendable {
  var sectionNumbers: Set<String>
  var referenceTargets: [String: CrossReference.Target]

  private struct Candidate {
    var range: Range<String.Index>
    var inline: Inline
  }

  /// A pattern and the literal it cannot match without, defined together: `link`
  /// reaches a pattern only through `matches(in:given:)`, so no pass can run under
  /// another pattern's gate.
  struct Gated<Output: Sendable>: Sendable {
    let regex: Pattern<Output>
    let gate: any KeyPath<Literals, Bool> & Sendable

    init(regex: Regex<Output>, gate: any KeyPath<Literals, Bool> & Sendable) {
      self.regex = Pattern(regex)
      self.gate = gate
    }

    func matches(in text: String, given literals: Literals) -> [Regex<Output>.Match] {
      literals[keyPath: gate] ? text.matches(of: regex) : []
    }
  }

  /// Sections of another document: "Section 4.2 of [RFC9110]", "Section 3.2 of [5]",
  /// "Sections 3.2 and 4 of RFC-793". The document is an RFC by number or an entry of
  /// the bibliography by its tag. Matched whether or not it resolves, so that
  /// `sectionPattern` never takes the section words for one of this document's own
  /// sections, which linked them into the citing document (#768): a bracket of
  /// several tags, and an RFC run into a name (`RFC822.SIZE`, as `bareRFCPattern`
  /// reads one), are matched too and link nowhere.
  static let sectionOfDocumentPattern = Gated(
    regex:
      // swiftlint:disable:next line_length
      #/\bSections?\s+(?<sections>\d+(?:\.\d+)*(?:(?:\s*,\s*(?:and\s+)?|\s+and\s+)\d+(?:\.\d+)*)*)\s+of\s+(?:\[(?<tag>[A-Za-z0-9][^\[\]\n]*)\]|RFC(?<hyphen>-)?\s?(?<number>\d+)(?<suffix>\w*)(?<name>\.[A-Z])?)/#,
    gate: \.sectionOfDocument
  )
  private static let sectionNumberPattern = Pattern(#/\d+(?:\.\d+)*/#)
  /// A bracket holding a single citation tag. The tag may carry internal spaces,
  /// because roughly a seventh of the corpus sets its citations as `[RFC 2211]`
  /// rather than `[RFC2211]`; a class that admitted no space left those matching
  /// neither this pattern nor the bare one. Anything that is not a document once
  /// parsed -- `[Page 3]`, `[see RFC 2119 and others]` -- is discarded below, and
  /// the bare pattern picks up whatever RFC sits inside it.
  static let bracketPattern = Gated(
    regex: #/\[(?<anchor>[A-Za-z0-9][A-Za-z0-9.\-_ ]*)\]/#, gate: \.bracket)
  /// Deliberately blind to a preceding `[`. A multi-anchor citation
  /// (`[RFC2582,FF96,Hoe96]`) is not a bracket this parser may eat -- the tags
  /// beside the RFC are the author's -- so its RFC is linked where it stands and
  /// the brackets stay as text. Where the bracket *is* ours, `bracketPattern`
  /// starts a character earlier and wins the overlap outright.
  ///
  /// The separator may be a hyphen: the older half of the series writes `RFC-1156`
  /// as its ordinary prose spelling, and `DocumentID` has always read the hyphen as
  /// a separator. Prose held 2,223 of those against 1,640 plain ones, so it was the
  /// larger of the two shapes going unlinked.
  ///
  /// A period and a capital after the number make a name, not a citation: an IMAP
  /// fetch item named after a format (`RFC822.SIZE`), a message field
  /// (`RFC5322.From`), a file (`RFC1131.PS`). A sentence run on without its space
  /// reads the same and loses its link; the legacy corpus holds one, where the
  /// converter joined two paragraphs.
  static let bareRFCPattern = Gated(
    regex: #/\bRFC[\s\-]?(?<number>\d+)\b(?!\.[A-Z])/#, gate: \.rfc)
  /// One list, written once: `RFCs 734, 736, 747 and 749`. Each number is its own
  /// reference but only the first carries the word, so the numbers are linked where
  /// they stand and the sentence is left to read as it was set.
  static let rfcListPattern = Gated(
    regex: #/\bRFCs\s+\d{1,5}(?:\s*,\s*(?:and\s+)?\d{1,5}|\s+and\s+\d{1,5})*/#, gate: \.rfcs)
  private static let listNumberPattern = Pattern(#/\d{1,5}/#)
  static let sectionPattern = Gated(
    regex: #/\bSections?\s+(?<section>\d+(?:\.\d+)*)\b/#, gate: \.section)
  static let urlPattern = Gated(regex: #/https?:\/\/[^\s<>"]+/#, gate: \.http)

  /// What a matched mention reads as: nil when the document spelled the reference
  /// the way the series spells itself, so the label composes back identically, and
  /// the matched words verbatim when it did not. `[RFC2119]` and `RFC 1156` are the
  /// series' own spelling; `[QUIC-TRANSPORT]` is this document's name for the
  /// reference and the hyphen in `RFC-1156` is the author's, and neither is ours to
  /// take out.
  private static func label(_ matched: String, canonicalFor id: DocumentID?) -> String? {
    let canonical = id.map { CrossReference.isCanonicalTag(matched, for: $0) } ?? false
    return canonical ? nil : CrossReference.nonBreakingLabel(matched)
  }

  /// Which of the literals the patterns open with a fragment holds, byte for byte.
  /// Each is necessary for its pattern to match -- the patterns are case-sensitive,
  /// and a grapheme the regex reads as `C` is the byte `C` -- so a pattern whose
  /// literal is absent is skipped without changing what `link` returns.
  /// A pattern above that stops needing its literal -- a `(?i)`, a lowercase
  /// `section`, a `www.` URL -- has to change this too, or its matches are dropped
  /// without a word; `` `the literal gate skips no match` `` is the guard.
  struct Literals {
    var bracket = false, rfc = false, rfcs = false, section = false, http = false
    var any: Bool { bracket || rfc || section || http }
    var sectionOfDocument: Bool { section && (rfc || bracket) }

    init(in text: String) {
      let bytes = text.utf8Span.span
      for index in bytes.indices {
        switch Unicode.Scalar(bytes[index]) {
        case "[": bracket = true
        case "R" where bytes.holds("RFC", at: index):
          rfc = true
          if bytes.holds("RFCs", at: index) { rfcs = true }
        case "S" where bytes.holds("Section", at: index): section = true
        case "h" where bytes.holds("http", at: index): http = true
        default: continue
        }
        // `rfcs` implies `rfc`: nothing later in the fragment can change the answer.
        if bracket, rfcs, section, http { return }
      }
    }
  }

  func link(_ text: String) -> [Inline] {
    // Every pattern below needs a literal to match at all -- `[`, `RFC`, `RFCs`,
    // `Section`, `http` -- and a pass over the UTF-8 does not start the regex
    // engine. Most fragments carry no citation, and the XML parser runs this over
    // every text node of every document. The pass used to test first bytes only,
    // and one of them was `h`, which nearly every sentence holds: all six patterns
    // ran on nearly every fragment.
    guard !text.isEmpty else { return [] }
    let literals = Literals(in: text)
    guard literals.any else { return [.text(text)] }

    var candidates: [Candidate] = []

    // The words of every section of another document, linked or not: none of them
    // is a section of this one.
    var citedSections: [Range<String.Index>] = []
    for match in Self.sectionOfDocumentPattern.matches(in: text, given: literals) {
      citedSections.append(match.range)
      // "RFC 2223bis" is a draft that revises RFC 2223: another document, and not one
      // whose sections are RFC 2223's.
      guard match.suffix?.isEmpty ?? true, match.name == nil,
        let cited = citedDocument(tag: match.tag, number: match.number, hyphen: match.hyphen)
      else { continue }
      let tag = match.tag.map(String.init) ?? ""
      let numbers = match.sections.matches(of: Self.sectionNumberPattern)
      if numbers.count == 1 {
        guard let target = Self.target(cited.target, section: String(match.sections), tag: tag)
        else { continue }
        // The matched prose *is* the label we compose when the document is named as
        // the series names it, so it is left to be composed rather than copied:
        // "Section 4.2 of [RFC9110]" reads back out the same, and the reader is free to
        // draw it as one chip. An entry outside the series composes around its tag.
        let isEntrySection = if case .entrySection = target { true } else { false }
        let composed = cited.isCanonical || isEntrySection
        candidates.append(
          Candidate(
            range: match.range,
            inline: .crossReference(
              CrossReference(
                target: target,
                text: composed ? nil : CrossReference.nonBreakingLabel(String(text[match.range])))
            )))
        continue
      }
      // A list of sections reads as it was written: each number is linked where it
      // stands, and the document after "of" by the passes below.
      for number in numbers {
        guard let target = Self.target(cited.target, section: String(number.output), tag: tag)
        else { continue }
        candidates.append(
          Candidate(
            range: number.range,
            inline: .crossReference(CrossReference(target: target, text: String(number.output)))))
      }
    }
    for match in Self.bracketPattern.matches(in: text, given: literals) {
      let anchor = String(match.anchor)
      // Parsed once: the label needs it on every path, so the hit path's is free.
      let parsed = DocumentID(parsing: anchor)
      guard let target = self.target(ofTag: anchor, parsed: parsed) else { continue }
      candidates.append(
        Candidate(
          range: match.range,
          inline: .crossReference(
            CrossReference(
              target: target, text: Self.label(String(text[match.range]), canonicalFor: parsed))
          )))
    }
    for match in Self.bareRFCPattern.matches(in: text, given: literals) {
      guard let number = Int(match.number) else { continue }
      candidates.append(
        Candidate(
          range: match.range,
          inline: .crossReference(
            CrossReference(
              target: .document(.rfc(number), section: nil),
              text: Self.label(String(text[match.range]), canonicalFor: .rfc(number)))
          )))
    }
    // Only the plural opens a list, and this is the dearest of the six patterns.
    for list in Self.rfcListPattern.matches(in: text, given: literals) {
      for match in text[list.range].matches(of: Self.listNumberPattern) {
        guard let number = Int(match.output) else { continue }
        candidates.append(
          Candidate(
            range: match.range,
            inline: .crossReference(
              CrossReference(
                target: .document(.rfc(number), section: nil), text: String(match.output))
            )))
      }
    }
    // Skipped outright when there are no section numbers to match, which is how
    // the XML parser runs: `<xref>` is how authored XML points at a section, so
    // every match of this pass would be filtered out again.
    if !sectionNumbers.isEmpty {
      for match in Self.sectionPattern.matches(in: text, given: literals)
      where sectionNumbers.contains(String(match.section))
        && !citedSections.contains(where: { $0.overlaps(match.range) })
      {
        candidates.append(
          Candidate(
            range: match.range,
            inline: .crossReference(
              CrossReference(
                target: .anchor(SectionAnchor.anchor(forSectionNumber: String(match.section))),
                text: CrossReference.nonBreakingLabel(String(text[match.range])))
            )))
      }
    }
    for match in Self.urlPattern.matches(in: text, given: literals) {
      let raw = String(match.output).trimmingTrailingPunctuation()
      guard let url = URL(string: raw) else { continue }
      let end = text.index(match.range.lowerBound, offsetBy: raw.count)
      // A URL into the RFC series cites the document it names, whichever site it points
      // at, as an `<eref>` to one reads (#683); the words the prose spelled it in stay.
      if let link = RFCLink(citing: url) {
        let citation = CrossReference(
          target: .document(link.id, section: link.section),
          text: CrossReference.isCanonicalTag(raw, for: link.id) ? nil : raw)
        candidates.append(
          Candidate(range: match.range.lowerBound..<end, inline: .crossReference(citation)))
        continue
      }
      candidates.append(
        Candidate(range: match.range.lowerBound..<end, inline: .link(url, [.text(raw)])))
    }

    // Earliest start wins; on ties the longer match wins. Overlaps are dropped.
    candidates.sort {
      if $0.range.lowerBound != $1.range.lowerBound {
        return $0.range.lowerBound < $1.range.lowerBound
      }
      return $0.range.upperBound > $1.range.upperBound
    }
    var inlines: [Inline] = []
    var cursor = text.startIndex
    for candidate in candidates where candidate.range.lowerBound >= cursor {
      if candidate.range.lowerBound > cursor {
        inlines.append(.text(String(text[cursor..<candidate.range.lowerBound])))
      }
      inlines.append(candidate.inline)
      cursor = candidate.range.upperBound
    }
    if cursor < text.endIndex {
      inlines.append(.text(String(text[cursor...])))
    }
    return inlines
  }

  /// The document a section citation names after "of": an RFC by number, or the
  /// bibliography entry under `tag`, which a tag in the series' own form names
  /// without one. Whether the words name it as the series spells itself, so that the
  /// label is ours to compose.
  private func citedDocument(tag: Substring?, number: Substring?, hyphen: Substring?) -> (
    target: CrossReference.Target, isCanonical: Bool
  )? {
    if let number, let number = Int(number) {
      // The hyphen in `RFC-793` is the author's spelling, not the series'.
      return (.document(.rfc(number), section: nil), hyphen == nil)
    }
    guard let tag else { return nil }
    let parsed = DocumentID(parsing: String(tag))
    // Canonical only for the document the tag names itself: `[BCP14]` resolved to the
    // entry's RFC 2119 is the author's name for it, and composing would say RFC 2119.
    func isCanonical(for target: CrossReference.Target) -> Bool {
      guard let parsed, case .document(parsed, _, _) = target else { return false }
      return CrossReference.isCanonicalTag("[\(tag)]", for: parsed)
    }
    // A series tag the bibliography lacks, `[BCP14]`, names a collection of RFCs,
    // none of whose sections it can say.
    guard let target = self.target(ofTag: String(tag), parsed: parsed),
      referenceTargets[String(tag)] != nil || parsed?.series == .rfc
    else { return nil }
    return (target, isCanonical(for: target))
  }

  /// What a bracketed tag names: its entry in the bibliography, or else the document
  /// the tag names itself, an RFC only when spelled with its series (`[2119]` is a
  /// numbered entry's tag, not RFC 2119). `parsed` is the tag read as a document.
  private func target(ofTag tag: String, parsed: DocumentID?) -> CrossReference.Target? {
    if let known = referenceTargets[tag] { return known }
    guard let parsed,
      parsed.series != .rfc || tag.prefix(3).caseInsensitiveCompare("RFC") == .orderedSame
    else { return nil }
    return .document(parsed, section: nil)
  }

  /// `section` of the document `target` names: a section of an RFC, or of a
  /// bibliography entry outside the series (#473), worded around the `tag` the prose
  /// cites it by. Nil for a target that is neither.
  private static func target(_ target: CrossReference.Target, section: String, tag: String)
    -> CrossReference.Target?
  {
    switch target {
    case .document(let id, nil, let entry): .document(id, section: section, entry: entry)
    case .anchor(let entry): .entrySection(entry: entry, tag: tag, section: section, url: nil)
    default: nil
    }
  }
}
