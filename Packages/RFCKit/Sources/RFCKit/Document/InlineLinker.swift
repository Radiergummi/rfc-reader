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
  struct Gated<Output> {
    let regex: Regex<Output>
    let gate: KeyPath<Literals, Bool>

    func matches(in text: String, given literals: Literals) -> [Regex<Output>.Match] {
      literals[keyPath: gate] ? text.matches(of: regex) : []
    }
  }

  nonisolated(unsafe) static let sectionOfRFCPattern = Gated(
    regex: #/\bSection\s+(?<section>\d+(?:\.\d+)*)\s+of\s+\[?RFC\s?(?<number>\d+)\]?/#,
    gate: \.sectionOfRFC
  )
  /// A bracket holding a single citation tag. The tag may carry internal spaces,
  /// because roughly a seventh of the corpus sets its citations as `[RFC 2211]`
  /// rather than `[RFC2211]`; a class that admitted no space left those matching
  /// neither this pattern nor the bare one. Anything that is not a document once
  /// parsed -- `[Page 3]`, `[see RFC 2119 and others]` -- is discarded below, and
  /// the bare pattern picks up whatever RFC sits inside it.
  nonisolated(unsafe) static let bracketPattern = Gated(
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
  nonisolated(unsafe) static let bareRFCPattern = Gated(
    regex: #/\bRFC[\s\-]?(?<number>\d+)\b/#, gate: \.rfc)
  /// One list, written once: `RFCs 734, 736, 747 and 749`. Each number is its own
  /// reference but only the first carries the word, so the numbers are linked where
  /// they stand and the sentence is left to read as it was set.
  nonisolated(unsafe) static let rfcListPattern = Gated(
    regex: #/\bRFCs\s+\d{1,5}(?:\s*,\s*(?:and\s+)?\d{1,5}|\s+and\s+\d{1,5})*/#, gate: \.rfcs)
  nonisolated(unsafe) private static let listNumberPattern = #/\d{1,5}/#
  nonisolated(unsafe) static let sectionPattern = Gated(
    regex: #/\bSections?\s+(?<section>\d+(?:\.\d+)*)\b/#, gate: \.section)
  nonisolated(unsafe) static let urlPattern = Gated(regex: #/https?:\/\/[^\s<>"]+/#, gate: \.http)

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
    var sectionOfRFC: Bool { rfc && section }

    init(in text: String) {
      var text = text
      text.withUTF8 { bytes in
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

    for match in Self.sectionOfRFCPattern.matches(in: text, given: literals) {
      guard let number = Int(match.number) else { continue }
      candidates.append(
        Candidate(
          range: match.range,
          inline: .crossReference(
            // The matched prose *is* the label we compose, so it is left to be
            // composed rather than copied: "Section 4.2 of [RFC9110]" reads back
            // out the same, and the reader is free to draw it as one chip.
            CrossReference(
              target: .document(.rfc(number), section: String(match.section)), sectionFormat: .of)
          )))
    }
    for match in Self.bracketPattern.matches(in: text, given: literals) {
      let anchor = String(match.anchor)
      // Parsed once: the label needs it on every path, so the hit path's is free.
      let parsed = DocumentID(parsing: anchor)
      let target: CrossReference.Target
      if let known = referenceTargets[anchor] {
        target = known
      } else if let id = parsed,
        id.series != .rfc || anchor.prefix(3).caseInsensitiveCompare("RFC") == .orderedSame
      {
        target = .document(id, section: nil)
      } else {
        continue
      }
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
      where sectionNumbers.contains(String(match.section)) {
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
}
