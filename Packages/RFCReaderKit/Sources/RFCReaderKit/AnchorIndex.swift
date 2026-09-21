import Foundation

/// Every anchor in a built document, sorted by character offset.
///
/// Anchors are the reader's only stable handle on a position: deep links, the table
/// of contents and reading positions all key off them, and the index is what turns
/// one into a text location and back.
public struct AnchorIndex: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let anchor: String
        public let offset: Int
        /// True when the anchor names a `Section`, which the builder knows and
        /// nothing downstream can tell by looking. See `DocumentTextBuilder.mark`.
        public let isSection: Bool

        public init(anchor: String, offset: Int, isSection: Bool = false) {
            self.anchor = anchor
            self.offset = offset
            self.isSection = isSection
        }
    }

    public let entries: [Entry]
    private let offsets: [String: Int]

    public init(_ entries: [Entry]) {
        let sorted = entries.sorted { $0.offset < $1.offset }
        self.entries = sorted
        self.offsets = Dictionary(sorted.map { ($0.anchor, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }

    /// Just the section anchors, as an index of their own: what section tracking
    /// hit-tests against.
    public var sections: AnchorIndex {
        AnchorIndex(entries.filter(\.isSection))
    }

    public func offset(of anchor: String) -> Int? {
        offsets[anchor]
    }

    /// The anchor covering `offset`: the last entry at or before it, or nil if the
    /// offset falls ahead of the first anchor.
    public func anchor(at offset: Int) -> String? {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if entries[middle].offset <= offset { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? entries[low - 1].anchor : nil
    }
}
