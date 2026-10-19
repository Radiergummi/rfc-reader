import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A note's body as the editor edits it (#523): attributed text in TextKit 2's terms,
/// a paragraph a line, a list item a paragraph whose style holds the `NSTextList`s it
/// is nested in, with no marker in the text, which TextKit 2 draws. Projected from the
/// stored body when the editor opens and back when it saves, so what is stored never
/// depends on the editor.
///
/// Reading text back is also how a paste is reduced to the scope a note keeps: bold,
/// italic, a monospaced font, a strikethrough, a link and a list survive it, and
/// every other font, size, color, heading or table goes (`reduced(_:font:)`).
public enum NoteText {
  /// How far apart paragraphs are, which stand in for Markdown's blank line.
  public static let paragraphSpacing: CGFloat = 6

  /// `body` as attributed text in `font`, the editor's body font.
  public static func attributed(_ body: NoteBody, font: PlatformFont) -> NSAttributedString {
    var paragraphs: [NSAttributedString] = []
    func add(_ spans: [NoteBody.Span], lists: [NSTextList]) {
      let line = NSMutableAttributedString()
      for span in spans {
        let text = span.text == "\n" ? "\u{2028}" : span.text
        line.append(NSAttributedString(string: text, attributes: attributes(span, font: font)))
      }
      let style = NSMutableParagraphStyle()
      style.textLists = lists
      style.paragraphSpacing = paragraphSpacing
      if !lists.isEmpty {
        // As TextEdit indents an item: a level's width a list deep.
        let indent = CGFloat(lists.count) * font.pointSize * 1.8
        style.headIndent = indent
        style.firstLineHeadIndent = indent
        style.paragraphSpacing = 0
      }
      if line.length == 0 {
        line.append(NSAttributedString(string: "", attributes: [.font: font]))
      }
      line.addAttribute(
        .paragraphStyle, value: style.copy(), range: NSRange(location: 0, length: line.length))
      paragraphs.append(line)
    }
    func add(_ list: NoteBody.List, within lists: [NSTextList]) {
      let textList = NSTextList(
        markerFormat: list.isOrdered ? .decimal : lists.count.isMultiple(of: 2) ? .disc : .circle,
        options: 0)
      for item in list.items {
        add(item.spans, lists: lists + [textList])
        for nested in item.lists { add(nested, within: lists + [textList]) }
      }
    }
    for block in body.blocks {
      switch block {
      case .paragraph(let spans): add(spans, lists: [])
      case .list(let list): add(list, within: [])
      }
    }
    let result = NSMutableAttributedString()
    for (index, paragraph) in paragraphs.enumerated() {
      if index > 0 {
        let style = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
        var separator: [NSAttributedString.Key: Any] = [.font: font]
        if let previous = paragraphs[index - 1].attribute(
          .paragraphStyle, at: max(0, paragraphs[index - 1].length - 1), effectiveRange: nil)
        {
          separator[.paragraphStyle] = previous
        } else if let style {
          separator[.paragraphStyle] = style
        }
        result.append(NSAttributedString(string: "\n", attributes: separator))
      }
      result.append(paragraph)
    }
    return result
  }

  private static func attributes(_ span: NoteBody.Span, font: PlatformFont)
    -> [NSAttributedString.Key: Any]
  {
    var attributes: [NSAttributedString.Key: Any] = [:]
    var traits: [Trait] = []
    if span.style.contains(.strong) { traits.append(.bold) }
    if span.style.contains(.emphasis) { traits.append(.italic) }
    let base =
      span.style.contains(.code)
      ? PlatformFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : font
    attributes[.font] = withTraits(traits, of: base)
    if span.style.contains(.strikethrough) {
      attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }
    if let link = span.link { attributes[.link] = link }
    return attributes
  }

  // MARK: - Reading it back

