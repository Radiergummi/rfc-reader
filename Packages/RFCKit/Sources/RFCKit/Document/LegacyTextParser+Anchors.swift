import Foundation

extension LegacyTextParser {
  /// Every anchor a section can be declared under, so no entry is: each a section can start
  /// with, and each `makingAnchorsUnique` can rename a repeat to. That rename runs after
  /// the prose is linked, and an entry settled onto `section-1-2` beside two sections
  /// numbered 1 was renamed off it, away from its citations. A repeat takes the first free
  /// `-n`, and what can hold one before it is an earlier repeat or another heading
  /// spelled so (`name-foo-2`, for `Foo 2`), so for an anchor that can appear `c` times,
  /// with `r` headings spelling `-n` of it, the rename lands within `-2` to `-(c + r)`.
  static func reservedAnchors(_ candidates: [String]) -> Set<String> {
    let counts = candidates.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
    var reserved = Set(candidates)
    for (anchor, count) in counts where count > 1 {
      let spelled = counts.keys.count {
        $0.hasPrefix("\(anchor)-") && $0.dropFirst(anchor.count + 1).allSatisfy(\.isNumber)
      }
      for suffix in 2...(count + spelled) { reserved.insert("\(anchor)-\(suffix)") }
    }
    return reserved
  }

  /// `reservedAnchors` for the sections `parse` would read from `text`.
  static func reservedAnchors(in text: String) -> Set<String> {
    reservedAnchors(sectionAnchorCandidates(prepared(text).sections))
  }

  /// Every anchor a section can start with, in document order: the lead-in, then each
  /// heading's own and the one its body after the boilerplate takes.
  static func sectionAnchorCandidates(_ sections: [RawSection]) -> [String] {
    ["preamble"] + sections.compactMap(\.heading).flatMap { [$0.anchor, "after-\($0.anchor)"] }
  }

  /// Each entry's anchor as it will be declared, settled before any prose is linked so a
  /// citation points at the anchor its entry ends with. Renaming repeats afterwards, as
  /// `makingAnchorsUnique` does sections, moved entries out from under the citations
  /// already pointing at them: `[X]`, `[X]`, `[X-2]` made the second `X-2` and the third
  /// `X-2-2`, so `[X-2]` opened the second `[X]`; `[ECMA TR 53]` and `[ECMA TR/53]` spell
  /// one name, and one of them is renamed. The first holder of an anchor keeps it; a
  /// repeat takes the first `-2`, `-3` that no entry is declared under and no section can
  /// take, so none is renamed again.
  static func settlingEntryAnchors(_ lists: [Int: [Reference]], reserved: Set<String>) -> [Int:
    [Reference]]
  {
    var lists = lists
    let declared = Set(lists.values.joined().map(\.anchor))
    var taken = reserved
    for index in lists.keys.sorted() {
      var list = lists[index] ?? []
      for entry in list.indices {
        let anchor = list[entry].anchor
        if taken.insert(anchor).inserted { continue }
        var suffix = 2
        while taken.contains("\(anchor)-\(suffix)") || declared.contains("\(anchor)-\(suffix)") {
          suffix += 1
        }
        list[entry].anchor = "\(anchor)-\(suffix)"
        taken.insert(list[entry].anchor)
      }
      lists[index] = list
    }
    return lists
  }

  /// An anchor is what a deep link, the table of contents and a reading position key off,
  /// and the XML declares each one as an ID, sections and bibliography entries alike.
  /// Headings that repeat -- two `Introduction`s in RFC 1, two sections numbered 1 in RFC
  /// 19 -- and a bibliography listing one label twice gave two elements one anchor in 526
  /// documents (#65), and a link landed on whichever came first. A repeat takes the next
  /// free `-2`, `-3`, the way xml2rfc numbers them; the first keeps its anchor, so every
  /// link that landed on it still does. An entry keeps its label as `displayAnchor`, and
  /// arrives here unique already (`settlingEntryAnchors`), clear of every anchor a
  /// section's repeat can be renamed to (`reservedAnchors`).
  static func makingAnchorsUnique(_ sections: [Section]) -> [Section] {
    var taken: Set<String> = []
    func unique(_ anchor: String) -> String {
      var candidate = anchor
      var suffix = 2
      while !taken.insert(candidate).inserted {
        candidate = "\(anchor)-\(suffix)"
        suffix += 1
      }
      return candidate
    }
    return sections.map { section in
      var section = section
      section.anchor = unique(section.anchor)
      section.blocks = section.blocks.map { block in
        guard case .references(var list) = block else { return block }
        for index in list.entries.indices {
          list.entries[index].anchor = unique(list.entries[index].anchor)
        }
        return .references(list)
      }
      return section
    }
  }
}
