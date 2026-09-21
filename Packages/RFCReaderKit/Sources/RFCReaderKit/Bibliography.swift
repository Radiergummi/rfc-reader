import Foundation
import RFCKit

/// One bibliography heading — "Normative References" — and its entries.
///
/// The reader shows these in a panel rather than in the text: every citation in the
/// prose already links straight to the document it names, so the section was several
/// screens of rows nobody reads in order. `DocumentTextBuilder` skips those sections
/// when building the body (`holdsOnlyReferences`); this is the other half of that
/// decision, and it lives here beside it rather than in a view, so both halves are
/// under test.
public struct ReferenceGroup: Identifiable, Sendable {
    public let title: String
    public let entries: [Reference]

    public var id: String { title }

    public init(title: String, entries: [Reference]) {
        self.title = title
        self.entries = entries
    }

    /// Every bibliography in the document, in document order, skipping empty ones.
    /// Read from the model rather than the built text, because the builder
    /// deliberately leaves these out of it.
    public static func groups(in document: RFCDocument) -> [ReferenceGroup] {
        document.allSections.flatMap { section in
            section.blocks.compactMap { block in
                guard case .references(let list) = block, !list.entries.isEmpty else { return nil }
                return ReferenceGroup(title: list.title, entries: list.entries)
            }
        }
    }
}
