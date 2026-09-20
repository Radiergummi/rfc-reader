import RFCKit
import SwiftUI

/// Renders a run of inlines as one selectable `Text` built from an `AttributedString`.
///
/// Cross references become links with private URL schemes, which `DocumentView`
/// intercepts through the `openURL` environment. That keeps the text selectable and
/// lets the system draw links, while navigation stays entirely in-app.
struct InlineText: View {
    static let anchorScheme = "rfc-anchor"

    let inlines: [Inline]

    init(_ inlines: [Inline]) {
        self.inlines = inlines
    }

    var body: some View {
        Text(Self.attributedString(inlines))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func attributedString(_ inlines: [Inline]) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            result.append(attributed(inline))
        }
        return result
    }

    private static func attributed(_ inline: Inline) -> AttributedString {
        switch inline {
        case .text(let text):
            return AttributedString(text)
        case .emphasis(let inner):
            var value = attributedString(inner)
            value.inlinePresentationIntent = .emphasized
            return value
        case .strong(let inner):
            var value = attributedString(inner)
            value.inlinePresentationIntent = .stronglyEmphasized
            return value
        case .code(let text):
            var value = AttributedString(text)
            value.inlinePresentationIntent = .code
            return value
        case .superscript(let text):
            var value = AttributedString(text)
            value.baselineOffset = 5
            return value
        case .subscript(let text):
            var value = AttributedString(text)
            value.baselineOffset = -3
            return value
        case .link(let url, let inner):
            var value = attributedString(inner)
            value.link = url
            return value
        case .crossReference(let xref):
            var value = AttributedString(label(for: xref))
            value.link = url(for: xref)
            return value
        case .lineBreak:
            return AttributedString("\n")
        }
    }

    private static func label(for xref: CrossReference) -> String {
        if let text = xref.text { return text }
        switch xref.target {
        case .anchor(let anchor): return anchor
        case .document(let id, let section):
            return section.map { "Section \($0) of \(id.displayName)" } ?? "[\(id.description)]"
        }
    }

    private static func url(for xref: CrossReference) -> URL? {
        switch xref.target {
        case .document(let id, let section):
            return RFCLink(id: id, section: section).appURL
        case .anchor(let anchor):
            let encoded = anchor.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? anchor
            return URL(string: "\(anchorScheme):\(encoded)")
        }
    }
}
