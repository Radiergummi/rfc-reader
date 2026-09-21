import Foundation
import RFCKit

extension DocumentTextBuilder {
    /// Renders a run of inlines. `base` carries the font and colour of the context
    /// the run sits in — body prose, a heading, a table cell — and each inline
    /// layers its own attributes on top.
    static func inlineRuns(
        _ inlines: [Inline],
        style: ReadingStyle,
        base: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for inline in inlines {
            result.append(run(inline, style: style, base: base))
        }
        return result
    }

    private static func run(
        _ inline: Inline,
        style: ReadingStyle,
        base: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        switch inline {
        case .text(let text):
            return NSAttributedString(string: text, attributes: base)

        case .emphasis(let inner):
            return inlineRuns(inner, style: style, base: base.adding(trait: RFCTraits.italic, style: style))

        case .strong(let inner):
            return inlineRuns(inner, style: style, base: base.adding(trait: RFCTraits.bold, style: style))

        case .code(let text):
            var attributes = base
            attributes[.font] = style.codeFont
            return NSAttributedString(string: text, attributes: attributes)

        case .superscript(let text):
            var attributes = base
            attributes[.baselineOffset] = style.bodySize * 0.3
            attributes[.font] = PlatformFont.systemFont(ofSize: style.bodySize * 0.75)
            return NSAttributedString(string: text, attributes: attributes)

        case .subscript(let text):
            var attributes = base
            attributes[.baselineOffset] = -style.bodySize * 0.18
            attributes[.font] = PlatformFont.systemFont(ofSize: style.bodySize * 0.75)
            return NSAttributedString(string: text, attributes: attributes)

        case .link(let url, let inner):
            let result = NSMutableAttributedString(attributedString: inlineRuns(inner, style: style, base: base))
            result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length))
            return result

        case .crossReference(let xref):
            var attributes = base
            attributes[.rfcReference] = ReferenceBox(xref)
            if let url = url(for: xref) { attributes[.link] = url }
            return NSAttributedString(string: label(for: xref), attributes: attributes)

        case .lineBreak:
            return NSAttributedString(string: "\n", attributes: base)
        }
    }

    /// The label a cross reference shows. Mirrors `[Inline].plainText` exactly, so a
    /// copied selection and the rendered text never disagree.
    static func label(for xref: CrossReference) -> String {
        if let text = xref.text { return text }
        switch xref.target {
        case .anchor(let anchor):
            return anchor
        case .document(let id, let section):
            return section.map { "Section \($0) of \(id.displayName)" } ?? "[\(id.description)]"
        }
    }

    static func url(for xref: CrossReference) -> URL? {
        switch xref.target {
        case .document(let id, let section):
            return RFCLink(id: id, section: section).appURL
        case .anchor(let anchor):
            let encoded = anchor.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? anchor
            return URL(string: "\(anchorScheme):\(encoded)")
        }
    }
}

extension [NSAttributedString.Key: Any] {
    /// Adds a symbolic trait to whatever font this context already carries.
    func adding(trait: PlatformFontDescriptor.SymbolicTraits, style: ReadingStyle) -> Self {
        var result = self
        let current = (self[.font] as? PlatformFont) ?? style.bodyFont
        let descriptor = current.fontDescriptor
        #if canImport(UIKit)
        if let traited = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(trait)) {
            result[.font] = PlatformFont(descriptor: traited, size: current.pointSize)
        }
        #else
        let traited = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(trait))
        result[.font] = PlatformFont(descriptor: traited, size: current.pointSize) ?? current
        #endif
        return result
    }
}
