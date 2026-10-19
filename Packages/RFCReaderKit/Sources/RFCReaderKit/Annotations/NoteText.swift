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
      line.addAttribute(
        .paragraphStyle, value: paragraphStyle(lists: lists, font: font),
        range: NSRange(location: 0, length: line.length))
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

  /// A paragraph's style, nested in `lists`: an item indented a level's width a list
  /// deep, as TextEdit indents one, and set close to the next; a paragraph apart.
  public static func paragraphStyle(lists: [NSTextList], font: PlatformFont) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.textLists = lists
    style.paragraphSpacing = lists.isEmpty ? paragraphSpacing : 0
    let indent = CGFloat(lists.count) * font.pointSize * 1.8
    style.headIndent = indent
    style.firstLineHeadIndent = indent
    return style.copy() as? NSParagraphStyle ?? style
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
      ? PlatformFont.monospacedFont(ofSize: font.pointSize, weight: .regular) : font
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
      var levels: [NoteBody.LeafLevel] = []
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
          NoteBody.LeafLevel(
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

  // MARK: - Formatting

  /// Turns `style` on over `range` of `text`, or off where all of it has it already:
  /// what the editor's bold, italic, strikethrough and code buttons do. In `font`,
  /// the editor's, which a code span leaves for a monospaced one and returns to.
  public static func toggle(
    _ style: NoteBody.Style, in text: NSMutableAttributedString, range: NSRange, font: PlatformFont
  ) {
    guard range.length > 0 else { return }
    let isOn = has(style, in: text, range: range)
    text.enumerateAttributes(in: range) { attributes, run, _ in
      var current = self.style(of: attributes)
      if isOn { current.subtract(style) } else { current.formUnion(style) }
      text.setAttributes(
        restyled(attributes, as: current, font: font), range: run)
    }
  }

  /// The typing attributes `attributes` with `style` turned on or off: a button
  /// pressed with nothing selected styles what is typed next.
  public static func toggling(
    _ style: NoteBody.Style, in attributes: [NSAttributedString.Key: Any], font: PlatformFont
  ) -> [NSAttributedString.Key: Any] {
    var current = self.style(of: attributes)
    if current.isSuperset(of: style) { current.subtract(style) } else { current.formUnion(style) }
    return restyled(attributes, as: current, font: font)
  }

  /// Whether every character of `range` has `style`.
  public static func has(_ style: NoteBody.Style, in text: NSAttributedString, range: NSRange)
    -> Bool
  {
    var all = true
    text.enumerateAttributes(in: range) { attributes, _, stop in
      if !self.style(of: attributes).isSuperset(of: style) {
        all = false
        stop.pointee = true
      }
    }
    return all
  }

  private static func style(of attributes: [NSAttributedString.Key: Any]) -> NoteBody.Style {
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
    return style
  }

  private static func restyled(
    _ attributes: [NSAttributedString.Key: Any], as style: NoteBody.Style, font: PlatformFont
  ) -> [NSAttributedString.Key: Any] {
    var result = attributes
    let styled = self.attributes(NoteBody.Span("", style: style), font: font)
    result[.font] = styled[.font]
    result[.strikethroughStyle] = styled[.strikethroughStyle]
    return result
  }

  /// Makes the paragraphs `range` touches a bulleted or a numbered list, or takes
  /// them out of it where they are all items of such a list already. Joined to the
  /// list just before them where it is of the same kind.
  public static func toggleList(
    ordered: Bool, in text: NSMutableAttributedString, range: NSRange, font: PlatformFont
  ) {
    let paragraphs = self.paragraphs(of: text, touching: range)
    let lists = paragraphs.map { textLists(of: text, at: $0) }
    let isOn = lists.allSatisfy { $0.last.map(isOrdered) == ordered }
    let before = paragraphs.first.flatMap { first -> NSTextList? in
      guard first.location > 0 else { return nil }
      return textLists(of: text, at: NSRange(location: first.location - 1, length: 0)).first
    }
    let list =
      before.flatMap { isOrdered($0) == ordered ? $0 : nil } ?? newList(ordered: ordered, depth: 0)
    for (paragraph, current) in zip(paragraphs, lists) {
      let next: [NSTextList] =
        isOn
        ? Array(current.dropLast())
        : current.isEmpty
          ? [list]
          : current.dropLast() + [
            newList(ordered: ordered, depth: current.count - 1)
          ]
      setLists(next, in: text, paragraph: paragraph, font: font)
    }
  }

  /// Nests the list items `range` touches a level deeper (`by: 1`), or takes them a
  /// level out (`by: -1`): what Tab and Shift-Tab do, for a keyboard without them.
  public static func indent(
    by levels: Int, in text: NSMutableAttributedString, range: NSRange, font: PlatformFont
  ) {
    var made: [Int: NSTextList] = [:]
    for paragraph in paragraphs(of: text, touching: range) {
      let current = textLists(of: text, at: paragraph)
      guard let innermost = current.last else { continue }
      if levels > 0 {
        let depth = current.count
        let deeper = made[depth] ?? newList(ordered: isOrdered(innermost), depth: depth)
        made[depth] = deeper
        setLists(current + [deeper], in: text, paragraph: paragraph, font: font)
      } else {
        setLists(Array(current.dropLast()), in: text, paragraph: paragraph, font: font)
      }
    }
  }

  private static func newList(ordered: Bool, depth: Int) -> NSTextList {
    NSTextList(
      markerFormat: ordered ? .decimal : depth.isMultiple(of: 2) ? .disc : .circle, options: 0)
  }

  private static func textLists(of text: NSAttributedString, at paragraph: NSRange)
    -> [NSTextList]
  {
    guard text.length > 0 else { return [] }
    let location = min(paragraph.location, text.length - 1)
    let style = text.attribute(.paragraphStyle, at: location, effectiveRange: nil)
    return (style as? NSParagraphStyle)?.textLists ?? []
  }

  private static func setLists(
    _ lists: [NSTextList], in text: NSMutableAttributedString, paragraph: NSRange,
    font: PlatformFont
  ) {
    guard paragraph.length > 0 else { return }
    text.addAttribute(
      .paragraphStyle, value: paragraphStyle(lists: lists, font: font), range: paragraph)
  }

  /// The paragraphs `range` touches, each with its line end.
  private static func paragraphs(of text: NSAttributedString, touching range: NSRange)
    -> [NSRange]
  {
    let string = text.string as NSString
    var result: [NSRange] = []
    var location = range.location
    repeat {
      let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
      result.append(paragraph)
      location = NSMaxRange(paragraph)
    } while location < NSMaxRange(range) && location < string.length
    return result
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
