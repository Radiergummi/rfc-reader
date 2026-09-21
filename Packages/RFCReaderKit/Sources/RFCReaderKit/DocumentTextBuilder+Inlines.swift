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
    func inlineRuns(_ inlines: [Inline], base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for inline in inlines {
            result.append(run(inline, base: base))
        }
        return result
    }

    private func run(_ inline: Inline, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        switch inline {
        case .text(let text):
            return NSAttributedString(string: text, attributes: base)

        case .emphasis(let inner):
            return inlineRuns(inner, base: base.adding(trait: RFCTraits.italic, style: style))

        case .strong(let inner):
            return inlineRuns(inner, base: base.adding(trait: RFCTraits.bold, style: style))

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
            let result = NSMutableAttributedString(attributedString: inlineRuns(inner, base: base))
            result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length))
            return result

        case .crossReference(let xref):
            var attributes = base
            attributes[.rfcReference] = ReferenceBox(xref)
            if let url = url(for: xref) { attributes[.link] = url }
            // What the reference reads as, and which part of it is a chip, are the
            // model's to say — `CrossReference.display`, which `plainText` answers
            // from too, so the screen and a copied selection cannot disagree.
            let display = xref.display
            guard let chip = display.chip else {
                return NSAttributedString(string: display.text, attributes: attributes)
            }
            let result = NSMutableAttributedString()
            result.append(NSAttributedString(string: String(display.text[display.text.startIndex..<chip.lowerBound]), attributes: attributes))
            result.append(chipRun(String(display.text[chip]), attributes: attributes))
            result.append(NSAttributedString(string: String(display.text[chip.upperBound...]), attributes: attributes))
            return result

        case .lineBreak:
            return NSAttributedString(string: "\n", attributes: base)
        }
    }

    /// The only constructor of a `.rfcChip` run, and the only place `nextChipID` is
    /// touched: the symbol, the joiner and the id are one recipe, and a second copy
    /// of it is how the two chip shapes (`[RFC9110]` and `Section 4.2 of
    /// [RFC9110]`) drift apart.
    ///
    /// The id is a serial number, not `true`: `NSAttributedString` merges contiguous
    /// runs whose attribute values compare equal, and two adjacent chips
    /// (`[RFC9110][RFC9111]`) sharing one effective range would draw as a single
    /// rounded rect. Each chip therefore carries a value no other chip has.
    private func chipRun(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var chip = attributes
        nextChipID += 1
        chip[.rfcChip] = nextChipID
        let result = NSMutableAttributedString()
        if let symbol = chipSymbolRun(attributes: chip) {
            result.append(symbol)
            // U+2060 WORD JOINER: an attachment character is its own grapheme and
            // offers a line-break opportunity on either side, so in a narrow column
            // the chip's icon wrapped onto the line above its own label.
            result.append(NSAttributedString(string: "\u{2060}", attributes: chip))
        }
        result.append(NSAttributedString(string: text, attributes: chip))
        return result
    }

    /// The leading `doc.text` glyph that rides inside the chip's own run, so it
    /// falls inside both the drawn background and the hit region. `NSTextAttachment
    /// (image:)` sits the image's bottom edge on the text baseline by default,
    /// which reads low against the words around it, so the symbol is drawn at the
    /// run's own font size and its bounds are centred on that font's cap height.
    private func chipSymbolRun(attributes: [NSAttributedString.Key: Any]) -> NSAttributedString? {
        let font = (attributes[.font] as? PlatformFont) ?? PlatformFont.systemFont(ofSize: 17)
        guard let symbol = chipSymbol(pointSize: font.pointSize) else { return nil }
        // AppKit's `NSTextAttachment` has no `init(image:)`; `image` is assigned
        // after the default initializer instead, which UIKit also accepts.
        let attachment = NSTextAttachment()
        attachment.image = symbol
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height)
        let run = NSMutableAttributedString(attachment: attachment)
        run.addAttributes(attributes, range: NSRange(location: 0, length: run.length))
        return run
    }

    /// Rendering the symbol is the expensive part and depends only on the point size,
    /// of which a build sees one or two — but there is a chip per cross reference, and
    /// RFCs are full of them. The attachment itself stays per run.
    private func chipSymbol(pointSize: CGFloat) -> PlatformImage? {
        if let cached = chipSymbols[pointSize] { return cached }
        guard let symbol = PlatformImage.symbol(named: "doc.text", pointSize: pointSize) else { return nil }
        chipSymbols[pointSize] = symbol
        return symbol
    }

    /// The other half of `url(for:)`'s anchor case: nil when the URL is not one of
    /// ours. Kept beside the encoder, because a scheme whose two halves live in
    /// different modules is one percent-encoding rule away from silently failing on
    /// an anchor containing `?` or `#`.
    public static func anchor(from url: URL) -> String? {
        guard url.scheme == anchorScheme else { return nil }
        let encoded = url.absoluteString.dropFirst(anchorScheme.count + 1)
        return String(encoded).removingPercentEncoding ?? String(encoded)
    }

    func url(for xref: CrossReference) -> URL? {
        switch xref.target {
        case .document(let id, let section):
            return RFCLink(id: id, section: section).appURL
        case .anchor(let anchor):
            let encoded = anchor.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? anchor
            return URL(string: "\(Self.anchorScheme):\(encoded)")
        }
    }
}

extension [NSAttributedString.Key: Any] {
    /// Adds a symbolic trait to whatever font this context already carries.
    func adding(trait: PlatformFontDescriptor.SymbolicTraits, style: ReadingStyle) -> Self {
        var result = self
        let current = (self[.font] as? PlatformFont) ?? style.bodyFont
        result[.font] = current.adding(traits: trait)
        return result
    }
}
