import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

@Suite("Builder: document structure")
@MainActor
struct BuilderStructureTests {
    private let style = ReadingStyle()

    @Test func everySectionAnchorIsIndexed() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        for section in document.allSections {
            #expect(built.anchors.offset(of: section.anchor) != nil, "missing anchor \(section.anchor)")
        }
    }

    @Test func eachSectionAnchorPointsAtItsHeading() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        let text = built.text.string as NSString
        for section in document.allSections {
            let offset = try #require(built.anchors.offset(of: section.anchor))
            let length = min((section.displayTitle as NSString).length, text.length - offset)
            let slice = text.substring(with: NSRange(location: offset, length: length))
            #expect(slice == section.displayTitle, "anchor \(section.anchor) does not point at its heading")
        }
    }

    @Test func theBuilderRecordsAnchorsInDocumentOrder() throws {
        let builder = DocumentTextBuilder(style: style)
        builder.appendDocument(try Fixtures.rfc8999())
        let offsets = builder.entries.map(\.offset)
        #expect(offsets == offsets.sorted(), "mark() must be called in document order, before the run it names")
    }

    @Test func anchorOffsetsAreInsideTheString() throws {
        let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: style)
        for entry in built.anchors.entries {
            #expect(entry.offset >= 0 && entry.offset <= built.text.length)
        }
    }

    @Test func headingsCarryTheirAnchorForTheVoiceOverRotor() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        let first = try #require(document.sections.first)
        let offset = try #require(built.anchors.offset(of: first.anchor))
        #expect(built.text.attribute(.rfcAnchor, at: offset, effectiveRange: nil) as? String == first.anchor)
    }

    @Test func theAbstractComesBeforeTheFirstSection() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        let abstract = document.header.abstract.compactMap { block -> String? in
            guard case .paragraph(let paragraph) = block else { return nil }
            return paragraph.plainText
        }.first
        let abstractText = try #require(abstract)
        let abstractRange = built.text.string.range(of: abstractText)
        #expect(abstractRange != nil, "the abstract is in the storage, not in the header view")

        let firstSection = try #require(document.sections.first)
        let sectionOffset = try #require(built.anchors.offset(of: firstSection.anchor))
        let abstractOffset = built.text.string.distance(from: built.text.string.startIndex, to: try #require(abstractRange).lowerBound)
        #expect(abstractOffset < sectionOffset)
    }

    /// Neither parser keeps "Abstract" as a block, and the reader's header view no
    /// longer draws it, so the builder is the only thing left that can.
    @Test func theAbstractIsLabelled() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        let text = built.text.string
        let label = try #require(text.range(of: "Abstract"), "the abstract has no heading")
        #expect(text.distance(from: text.startIndex, to: label.lowerBound) == 0, "the heading is the first thing in the storage")

        let firstParagraph = try #require(document.header.abstract.compactMap { block -> String? in
            guard case .paragraph(let paragraph) = block else { return nil }
            return paragraph.plainText
        }.first)
        let prose = try #require(text.range(of: firstParagraph))
        #expect(label.upperBound <= prose.lowerBound, "the heading must precede the abstract's first paragraph")

        let offset = text.distance(from: text.startIndex, to: label.lowerBound)
        #expect(built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont == style.headingFont(depth: 1))
        #expect(built.anchors.offset(of: "Abstract") == nil, "the heading carries no anchor")
    }

    @Test func aDocumentWithNoAbstractGetsNoHeading() throws {
        var document = try Fixtures.rfc8999()
        document.header.abstract = []
        let built = DocumentTextBuilder.build(document, style: style)
        #expect(!built.text.string.hasPrefix("Abstract"))
    }

    @Test func headingTextIsTheSectionDisplayTitle() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        for section in document.allSections {
            #expect(built.text.string.contains(section.displayTitle), "missing heading \(section.displayTitle)")
        }
    }

    @Test func noParagraphTextIsLost() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        for section in document.allSections {
            for case .paragraph(let paragraph) in section.blocks where !paragraph.plainText.isEmpty {
                let projection = Self.renderedLabel(paragraph.inlines)
                #expect(built.text.string.contains(projection), "missing paragraph: \(paragraph.plainText.prefix(60))")
            }
        }
    }

    /// Mirrors what the builder renders, computed independently from the model
    /// rather than by calling the builder's own `bracketedRange(in:)`, so this
    /// stays a check on the builder rather than a restatement of it. A canonical
    /// cross reference's label loses its outer brackets and gains the chip's
    /// leading `U+FFFC` symbol in their place; everything else is `plainText`.
    private static func renderedLabel(_ inlines: [Inline]) -> String {
        inlines.map { inline -> String in
            switch inline {
            case .text(let text), .code(let text), .superscript(let text), .subscript(let text):
                return text
            case .emphasis(let inner), .strong(let inner), .link(_, let inner):
                return renderedLabel(inner)
            case .crossReference(let xref):
                let label = xref.text ?? {
                    switch xref.target {
                    case .anchor(let anchor): return anchor
                    case .document(let id, let section):
                        return section.map { "Section \($0) of \(id.displayName)" } ?? "[\(id.description)]"
                    }
                }()
                guard xref.isCanonicalLabel,
                      let open = label.firstIndex(of: "["),
                      let close = label.lastIndex(of: "]"),
                      open < close else {
                    return label
                }
                let before = label[label.startIndex..<open]
                let inner = label[label.index(after: open)..<close]
                let after = label[label.index(after: close)...]
                return "\(before)\u{FFFC}\(inner)\(after)"
            case .lineBreak:
                return "\n"
            }
        }.joined()
    }

    @Test func theLegacyPathBuildsToo() throws {
        let built = DocumentTextBuilder.build(try Fixtures.rfc2119(), style: style)
        #expect(built.text.length > 0)
        #expect(!built.anchors.entries.isEmpty)
    }
}
