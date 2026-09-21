import Foundation
import RFCKit

/// Turns an `RFCDocument` into one attributed string plus an anchor index.
///
/// Pure: no view, no state that outlives a build, no I/O. `@MainActor` because
/// `NSAttributedString` is not `Sendable` and the result goes straight into a text
/// view; nothing here needs to run anywhere else.
@MainActor
public final class DocumentTextBuilder {
    /// The private URL scheme an in-document anchor link uses. Moved here from
    /// `InlineText`, which this replaces.
    public static let anchorScheme = "rfc-anchor"

    let style: ReadingStyle
    let output = NSMutableAttributedString()
    var entries: [AnchorIndex.Entry] = []

    init(style: ReadingStyle) {
        self.style = style
    }

    public static func build(_ document: RFCDocument, style: ReadingStyle) -> BuiltDocument {
        let builder = DocumentTextBuilder(style: style)
        builder.appendDocument(document)
        return BuiltDocument(text: builder.output, anchors: AnchorIndex(builder.entries))
    }

    /// Task 4 replaces this with real section and paragraph emission.
    func appendDocument(_ document: RFCDocument) {}

    /// Records where an anchor lands. Called immediately before the run it names.
    func mark(_ anchor: String?) {
        guard let anchor, !anchor.isEmpty else { return }
        entries.append(AnchorIndex.Entry(anchor: anchor, offset: output.length))
    }

    func append(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
        output.append(NSAttributedString(string: string, attributes: attributes))
    }
}
