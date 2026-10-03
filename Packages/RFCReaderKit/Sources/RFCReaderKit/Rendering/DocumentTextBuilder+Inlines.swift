import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension DocumentTextBuilder {
  /// Renders a run of inlines. `base` carries the font and color of the context
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
      var attributes = base
      attributes[.font] = style.strongFont(matching: font(in: base))
      return inlineRuns(inner, base: attributes)

    // Code and scripts are made from the font in effect, not from the body's: code
    // in a heading dropped to body size, and a superscript in strong text lost its
    // weight (#154). In body prose these are the sizes they always were.
    case .code(let text):
      var attributes = base
      attributes[.font] = style.codeFont(matching: font(in: base))
      return NSAttributedString(string: text, attributes: attributes)

    case .superscript(let text):
      var attributes = base
      let current = font(in: base)
      attributes[.baselineOffset] = current.pointSize * 0.3
      attributes[.font] = current.resized(to: current.pointSize * 0.75)
      return NSAttributedString(string: text, attributes: attributes)

    case .subscript(let text):
      var attributes = base
      let current = font(in: base)
      attributes[.baselineOffset] = -current.pointSize * 0.18
      attributes[.font] = current.resized(to: current.pointSize * 0.75)
      return NSAttributedString(string: text, attributes: attributes)

    case .link(let url, let inner):
      let result = NSMutableAttributedString(attributedString: inlineRuns(inner, base: base))
      result.addAttributes(linkAttributes(url), range: NSRange(location: 0, length: result.length))
      #if !canImport(UIKit)
        // Explicit, because the reader turns `displaysLinkToolTips` off: the
        // implicit tooltip gave every reference its raw `rfc://` URL. Only an
        // external link carries one — its URL is the one place its destination
        // can be read before it is followed.
        result.addAttribute(
          .toolTip, value: url.absoluteString, range: NSRange(location: 0, length: result.length))
      #endif
      return result

    case .crossReference(let xref):
      var attributes = base
      attributes[.rfcReference] = ReferenceBox(xref)
      if let url = url(for: xref) {
        attributes.merge(linkAttributes(url)) { _, link in link }
      }
      // What the reference reads as, and which part of it is a chip, are the
      // model's to say — `CrossReference.display`, which `plainText` answers
      // from too, so the screen and a copied selection cannot disagree.
      let display = xref.display
      switch style.references {
      case .chip:
        break
      case .plainText:
        attributes[.font] = style.referenceFont(matching: font(in: base))
        return NSAttributedString(string: display.text, attributes: attributes)
      case .link:
        return NSAttributedString(string: display.text, attributes: attributes)
      }
      guard display.isChip else {
        return NSAttributedString(string: display.text, attributes: attributes)
      }
      var chipAttributes = attributes
      if referenceKinds.kind(of: xref.target) == .informative {
        chipAttributes[.rfcInformative] = "informative"
      }
      return chipRun(display.text, attributes: chipAttributes)

    case .lineBreak:
      return NSAttributedString(string: "\n", attributes: base)
    }
  }

  /// What makes a run a link: the URL, and the underline when the reader asked
  /// for one (`ReadingStyle.underlinesLinks`). For a style that emits no live
  /// links (`ReadingStyle.emitsLinks`), where it goes, as `.rfcLinkTarget`, and
  /// the link color with the underline, since nothing else colors it there.
  private func linkAttributes(_ url: URL) -> [NSAttributedString.Key: Any] {
    guard style.emitsLinks else {
      guard style.underlinesLinks else { return [.rfcLinkTarget: url] }
      return [
        .rfcLinkTarget: url,
        .foregroundColor: RFCColors.link,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
      ]
    }
    var attributes: [NSAttributedString.Key: Any] = [.link: url]
    if style.underlinesLinks {
      attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    return attributes
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
  private func chipRun(
    _ text: String, attributes: [NSAttributedString.Key: Any]
  ) -> NSAttributedString {
    var chip = attributes
    nextChipID += 1
    chip[.rfcChip] = nextChipID
    let result = NSMutableAttributedString()
    if let symbol = chipSymbolRun("doc.text", attributes: chip) {
      result.append(symbol)
      // U+2060 WORD JOINER: an attachment character is its own grapheme and
      // offers a line-break opportunity on either side, so in a narrow column
      // the chip's icon wrapped onto the line above its own label.
      result.append(NSAttributedString(string: "\u{2060}", attributes: chip))
    }
    result.append(NSAttributedString(string: text, attributes: chip))
    return result
  }

  /// Makes room in the line for every chip's tint. **The only writer of `.kern`
  /// around a chip.**
  ///
  /// The tint reaches `FragmentGeometry.chipPadding` past a chip's glyphs, and a
  /// space is narrower than two of those, so `BCP 14 [RFC2119] [RFC8174]` — in
  /// nearly every RFC — drew its two chips overlapping, each tint covering the
  /// space beside it. Kerning the chip's last character and the character before
  /// it by the padding gives the tint its own room. Run once over the finished
  /// text rather than as each chip is made, because the character before a chip
  /// is whatever came before its inline, and two adjacent chips each add to the
  /// one character between them. A table cell runs it over its own runs too, to be
  /// measured as it is drawn (#488).
  static func reserveChipPadding(in output: NSMutableAttributedString) {
    let padding = FragmentGeometry.chipPadding
    let whole = NSRange(location: 0, length: output.length)
    var chips: [NSRange] = []
    // The default options give the longest effective range, which is the whole
    // chip: its symbol's attachment is a storage run of its own.
    output.enumerateAttribute(.rfcChip, in: whole) { value, range, _ in
      if value != nil { chips.append(range) }
    }
    // The backing store itself: `string` would copy the whole document.
    let text = output.mutableString
    // A newline, a table cell's line separator (#506) and a tab.
    let lineAndCellBreaks: Set<unichar> = [0x0A, 0x2028, 0x09]
    for chip in chips {
      addKern(padding, at: NSMaxRange(chip) - 1, in: output)
      let before = chip.location - 1
      // A chip that starts a line has nothing before it to make room in: its
      // tint reaches into the margin, as a card's does, after a newline or after
      // the line separator a table cell's line break is set as. Nor does one
      // that starts a table cell: the layout ignores a tab's kern and sets the chip
      // at its stop, so kerning the tab would only let the measuring of the cell,
      // which cannot see the tab, disagree with the drawing where a layout did
      // honor it.
      if before >= 0, !lineAndCellBreaks.contains(text.character(at: before)) {
        addKern(padding, at: before, in: output)
      }
    }
  }

  private static func addKern(
    _ amount: CGFloat, at index: Int, in output: NSMutableAttributedString
  ) {
    let existing = output.attribute(.kern, at: index, effectiveRange: nil) as? CGFloat ?? 0
    output.addAttribute(.kern, value: existing + amount, range: NSRange(location: index, length: 1))
  }

  /// A heading's backlink caption (#183, #584): a paragraph of its own under the
  /// heading, an arrow and how many sections refer to the section, in the
  /// secondary style of a caption, so it does not read as part of the heading. It
  /// goes nowhere itself: its link names the section, and the reader lists the
  /// sections that refer there. Every character of it is `.rfcBacklinks`, its line
  /// break too, so a copied heading leaves the whole line out; the line break is
  /// neither link nor label, so the caption's extent is its words alone.
  func backlinkCaption(_ anchor: String, count: Int) -> NSAttributedString {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: style.backlinksFont,
      .foregroundColor: RFCColors.secondaryLabel,
      .paragraphStyle: paragraphStyle(spacingAfter: style.paragraphSpacing * 0.6),
      .rfcBacklinks: anchor,
    ]
    let lineBreak = NSAttributedString(string: "\n", attributes: attributes)
    let words = Self.backlinksCaption(count: count)
    attributes[.rfcSpoken] = words
    if let url = Self.url(anchor, scheme: Self.backlinksScheme) {
      attributes.merge(linkAttributes(url)) { _, link in link }
    }
    let result = NSMutableAttributedString()
    // A few points under the words' size: a diagonal arrow fills its whole square,
    // and at the words' size it outweighs them.
    if let symbol = chipSymbolRun(
      "arrow.down.backward", color: RFCColors.secondaryLabel, smallerBy: 4,
      attributes: attributes)
    {
      result.append(symbol)
      // NO-BREAK SPACE: the arrow never wraps away from the words it introduces.
      result.append(NSAttributedString(string: "\u{00A0}", attributes: attributes))
    }
    result.append(NSAttributedString(string: words, attributes: attributes))
    result.append(lineBreak)
    return result
  }

  /// What a backlink caption says, and VoiceOver says for it: the number of
  /// sections that refer to the section — not of references, of which one section
  /// may make several — in words up to three.
  public static func backlinksCaption(count: Int) -> String {
    switch count {
    case 1: "One Backlink"
    case 2: "Two Backlinks"
    case 3: "Three Backlinks"
    default: "\(count) Backlinks"
    }
  }

  /// The attributes a text view draws the link `link` with, given its own
  /// `defaults`: a text view colors every link itself, over the storage's color,
  /// which a backlink caption has to keep to stay in the background. The caption
  /// is drawn with `caption` on top: on macOS the ordinary pointer, not a link's
  /// pointing hand, since it opens a list beside it as a control does. Passed in
  /// rather than made here, because a cursor is AppKit's to make on the main
  /// thread and TextKit may ask from another. Every other link is drawn as the
  /// text view would.
  public static func linkRenderingAttributes(
    for link: Any, defaults: [NSAttributedString.Key: Any],
    caption: [NSAttributedString.Key: Any] = [:]
  ) -> [NSAttributedString.Key: Any] {
    // The scheme alone: asked of every link TextKit draws, where decoding the
    // anchor would allocate for an answer nobody reads.
    guard let url = link as? URL, url.scheme == backlinksScheme else { return defaults }
    var attributes = defaults
    attributes[.foregroundColor] = nil
    attributes.merge(caption) { _, caption in caption }
    return attributes
  }

  /// The leading glyph -- `doc.text` for a reference -- that rides inside the chip's
  /// own run, so it falls inside both the drawn background and the hit region.
  /// `NSTextAttachment(image:)` sits the image's bottom edge on the text baseline by
  /// default, which reads low against the words around it, so the symbol is drawn at
  /// the run's own font size and its bounds are centered on that font's cap height,
  /// to the nearest whole point: a symbol that hangs below the line's descender
  /// makes its line that much taller, even past a fixed line height, and a
  /// fraction there puts every fragment below it off the pixel grid (#273). A
  /// backlink caption's arrow is set the same way, in the caption's `color` and
  /// `smallerBy` points under its font's size.
  private func chipSymbolRun(
    _ name: String, color: PlatformColor = RFCColors.accent, smallerBy: CGFloat = 0,
    attributes: [NSAttributedString.Key: Any]
  ) -> NSAttributedString? {
    let font = font(in: attributes)
    let pointSize = font.pointSize - smallerBy
    guard let symbol = chipSymbol(name, pointSize: pointSize, color: color) else {
      return nil
    }
    // AppKit's `NSTextAttachment` has no `init(image:)`; `image` is assigned
    // after the default initializer instead, which UIKit also accepts.
    let attachment = NSTextAttachment()
    attachment.image = symbol
    attachment.bounds = CGRect(
      x: 0, y: ((font.capHeight - symbol.size.height) / 2).rounded(), width: symbol.size.width,
      height: symbol.size.height)
    let run = NSMutableAttributedString(attachment: attachment)
    run.addAttributes(attributes, range: NSRange(location: 0, length: run.length))
    return run
  }

  /// Rendering the symbol is the expensive part and depends only on which symbol and
  /// the point size, of which a build sees a few — but there is a chip per cross reference, and
  /// RFCs are full of them. The attachment itself stays per run.
  private func chipSymbol(_ name: String, pointSize: CGFloat, color: PlatformColor)
    -> PlatformImage?
  {
    let key = ChipSymbolKey(name: name, pointSize: pointSize, color: color)
    if let cached = chipSymbols[key] { return cached }
    guard let template = PlatformImage.symbol(named: name, pointSize: pointSize) else {
      return nil
    }
    #if canImport(UIKit)
      // UIKit draws an attachment's template symbol untinted, black on a dark page,
      // where AppKit tints it; colored as the text beside it is.
      let symbol = template.withTintColor(color, renderingMode: .alwaysOriginal)
    #else
      let symbol = template
    #endif
    chipSymbols[key] = symbol
    return symbol
  }

  /// The other half of `url(for:)`'s anchor case: nil when the URL is not one of
  /// ours. Kept beside the encoder, because a scheme whose two halves live in
  /// different modules is one percent-encoding rule away from silently failing on
  /// an anchor containing `?` or `#`.
  public static func anchor(from url: URL) -> String? {
    decoded(url, scheme: anchorScheme)
  }

  /// The same for `referenceScheme`: the bibliography entry a citation names.
  public static func reference(from url: URL) -> String? {
    decoded(url, scheme: referenceScheme)
  }

  /// The same for `backlinksScheme`: the section whose backlinks a caption lists.
  public static func backlinks(from url: URL) -> String? {
    decoded(url, scheme: backlinksScheme)
  }

  private static func decoded(_ url: URL, scheme: String) -> String? {
    guard url.scheme == scheme else { return nil }
    let encoded = url.absoluteString.dropFirst(scheme.count + 1)
    return String(encoded).removingPercentEncoding ?? String(encoded)
  }

  func url(for xref: CrossReference) -> URL? {
    switch xref.target {
    case .document(let id, let section, _):
      return RFCLink(id: id, section: section).appURL
    case .anchor(let anchor):
      let scheme = referenceAnchors.contains(anchor) ? Self.referenceScheme : Self.anchorScheme
      return Self.url(anchor, scheme: scheme)
    case .entrySection(let entry, _, _, let url):
      return url ?? Self.url(entry, scheme: Self.referenceScheme)
    }
  }

  /// The encoding half of `decoded(_:scheme:)`: `anchor` as a link of one of our
  /// schemes, which `anchor(from:)` and its siblings read back.
  public static func url(_ anchor: String, scheme: String) -> URL? {
    let encoded = anchor.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? anchor
    return URL(string: "\(scheme):\(encoded)")
  }

  /// The font a run's context carries, or the body's where it carries none.
  func font(in attributes: [NSAttributedString.Key: Any]) -> PlatformFont {
    (attributes[.font] as? PlatformFont) ?? style.bodyFont
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
