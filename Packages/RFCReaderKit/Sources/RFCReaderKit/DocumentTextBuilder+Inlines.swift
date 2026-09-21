import Foundation
import RFCKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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
            let label = label(for: xref)
            guard xref.isCanonicalLabel, let bracketed = bracketedRange(in: label) else {
                return NSAttributedString(string: label, attributes: attributes)
            }
            // What isCanonicalLabel licenses is replacing a canonical series id's
            // brackets with a chip, not a claim about who authored them: the legacy
            // parser's brackets are literally in the source text. The rest of the
            // phrase stays plain link text.
            let result = NSMutableAttributedString()
            result.append(NSAttributedString(string: String(label[label.startIndex..<bracketed.lowerBound]), attributes: attributes))
            var chip = attributes
            chip[.rfcChip] = true
            if let symbolRun = chipSymbolRun(attributes: chip) {
                result.append(symbolRun)
            }
            let inner = label.index(after: bracketed.lowerBound)..<label.index(before: bracketed.upperBound)
            result.append(NSAttributedString(string: String(label[inner]), attributes: chip))
            result.append(NSAttributedString(string: String(label[bracketed.upperBound...]), attributes: attributes))
            return result

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

    /// The `[...]` span in a label, brackets included, or nil if there is none.
    static func bracketedRange(in label: String) -> Range<String.Index>? {
        guard let open = label.firstIndex(of: "["), let close = label.lastIndex(of: "]"), open < close else { return nil }
        return open..<label.index(after: close)
    }

    /// The leading `doc.text` glyph that rides inside the chip's own run, so it
    /// falls inside both the drawn background and the hit region. `NSTextAttachment
    /// (image:)` sits the image's bottom edge on the text baseline by default,
    /// which reads low against the words around it, so the symbol is drawn at the
    /// run's own font size and its bounds are centred on that font's cap height.
    private static func chipSymbolRun(attributes: [NSAttributedString.Key: Any]) -> NSAttributedString? {
        let font = (attributes[.font] as? PlatformFont) ?? PlatformFont.systemFont(ofSize: 17)
        let configuration = PlatformImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
        let attachment = NSTextAttachment()
        #if canImport(UIKit)
        guard let symbol = PlatformImage(systemName: "doc.text")?.withConfiguration(configuration) else { return nil }
        attachment.image = symbol
        #else
        // AppKit's `NSTextAttachment` has no `init(image:)`; `image` is assigned
        // after the default initializer instead.
        guard let symbol = PlatformImage(systemName: "doc.text")?.withSymbolConfiguration(configuration) else { return nil }
        attachment.image = symbol
        #endif
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height)
        let run = NSMutableAttributedString(attachment: attachment)
        run.addAttributes(attributes, range: NSRange(location: 0, length: run.length))
        return run
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
