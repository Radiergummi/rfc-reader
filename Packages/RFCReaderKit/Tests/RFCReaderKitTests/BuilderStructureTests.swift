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
                #expect(built.text.string.contains(paragraph.plainText), "missing paragraph: \(paragraph.plainText.prefix(60))")
            }
        }
    }

    @Test func theLegacyPathBuildsToo() throws {
        let built = DocumentTextBuilder.build(try Fixtures.rfc2119(), style: style)
        #expect(built.text.length > 0)
        #expect(!built.anchors.entries.isEmpty)
    }
}
