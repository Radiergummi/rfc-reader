import Foundation
import Testing

@testable import RFCKit

@Suite("RFCXML serializer")
struct RFCXMLSerializerTests {
  /// A structural fingerprint: section tree, block kinds and paragraph text.
  static func signature(_ document: RFCDocument) -> [String] {
    var lines: [String] = []
    func blockKind(_ block: Block) -> String {
      switch block {
      case .paragraph(let paragraph): "P:" + paragraph.plainText
      case .list(let list):
        "L\(list.items.count):"
          + list.items.map { $0.blocks.map(blockKind).joined(separator: "|") }.joined(
            separator: "||")
      case .definitionList(let list):
        "D\(list.items.count)\(list.isCompact ? "c" : "")\(list.hangsTerms ? "h" : ""):"
          + list.items.map { $0.term.plainText }.joined(separator: "|")
      case .preformatted(let artwork): "A:" + artwork.text
      case .figure(let figure):
        "F:\(figure.title, default: "")" + figure.blocks.map(blockKind).joined(separator: "|")
      case .table(let table): "T:\(table.header.count)x\(table.rows.count)"
      case .blockQuote(let blocks): "Q:" + blocks.map(blockKind).joined(separator: "|")
      case .aside(let blocks): "S:" + blocks.map(blockKind).joined(separator: "|")
      case .references(let list):
        "R:"
          + list.entries.map { "\($0.anchor)=\($0.documentID, default: "-")" }.joined(
            separator: ",")
      }
    }
    func visit(_ section: Section, depth: Int) {
      lines.append(
        "\(depth) \(section.anchor) [\(section.number, default: "-")] \(section.isAppendix ? "appendix " : "")\(section.title)"
      )
      for block in section.blocks { lines.append("  " + blockKind(block)) }
      for sub in section.subsections { visit(sub, depth: depth + 1) }
    }
    lines.append(
      "title=\(document.header.title) id=\(document.header.id, default: "-") authors=\(document.header.authors.map(\.name))"
    )
    for block in document.header.abstract { lines.append("abstract " + blockKind(block)) }
    for section in document.sections { visit(section, depth: 1) }
    return lines
  }

  @Test func `round trips RFCXML`() throws {
    let original = try RFCXMLParser.parse(try Fixtures.data("rfc8999.xml"))
    let xml = RFCXMLSerializer().serialize(original)
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(Self.signature(reparsed) == Self.signature(original))
    #expect(reparsed.referencedDocuments == original.referencedDocuments)
    #expect(reparsed.header.date == original.header.date)
    #expect(reparsed.header.keywords == original.header.keywords)
  }

