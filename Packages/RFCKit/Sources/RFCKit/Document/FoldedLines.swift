/// Lines an RFC folded to fit a figure, per RFC 8792, and the text they fold.
///
/// A plain-text RFC holds at most 69 columns of artwork or code, and RFC 8792 is how
/// a longer line gets in: break it with a trailing `\`, and say so in a header at the
/// top of the block. That header tells a person what happened; a machine handed the
/// folded text has no idea, so copied XML is invalid, a JSON string is broken and an
/// HTTP header is split mid-token (issue #64).
///
/// Unfolding is exactly specified and needs nothing but the block's own text, so it
/// lives here beside the model rather than in the view. The legacy series predates
/// RFC 8792 (2020), so in practice only RFCXML documents carry folded blocks.
public enum FoldedLines {
    /// The two strategies RFC 8792 defines, named by the header that announces them.
    public enum Strategy: Sendable, Equatable {
        /// `'\'` (RFC 8792 §7): a line ending in a backslash continues on the next,
        /// and the continuation's leading spaces are indentation, not content.
        case singleBackslash
        /// `'\\'` (RFC 8792 §8): the continuation also begins with a backslash, so
        /// the spaces before it are indentation and any after it are content. This
        /// is the strategy for text whose own lines end in a backslash.
        case doubleBackslash
    }

    /// The strategy `text` announces, or nil when it is not a folded block.
    public static func strategy(of text: String) -> Strategy? {
        header(in: lines(of: text))?.strategy
    }

    /// `text` with its folding undone, or nil when it does not announce RFC 8792
    /// folding — including when it names a strategy the RFC does not define.
    ///
    /// The header and the blank line that belongs to it go too: they describe the
    /// folding, and once it is undone they describe something that is not there.
    public static func unfold(_ text: String) -> String? {
        let lines = lines(of: text)
        guard let header = header(in: lines) else { return nil }

        var body = lines[(header.index + 1)...]
        if let first = body.first, first.allSatisfy(\.isWhitespace) {
            body = body.dropFirst()
        }

        var unfolded: [Substring] = []
        var next = body.startIndex
        while next < body.endIndex {
            var line = body[next]
            next += 1
            folding: while line.hasSuffix("\\"), next < body.endIndex {
                // Only spaces: RFC 8792 indents a continuation with spaces, and a tab
                // at the start of one is content the author put there.
                var continuation = body[next].drop { $0 == " " }
                if header.strategy == .doubleBackslash {
                    // A backslash that ends a line with no marked continuation after
                    // it is the author's own, not a fold.
                    guard continuation.hasPrefix("\\") else { break folding }
                    continuation = continuation.dropFirst()
                }
                line = line.dropLast() + continuation
                next += 1
            }
            unfolded.append(line)
        }
        return unfolded.joined(separator: "\n")
    }

    private static func lines(of text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// The header must open the block: the first line that is not blank. A NOTE
    /// further down is the block talking about folding, not announcing it.
    ///
    /// RFC 8792 centres the note between runs of `=`, and `rfcfold` pads it to the
    /// block's width, so the padding is taken off at both ends and not measured.
    private static func header(in lines: [Substring]) -> (index: Int, strategy: Strategy)? {
        guard let index = lines.firstIndex(where: { !$0.allSatisfy(\.isWhitespace) }) else { return nil }
        var note = lines[index].trimmingWhitespace()
        while note.first == "=" { note.removeFirst() }
        while note.last == "=" { note.removeLast() }
        switch note.trimmingWhitespace() {
        case #"NOTE: '\' line wrapping per RFC 8792"#: return (index, .singleBackslash)
        case #"NOTE: '\\' line wrapping per RFC 8792"#: return (index, .doubleBackslash)
        default: return nil
        }
    }
}

extension Preformatted {
    /// The block as its author wrote it: unfolded where RFC 8792 folded it to fit the
    /// plain-text page, and `text` itself everywhere else. What a copy should yield.
    public var unfoldedText: String {
        FoldedLines.unfold(text) ?? text
    }
}

private extension Substring {
    func trimmingWhitespace() -> Substring {
        var trimmed = self
        while trimmed.first?.isWhitespace == true { trimmed.removeFirst() }
        while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
        return trimmed
    }
}