  /// The body `text` holds, in the scope a note keeps.
  public static func body(of text: NSAttributedString) -> NoteBody {
    var leaves: [NoteBody.Leaf] = []
    // The item open at each depth, and the list it is in.
    var open: [(list: NSTextList, item: Int)] = []
    var nextItem = 0
    let string = text.string as NSString
    var location = 0
    while location <= string.length {
      let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
      var content = paragraph
      // Without its line end.
      while content.length > 0,
        let scalar = Unicode.Scalar(string.character(at: NSMaxRange(content) - 1)),
        CharacterSet.newlines.contains(scalar), scalar != "\u{2028}"
      {
        content.length -= 1
      }
      let style =
        paragraph.length > 0
        ? text.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
          as? NSParagraphStyle : nil
      let lists = style?.textLists ?? []
      var levels: [NoteBody.Leaf.Level] = []
      for (depth, list) in lists.enumerated() {
        let isLast = depth == lists.count - 1
        if !isLast, depth < open.count, open[depth].list === list {
          // Still in the item this paragraph's parent opened.
        } else {
          open.removeSubrange(min(depth, open.count)...)
          open.append((list, nextItem))
          nextItem += 1
        }
        levels.append(
          NoteBody.Leaf.Level(
            list: ObjectIdentifier(list), isOrdered: isOrdered(list), item: open[depth].item))
      }
      open.removeSubrange(min(lists.count, open.count)...)
      var spans = self.spans(of: text, in: content)
      if !lists.isEmpty { spans = withoutMarker(spans, list: lists[lists.count - 1]) }
      leaves.append(NoteBody.Leaf(levels: levels, spans: spans))
      guard NSMaxRange(paragraph) > location else { break }
      location = NSMaxRange(paragraph)
      if location == string.length { break }
    }
    return NoteBody(leaves: leaves)
  }

  /// A paste, reduced to what a note keeps, in the editor's `font`.
  public static func reduced(_ pasted: NSAttributedString, font: PlatformFont)
    -> NSAttributedString
  {
    attributed(body(of: pasted), font: font)
  }

  private static func spans(of text: NSAttributedString, in range: NSRange) -> [NoteBody.Span] {
    var spans: [NoteBody.Span] = []
    text.enumerateAttributes(in: range) { attributes, run, _ in
      var style: NoteBody.Style = []
      if let font = attributes[.font] as? PlatformFont {
        let traits = Trait.of(font)
        if traits.contains(.bold) { style.insert(.strong) }
        if traits.contains(.italic) { style.insert(.emphasis) }
        if traits.contains(.monospace) { style.insert(.code) }
      }
      if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 {
        style.insert(.strikethrough)
      }
      let link: URL? =
        switch attributes[.link] {
        case let url as URL: url
        case let string as String: URL(string: string)
        default: nil
        }
      let string = (text.string as NSString).substring(with: run)
        .replacingOccurrences(of: "\u{2028}", with: "\n")
        .replacingOccurrences(of: "\u{2029}", with: "\n")
      spans.append(NoteBody.Span(string, style: style, link: link))
    }
    return spans
  }

  /// A list item's text without a marker its source wrote into it, as TextKit 1 and
  /// pasted rich text do: `\t•\t`.
  private static func withoutMarker(_ spans: [NoteBody.Span], list: NSTextList)
    -> [NoteBody.Span]
  {
    guard var first = spans.first, first.text.hasPrefix("\t") else { return spans }
    let rest = first.text.dropFirst()
    guard let tab = rest.firstIndex(of: "\t") else { return spans }
    first.text = String(rest[rest.index(after: tab)...])
    return [first] + spans.dropFirst()
  }

  private static func isOrdered(_ list: NSTextList) -> Bool {
    switch list.markerFormat {
    case .disc, .circle, .square, .hyphen, .diamond, .box, .check: false
    default: true
    }
  }

  // MARK: - Font traits

  enum Trait {
    case bold, italic, monospace

    static func of(_ font: PlatformFont) -> Set<Trait> {
      var result: Set<Trait> = []
      #if canImport(UIKit)
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.traitBold) { result.insert(.bold) }
        if traits.contains(.traitItalic) { result.insert(.italic) }
        if traits.contains(.traitMonoSpace) { result.insert(.monospace) }
      #else
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) { result.insert(.bold) }
        if traits.contains(.italic) { result.insert(.italic) }
        if traits.contains(.monoSpace) { result.insert(.monospace) }
      #endif
      return result
    }
  }

  /// `font` with bold or italic, or both, as far as its family has them.
  static func withTraits(_ traits: [Trait], of font: PlatformFont) -> PlatformFont {
    guard !traits.isEmpty else { return font }
    #if canImport(UIKit)
      var symbolic = font.fontDescriptor.symbolicTraits
      if traits.contains(.bold) { symbolic.insert(.traitBold) }
      if traits.contains(.italic) { symbolic.insert(.traitItalic) }
      guard let descriptor = font.fontDescriptor.withSymbolicTraits(symbolic) else { return font }
      return UIFont(descriptor: descriptor, size: font.pointSize)
    #else
      var symbolic = font.fontDescriptor.symbolicTraits
      if traits.contains(.bold) { symbolic.insert(.bold) }
      if traits.contains(.italic) { symbolic.insert(.italic) }
      let descriptor = font.fontDescriptor.withSymbolicTraits(symbolic)
      return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    #endif
  }
}
