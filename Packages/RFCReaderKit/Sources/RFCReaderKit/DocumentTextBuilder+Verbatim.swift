import Foundation
import RFCKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension DocumentTextBuilder {
    /// Artwork and source code go into the storage verbatim, non-wrapping, in a
    /// monospace font scaled so the widest line fits the measure.
    ///
    /// Scaling replaces the horizontal scroll view the old `PreformattedView` had.
    /// Across the 8,457-document converted corpus, 97.8% of artwork blocks are 69
    /// columns or narrower and 99.998% are 79 or narrower; the widest line anywhere
    /// is 129 columns, in RFC 2124.
    func appendVerbatim(_ content: Preformatted, indent: CGFloat) {
        mark(content.anchor)
        let scale = monospaceScale(for: content.text, indent: indent)
        let box = VerbatimBox(content)

        // Before the label, so the label is inside the card it names.
        let start = output.length
        if content.kind == .sourceCode, let type = content.type, !type.isEmpty {
            append(type.uppercased() + "\n", [
                .font: style.captionFont,
                .foregroundColor: RFCColors.secondaryLabel,
                .rfcVerbatim: box,
                .paragraphStyle: paragraphStyle(indent: indent, spacingAfter: 0),
            ])
        }

        let body = content.text.hasSuffix("\n") ? content.text : content.text + "\n"
        append(body, [
            .font: style.monospacedFont(scale: scale),
            .foregroundColor: bodyColour,
            .rfcVerbatim: box,
            .paragraphStyle: paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing, wraps: false),
        ])
        decorate(from: start, with: .artwork)
    }

    /// 1 when the block already fits, otherwise the factor that makes its widest line
    /// fit what the measure leaves after `indent`.
    func monospaceScale(for text: String, indent: CGFloat = 0) -> CGFloat {
        let columns = text.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0
        guard columns > 0, monospaceAdvance > 0 else { return 1 }
        return min(1, max(0, style.measure - indent) / (CGFloat(columns) * monospaceAdvance))
    }
}
