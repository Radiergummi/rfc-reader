import Foundation

extension LegacyTextParser {
  /// Every anchor a section can be declared under, so no entry is: each a section can start
  /// with, and each `makingAnchorsUnique` can rename a repeat to. That rename runs after
  /// the prose is linked, and an entry settled onto a rename beside two sections numbered
  /// 1 was renamed off it, away from its citations. A repeat takes the first free `_n`,
  /// which no heading spells, so for an anchor that can appear `c` times the rename lands
  /// within `_2` to `_c`.
  static func reservedAnchors(_ candidates: [String]) -> Set<String> {
    let counts = candidates.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
    var reserved = Set(candidates)
    for (anchor, count) in counts where count > 1 {
      for suffix in 2...count { reserved.insert(renamed(anchor, suffix)) }
    }
    return reserved
  }

  /// A repeated section's anchor, `section-1_2` for the second `section-1`. Not `-2`, the
  /// shape of a paragraph's part number, `section-1-2` (#491); an underscore is never one
  /// that prep gives or a heading's slug spells.
  static func renamed(_ anchor: String, _ suffix: Int) -> String {
    "\(anchor)_\(suffix)"
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
  /// free `_2`, `_3` (`renamed`); the first keeps its anchor, so every link that landed on
  /// it still does. An entry keeps its label as `displayAnchor`, and arrives here unique
  /// already (`settlingEntryAnchors`), clear of every anchor a section's repeat can be
  /// renamed to (`reservedAnchors`).
  static func makingAnchorsUnique(_ sections: [Section]) -> [Section] {
    var taken: Set<String> = []
    func unique(_ anchor: String) -> String {
      var candidate = anchor
      var suffix = 2
      while !taken.insert(candidate).inserted {
        candidate = renamed(anchor, suffix)
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

  /// Each paragraph's part number, as prep gives authored XML's (#491): `section-4.2-3` for
  /// the third part of section 4.2. Prep numbers a section's parts in one sequence,
  /// paragraphs, lists, artwork, figures and tables alike, so every block uses up a number
  /// but only a paragraph keeps its. A number in `declared` (`declaredAnchors`), a heading
  /// spelled `Foo 2` beside `Foo` or an entry, is left to it, and the paragraph goes without.
  ///
  /// An appendix's parts count from its part number, as prep's do, `section-appendix.a-3`,
  /// since its anchor, `appendix-A`, is not one. The first appendix with a number holds
  /// that part number, as in the serializer, and a repeat counts from its own anchor.
  static func numberingParagraphs(_ sections: [Section], avoiding declared: Set<String>)
    -> [Section]
  {
    var claimed: Set<String> = []
    return sections.map { section in
      var section = section
      var prefix = section.anchor
      if section.isAppendix, let number = section.number {
        // Claimed by the number, as the serializer claims it, and named by the word.
        let claim = PartNumber(sectionNumber: number, isAppendix: true).attribute
        if claimed.insert(claim).inserted {
          prefix =
            PartNumber(sectionNumber: number, isAppendix: true, word: section.appendixWord)
            .attribute
        }
      }
      section.blocks = numberingParagraphs(section.blocks, of: prefix, avoiding: declared)
      return section
    }
  }

  /// Every anchor the sections declare, theirs and their blocks' at any depth, before
  /// any paragraph is numbered.
  static func declaredAnchors(_ sections: [Section]) -> Set<String> {
    Set(sections.flatMap { [$0.anchor] + $0.blocks.flattened.flatMap(\.anchors) })
  }

  /// `blocks`' paragraphs numbered as the parts of the section whose parts count from
  /// `anchor`.
  static func numberingParagraphs(
    _ blocks: [Block], of anchor: String, avoiding declared: Set<String>
  ) -> [Block] {
    blocks.enumerated().map { offset, block in
      let number = "\(anchor)-\(offset + 1)"
      guard case .paragraph(var paragraph) = block, paragraph.anchor == nil,
        !declared.contains(number)
      else { return block }
      paragraph.anchor = number
      return .paragraph(paragraph)
    }
  }
}