  @Test func `an entrys printed tag survives a round trip`() throws {
    let original = try RFCXMLParser.parse(try Fixtures.data("rfc9220.xml"))
    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(original).utf8))
    func tags(_ document: RFCDocument) -> [String] {
      document.allSections.flatMap(\.blocks).flatMap { block -> [String] in
        if case .references(let list) = block {
          return list.entries.map { "\($0.anchor)=\($0.displayAnchor)" }
        }
        return []
      }
    }
    #expect(tags(original).contains("HTTP2=HTTP/2"))
    #expect(tags(reparsed) == tags(original))
  }

  static func roundTrip(_ name: String) throws -> (original: RFCDocument, reparsed: RFCDocument) {
    let original = try RFCXMLParser.parse(try Fixtures.data(name))
    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(original).utf8))
    return (original, reparsed)
  }

  @Test func `the draft an RFC came from survives a round trip`() throws {
    let (original, reparsed) = try Self.roundTrip("rfc9842.xml")
    #expect(original.header.precedingDraft != nil)
    #expect(reparsed.header.precedingDraft == original.header.precedingDraft)
  }

  /// How each definition list in `document`, at any depth, asks to be set.
  static func definitionListShapes(_ document: RFCDocument) -> [String] {
    document.everyBlock.flattened.compactMap(\.definitionList).map {
      "\($0.isCompact ? "compact" : "normal") \($0.hangsTerms ? "hanging" : "newline")"
    }
  }

  /// RFC 9290 sets its terms on their own lines and RFC 9985 hangs them, some of
  /// both compact (#352).
  @Test(arguments: ["rfc9290.xml", "rfc9985.xml"])
  func `a definition list's newline and spacing survive a round trip`(name: String) throws {
    let (original, reparsed) = try Self.roundTrip(name)
    #expect(Set(Self.definitionListShapes(original)).count > 1)
    #expect(Self.definitionListShapes(reparsed) == Self.definitionListShapes(original))
  }

  /// The converter's documents: a legacy list that hangs no term says so, since
  /// RFCXML would otherwise hang it (RFC 21's), and a catalog says it is compact and
  /// hangs (RFC 1540's).
  @Test(arguments: [
    ("rfc21.txt", #"<dl newline="true">"#),
    ("rfc1540.txt", #"<dl newline="false" spacing="compact">"#),
  ])
  func `a converted definition list states how its terms are set`(name: String, tag: String)
    throws
  {
    let original = LegacyTextParser.parse(try Fixtures.string(name))
    let xml = RFCXMLSerializer().serialize(original)
    #expect(xml.contains(tag))
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(!Self.definitionListShapes(original).isEmpty)
    #expect(Self.definitionListShapes(reparsed) == Self.definitionListShapes(original))
  }

  @Test func `a reference annotation survives a round trip`() throws {
    let (original, reparsed) = try Self.roundTrip("rfc9842.xml")
    func annotations(_ document: RFCDocument) -> [String: [Inline]] {
      var result: [String: [Inline]] = [:]
      for block in document.allSections.flatMap(\.blocks) {
        guard case .references(let list) = block else { continue }
        for entry in list.entries where !entry.annotation.isEmpty {
          result[entry.anchor] = entry.annotation
        }
      }
      return result
    }
    #expect(annotations(original).keys.sorted() == ["FETCH", "URLPATTERN"])
    #expect(annotations(reparsed) == annotations(original))
  }

  /// "Section 4.9 of [FETCH]" keeps its section, its wording and its link (#473).
  @Test func `a citation of a section of an entry outside the series survives a round trip`()
    throws
  {
    let (original, reparsed) = try Self.roundTrip("rfc9842.xml")
    func citations(_ document: RFCDocument) -> [CrossReference] {
      document.everyCrossReference.filter {
        if case .entrySection = $0.target { return true }
        return false
      }
    }
    #expect(citations(original).count == 6)
    #expect(citations(reparsed) == citations(original))
  }

  @Test func `a paragraph indent survives a round trip`() throws {
    let (original, reparsed) = try Self.roundTrip("rfc9601.xml")
    func indents(_ document: RFCDocument) -> [Int] {
      document.nestedParagraphs.map(\.indent)
    }
    #expect(indents(original).contains(3))
    #expect(indents(reparsed) == indents(original))
  }

  @Test func `round trips legacy text`() throws {
    let parsed = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    let xml = RFCXMLSerializer(
      options: .init(
        generatorComment: "test",
        sourceURL: RFCEditorEndpoints.document(.rfc(5234), format: .text)
      )
    ).serialize(parsed)
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(reparsed.source == .xml)
    #expect(Self.signature(reparsed) == Self.signature(parsed))
    #expect(reparsed.referencedDocuments == parsed.referencedDocuments)
    #expect(reparsed.header.obsoletes == [.rfc(4234)])
    #expect(reparsed.header.category == .standardsTrack)
    #expect(xml.contains("<!-- test -->"))
    #expect(xml.contains("rel=\"alternate\""))
  }

  @Test func `canonical labels survive legacy round trip`() throws {
    let parsed = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    let xml = RFCXMLSerializer().serialize(parsed)
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))

    let xrefs = reparsed.allSections.flatMap(\.blocks).flatMap { block -> [CrossReference] in
      guard case .paragraph(let paragraph) = block else { return [] }
      return paragraph.inlines.compactMap(\.crossReference)
    }

    let canonical = try #require(
      xrefs.first { xref in
        guard case .document(let id, _, _) = xref.target, id.series == .rfc else { return false }
        return xref.isCanonicalLabel
      }, "round trip must preserve canonical RFC refs")
    #expect(
      canonical.text == nil,
      "a composed label must survive LegacyTextParser → Serializer → XMLParser composed")
    #expect(canonical.label.hasPrefix("[RFC"))

    let authored = try #require(xrefs.first { $0.text == "[US-ASCII]" })
    #expect(!authored.isCanonicalLabel, "author tag flag must survive the round trip")
  }

  /// `<references>` holds only entries, so a block beside them has nowhere to go. It
  /// is dropped, and the caller is told, not left to find it missing.
  @Test func `a dropped block comes back as a warning`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "Test"),
      sections: [
        Section(
          anchor: "references", title: "References",
          blocks: [
            .paragraph(Paragraph(text: "A note ahead of the entries.")),
            .references(ReferenceList(title: "References", entries: [])),
          ])
      ],
      source: .text
    )
    let serialization = RFCXMLSerializer().serialization(of: document)
    #expect(!serialization.xml.contains("A note ahead of the entries."))
    #expect(serialization.warnings.count == 1)
    #expect(serialization.warnings.first?.contains("references") == true)
  }

  /// `format="none"` with nothing inside shows nothing; written back without its
  /// format, it would come back composed as "Section 4.9 of [WIDGETS]" (#473).
  @Test func `an empty citation of a section of an entry stays empty`() throws {
    let xref = CrossReference(
      target: .entrySection(entry: "WIDGETS", tag: "WIDGETS", section: "4.9", url: nil), text: "")
    let document = RFCDocument(
      header: DocumentHeader(title: "Test"),
      sections: [
        Section(
          anchor: "intro", title: "Introduction",
          blocks: [.paragraph(Paragraph([.text("See "), .crossReference(xref), .text(".")]))]),
        Section(
          anchor: "references", title: "References",
          blocks: [
            .references(
              ReferenceList(
                title: "References", entries: [Reference(anchor: "WIDGETS", title: "Widgets")]))
          ]),
      ],
      source: .xml
    )
    let xml = RFCXMLSerializer().serialize(document)
    let reparsed = RFCXMLParser.crossReferences(in: try XMLTree.parse(Data(xml.utf8)))
    #expect(reparsed.map(\.label) == [""])
  }

  @Test func `unresolved document references survive as links`() throws {
    // RFC 1149 mentions no other RFC in a references section, so a synthetic one is used.
    let document = RFCDocument(
      header: DocumentHeader(
        id: .rfc(99999), title: "Test", date: PublicationDate(year: 2030, month: 1)),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "Intro",
          blocks: [
            .paragraph(
              Paragraph([
                .text("See "),
                .crossReference(
                  CrossReference(
                    target: .document(.rfc(9110), section: "4.2"), text: "Section 4.2 of RFC 9110")),
                .text(" and "),
                .link(URL(string: "https://example.com/")!, [.text("example")]),
                .text(" & <tags>."),
              ]))
          ])
      ],
      source: .text
    )
    let xml = RFCXMLSerializer().serialize(document)
    #expect(xml.contains("&amp; &lt;tags&gt;."))
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    guard case .paragraph(let paragraph)? = reparsed.sections.first?.blocks.first else {
      Issue.record("expected paragraph")
      return
    }
    #expect(
      paragraph.inlines.contains(
        .crossReference(
          CrossReference(
            target: .document(.rfc(9110), section: "4.2"), text: "Section 4.2 of RFC 9110"))))
    #expect(paragraph.plainText == "See Section 4.2 of RFC 9110 and example & <tags>.")
  }

  /// A citation is written against the entry it resolved to, not the first entry that
  /// names the same document: an erratum listed ahead of the RFC it corrects took
  /// that RFC's citations, 887 of them in 569 converted documents (#424).
  @Test func `a citation is written against the entry it resolved to`() throws {
    let document = RFCDocument(
      header: DocumentHeader(id: .rfc(99999), title: "Test"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "Intro",
          blocks: [
            .paragraph(
              Paragraph([
                .text("See "),
                .crossReference(
                  CrossReference(
                    target: .document(.rfc(7159), section: nil, entry: "Err1"), text: "[Err1]")),
                .text(", "),
                .crossReference(
                  CrossReference(
                    target: .document(.rfc(7159), section: nil, entry: "RFC7159"), text: "[RFC7159]"
                  )),
                .text(" and "),
                .crossReference(
                  CrossReference(
                    target: .document(.rfc(7159), section: nil, entry: nil), text: "RFC 7159")),
                .text("."),
              ]))
          ]),
        Section(
          anchor: "section-2", number: "2", title: "References",
          blocks: [
            .references(
              ReferenceList(
                title: "References",
                entries: [
                  Reference(
                    anchor: "Err1", title: "Erratum",
                    seriesInfo: [SeriesInfo(name: "RFC", value: "7159")]),
                  Reference(
                    anchor: "RFC7159", title: "The Format",
                    seriesInfo: [SeriesInfo(name: "RFC", value: "7159")]),
                ]))
          ]),
      ],
      source: .text
    )
    let xml = RFCXMLSerializer().serialize(document)
    #expect(xml.contains("<xref target=\"Err1\">[Err1]</xref>"), "\(xml)")
    #expect(xml.contains("<xref target=\"RFC7159\">[RFC7159]</xref>"), "\(xml)")
    // A bare mention records no entry, and goes to the one anchored under its document.
    #expect(xml.contains("<xref target=\"RFC7159\">RFC 7159</xref>"), "\(xml)")
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(
      reparsed.everyCrossReference.map(\.target) == [
        .document(.rfc(7159), section: nil, entry: "Err1"),
        .document(.rfc(7159), section: nil, entry: "RFC7159"),
        .document(.rfc(7159), section: nil, entry: "RFC7159"),
      ])
  }

  /// A citation of a `<referencegroup>`'s member records the group as its entry, and
  /// the group names another document (BCP 14, not RFC 8174): written against the
  /// group, it read back as the group's document, or as no document at all.
  @Test func `a group member's citation keeps its document through a round trip`() throws {
    for name in ["rfc9290.xml", "rfc9682.xml", "rfc9783.xml"] {
      let original = try RFCXMLParser.parse(try Fixtures.data(name))
      let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(original).utf8))
      func documents(_ document: RFCDocument) -> [DocumentID] {
        document.everyCrossReference.compactMap {
          guard case .document(let id, _, _) = $0.target else { return nil }
          return id
        }
      }
      #expect(documents(reparsed) == documents(original), "\(name)")
    }
  }

  @Test func `artwork is preserved byte for byte`() throws {
    let art = "  +---+\n  | a |  <-- & <\n  +---+"
    let document = RFCDocument(
      header: DocumentHeader(title: "Art"),
      sections: [
        Section(
          anchor: "s", number: "1", title: "S",
          blocks: [.preformatted(Preformatted(kind: .artwork, text: art))])
      ],
      source: .text
    )
    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(document).utf8))
    guard case .preformatted(let back)? = reparsed.sections.first?.blocks.first else {
      Issue.record("expected artwork")
      return
    }
    #expect(back.text == art)
  }
}

@Suite("RFCXML serializer: corpus findings")
struct RFCXMLSerializerCorpusFindingsTests {
  @Test func `references subsection under mixed parent survives`() throws {
    // "10. References" whose 10.1 parsed to plain prose (no entries) and 10.2 to entries.
    let document = RFCDocument(
      header: DocumentHeader(id: .rfc(7019), title: "T"),
      sections: [
        Section(
          anchor: "section-10", number: "10", title: "References",
          subsections: [
            Section(
              anchor: "section-10.1", number: "10.1", title: "Normative References",
              blocks: [.paragraph(Paragraph(text: "None."))]),
            Section(
              anchor: "section-10.2", number: "10.2", title: "Informative References",
              blocks: [
                .references(
                  ReferenceList(
                    title: "Informative References",
                    entries: [
                      Reference(
                        anchor: "RFC2119", title: "Key words",
                        seriesInfo: [SeriesInfo(name: "RFC", value: "2119")])
                    ]))
              ]),
          ])
      ],
      source: .text
    )
    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(document).utf8))
    #expect(reparsed.allSections.map(\.number) == ["10", "10.1", "10.2"])
    #expect(reparsed.referencedDocuments == [.rfc(2119)])
  }

  /// RFCXML requires `author+` in every `<front>`, the document's and each reference's.
  /// A legacy reference never has structured authors, and a header can name none --
  /// RFC 1 folds its author into the title -- which failed the schema in 7,566 documents.
  @Test func `every front has an author even when none is known`() throws {
    for fixture in ["rfc1.txt", "rfc5234.txt"] {
      let parsed = LegacyTextParser.parse(try Fixtures.string(fixture))
      let xml = RFCXMLSerializer().serialize(parsed)
      let authors = { (document: RFCDocument) in
        document.allSections.flatMap(\.blocks).flatMap { block -> [[Author]] in
          guard case .references(let list) = block else { return [] }
          return list.entries.map(\.authors)
        }
      }
      let fronts = xml.components(separatedBy: "<front>").dropFirst().map {
        $0.components(separatedBy: "</front>")[0]
      }
      #expect(
        fronts.count == 1 + authors(parsed).count,
        "\(fixture): the document's front and one per entry")
      #expect(fronts.allSatisfy { $0.contains("<author") }, "\(fixture)")

      // An empty `<author/>` says no author is given, and must not read back as one.
      let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
      #expect(reparsed.header.authors.map(\.name) == parsed.header.authors.map(\.name))
      #expect(authors(reparsed) == authors(parsed))
    }
    // The two cases this pins: a header naming no author, and entries naming none.
    #expect(LegacyTextParser.parse(try Fixtures.string("rfc1.txt")).header.authors.isEmpty)
    #expect(
      LegacyTextParser.parse(try Fixtures.string("rfc5234.txt")).allSections.contains { section in
        section.blocks.contains {
          if case .references(let list) = $0 {
            list.entries.contains { $0.authors.isEmpty }
          } else {
            false
          }
        }
      })
  }

  /// An appendix that is a bibliography, RFC 2049's `Appendix C -- References`, is
  /// written as `<references>`, and its `pn` names it an appendix. Read back, it was a
  /// numbered section that was not one (#201).
  @Test func `a references appendix round trips as an appendix`() throws {
    let parsed = LegacyTextParser.parse(try Fixtures.string("rfc2049.txt"))
    let appendix = try #require(parsed.section(anchor: "appendix-C"))
    #expect(appendix.isAppendix)
    #expect(appendix.blocks.contains { if case .references = $0 { true } else { false } })
    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(parsed).utf8))
    let readBack = try #require(reparsed.section(anchor: "appendix-C"))
    #expect(readBack.number == "C")
    #expect(readBack.isAppendix)
  }

  /// `anchor` and `pn` are both `xsd:ID`, so `<section anchor="section-1" pn="section-1">`
  /// declares one ID twice, which failed the schema in 7,419 documents. A synthesized
  /// anchor is the part number for every numbered section, so it is written once, as the
  /// `pn` the published series always carries, and read back from there.
  @Test func `an anchor that is the part number is written once`() throws {
    let parsed = LegacyTextParser.parse(try Fixtures.string("rfc5234.txt"))
    #expect(parsed.allSections.contains { $0.anchor == "section-1" })
    let xml = RFCXMLSerializer().serialize(parsed)
    // Per tag, whichever order the two attributes come in.
    let repeated = xml.matches(of: #/<[a-z]+\s[^>]*>/#).compactMap { tag -> String? in
      let anchor = tag.output.firstMatch(of: #/\banchor="([^"]*)"/#)?.1
      return anchor != nil && anchor == tag.output.firstMatch(of: #/\bpn="([^"]*)"/#)?.1
        ? String(tag.output) : nil
    }
    #expect(repeated.isEmpty, "\(repeated)")
    // The anchor reads back from the `pn`, and the number and kind the `pn` also carries
    // still read back from it.
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(reparsed.allSections.map(\.anchor) == parsed.allSections.map(\.anchor))
    #expect(reparsed.allSections.map(\.number) == parsed.allSections.map(\.number))
    #expect(reparsed.allSections.map(\.isAppendix) == parsed.allSections.map(\.isAppendix))
  }

  @Test func `control characters never reach the XML`() throws {
    let document = RFCDocument(
      header: DocumentHeader(title: "T\u{00}itle\u{1B}"),
      sections: [
        Section(
          anchor: "s", number: "1", title: "S", blocks: [.paragraph(Paragraph(text: "a\u{01}b\tc"))]
        )
      ],
      source: .text
    )
    let xml = RFCXMLSerializer().serialize(document)
    let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(reparsed.header.title == "Title")
    guard case .paragraph(let paragraph)? = reparsed.sections.first?.blocks.first else {
      Issue.record("expected paragraph")
      return
    }
    #expect(
      paragraph.plainText == "ab c", "tab survives escaping and is collapsed like other whitespace")
  }
}
