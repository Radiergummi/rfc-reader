import Foundation

/// A reading note's text (#523), in the scope it is stored in: CommonMark restricted to
/// paragraphs, bulleted and numbered lists, nested, and inside them emphasis, strong,
/// strikethrough, inline code and links. What is stored is its Markdown
/// (`NoteBody.markdown`), and what the editor edits is its projection into attributed
/// text (`NoteText`), so neither depends on the other.
///
/// A body is kept **canonical** (`normalized`): two bodies that serialize to the same
/// Markdown are equal, which is what makes parse ∘ serialize the identity.
public struct NoteBody: Sendable, Hashable {
  public var blocks: [Block]

  public init(_ blocks: [Block] = []) {
    self.blocks = blocks
    normalize()
  }

  public enum Block: Sendable, Hashable {
    case paragraph([Span])
    case list(List)
  }

  /// A bulleted or a numbered list. A numbered list always counts from one.
  public struct List: Sendable, Hashable {
    public var isOrdered: Bool
    public var items: [Item]

    public init(isOrdered: Bool, items: [Item]) {
      self.isOrdered = isOrdered
      self.items = items
    }
  }

  /// One item: its text, then the lists nested in it.
  public struct Item: Sendable, Hashable {
    public var spans: [Span]
    public var lists: [List]

    public init(_ spans: [Span], lists: [List] = []) {
      self.spans = spans
      self.lists = lists
    }
  }

  /// A stretch of text in one style. A `\n` in the text is a line break inside its
  /// paragraph.
  public struct Span: Sendable, Hashable {
    public var text: String
    public var style: Style
    public var link: URL?

    public init(_ text: String, style: Style = [], link: URL? = nil) {
      self.text = text
      self.style = style
      self.link = link
    }
  }

  public struct Style: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let emphasis = Style(rawValue: 1 << 0)
    public static let strong = Style(rawValue: 1 << 1)
    public static let strikethrough = Style(rawValue: 1 << 2)
    public static let code = Style(rawValue: 1 << 3)
  }

  /// Whether it holds no text.
  public var isEmpty: Bool { blocks.isEmpty }

  /// Its text without formatting, paragraphs and items a line each: what the
  /// Annotations tab shows of a note.
  public var plainText: String {
    var lines: [String] = []
    func add(_ list: List) {
      for item in list.items {
        lines.append(item.spans.map(\.text).joined())
        item.lists.forEach(add)
      }
    }
    for block in blocks {
      switch block {
      case .paragraph(let spans): lines.append(spans.map(\.text).joined())
      case .list(let list): add(list)
      }
    }
    return lines.joined(separator: "\n")
  }
}

// MARK: - Building from a flat list of paragraphs

extension NoteBody {
  /// One paragraph as a parser meets it: its text, and the lists it is nested in,
  /// outermost first, each with the item it is in. What the Markdown parser and the
  /// editor's text both reduce to, so one builder makes the tree from either.
  struct Leaf {
    var levels: [LeafLevel]
    var spans: [Span]
  }

  /// A list a paragraph is nested in, and the item of it the paragraph is in.
  struct LeafLevel {
    let list: AnyHashable
    let isOrdered: Bool
    let item: AnyHashable
  }

  init(leaves: [Leaf]) {
    self.init(Self.blocks(leaves[...], depth: 0))
  }

  private static func blocks(_ leaves: ArraySlice<Leaf>, depth: Int) -> [Block] {
    var result: [Block] = []
    var index = leaves.startIndex
    while index < leaves.endIndex {
      let leaf = leaves[index]
      guard leaf.levels.count > depth else {
        result.append(.paragraph(leaf.spans))
        index += 1
        continue
      }
      let list = leaf.levels[depth].list
      var end = index + 1
      while end < leaves.endIndex, leaves[end].levels.count > depth,
        leaves[end].levels[depth].list == list
      {
        end += 1
      }
      result.append(.list(self.list(leaves[index..<end], depth: depth)))
      index = end
    }
    return result
  }

  private static func list(_ leaves: ArraySlice<Leaf>, depth: Int) -> List {
    var items: [Item] = []
    var index = leaves.startIndex
    while index < leaves.endIndex {
      let item = leaves[index].levels[depth].item
      var end = index + 1
      while end < leaves.endIndex, leaves[end].levels[depth].item == item { end += 1 }
      // An item holds one paragraph and its lists: a second paragraph, in the scope
      // a note keeps, joins the first on a line of its own.
      var spans: [Span] = []
      var lists: [List] = []
      for block in blocks(leaves[index..<end], depth: depth + 1) {
        switch block {
        case .paragraph(let more):
          if !spans.isEmpty { spans.append(Span("\n")) }
          spans += more
        case .list(let list):
          lists.append(list)
        }
      }
      items.append(Item(spans, lists: lists))
      index = end
    }
    return List(isOrdered: leaves.first?.levels[depth].isOrdered ?? false, items: items)
  }
}

// MARK: - The canonical form

extension NoteBody {
  /// Puts the body in its one form. Nothing a reader would see is lost but what
  /// CommonMark cannot say: an empty paragraph or item, white space at a paragraph's
  /// edges or around a line break, a style on the white space at a styled run's edge,
  /// formatting inside a link's text, which takes its run's common style, and two
  /// lists of one kind side by side, which become one.
  mutating func normalize() {
    blocks = Self.normalized(blocks)
  }

  private static func normalized(_ blocks: [Block]) -> [Block] {
    var result: [Block] = []
    for block in blocks {
      switch block {
      case .paragraph(let spans):
        let spans = normalized(spans)
        if !spans.isEmpty { result.append(.paragraph(spans)) }
      case .list(let list):
        guard let list = normalized(list) else { continue }
        if case .list(let previous)? = result.last, previous.isOrdered == list.isOrdered {
          result[result.count - 1] = .list(
            List(isOrdered: list.isOrdered, items: previous.items + list.items))
        } else {
          result.append(.list(list))
        }
      }
    }
    return result
  }

  private static func normalized(_ list: List) -> List? {
    let items = list.items.compactMap { item -> Item? in
      let spans = normalized(item.spans)
      let lists = normalized(item.lists.map(Block.list)).compactMap { block -> List? in
        if case .list(let list) = block { list } else { nil }
      }
      guard !spans.isEmpty || !lists.isEmpty else { return nil }
      return Item(spans, lists: lists)
    }
    return items.isEmpty ? nil : List(isOrdered: list.isOrdered, items: items)
  }

  static func normalized(_ spans: [Span]) -> [Span] {
    // A link's text has no code, and one style throughout: CommonMark's parse keeps
    // none inside it.
    var spans = spans.filter { !$0.text.isEmpty }
    var index = 0
    while index < spans.count {
      guard let link = spans[index].link else {
        index += 1
        continue
      }
      var end = index
      var common = Style.all
      while end < spans.count, spans[end].link == link {
        common.formIntersection(spans[end].style)
        end += 1
      }
      common.remove(.code)
      for member in index..<end { spans[member].style = common }
      index = end
    }
    // A line break stands alone, unstyled and unlinked; a run of them is one.
    spans = spans.flatMap { span -> [Span] in
      guard span.text.contains("\n") else { return [span] }
      var pieces: [Span] = []
      for (offset, piece) in span.text.split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
      {
        if offset > 0 { pieces.append(Span("\n")) }
        pieces.append(Span(String(piece), style: span.style, link: span.link))
      }
      return pieces
    }
    // White space at a paragraph's edges and around a line break goes.
    spans = trimmed(spans)
    // White space at a styled or linked run's edge keeps only what its neighbor shares.
    var edged: [Span] = []
    for (offset, span) in spans.enumerated() {
      guard !span.style.contains(.code), span.text != "\n",
        !span.style.isEmpty || span.link != nil
      else {
        edged.append(span)
        continue
      }
      let previous = offset > 0 ? spans[offset - 1] : nil
      let next = offset + 1 < spans.count ? spans[offset + 1] : nil
      let leading = String(span.text.prefix(while: isBlank))
      let rest = span.text.dropFirst(leading.count)
      let trailing = String(String(rest.reversed().prefix(while: isBlank)).reversed())
      let core = String(rest.dropLast(trailing.count))
      if !leading.isEmpty {
        edged.append(Span(leading, style: shared(span, previous), link: sharedLink(span, previous)))
      }
      if !core.isEmpty { edged.append(Span(core, style: span.style, link: span.link)) }
      if !trailing.isEmpty {
        edged.append(Span(trailing, style: shared(span, next), link: sharedLink(span, next)))
      }
    }
    // Neighbors alike are one.
    var merged: [Span] = []
    for span in edged where !span.text.isEmpty {
      if let last = merged.last, last.style == span.style, last.link == span.link,
        span.text != "\n", last.text != "\n"
      {
        merged[merged.count - 1].text += span.text
      } else if span.text == "\n", merged.last?.text == "\n" {
        continue
      } else {
        merged.append(span)
      }
    }
    return merged
  }

  private static func shared(_ span: Span, _ neighbor: Span?) -> Style {
    guard let neighbor, neighbor.text != "\n" else { return [] }
    return span.style.intersection(neighbor.style).subtracting(.code)
  }

  private static func sharedLink(_ span: Span, _ neighbor: Span?) -> URL? {
    guard let neighbor, neighbor.link == span.link else { return nil }
    return span.link
  }

  /// Without white space at the ends of the paragraph, or on either side of a line
  /// break, and without a line break at either end.
  private static func trimmed(_ spans: [Span]) -> [Span] {
    var spans = spans
    while spans.first?.text == "\n" { spans.removeFirst() }
    while spans.last?.text == "\n" { spans.removeLast() }
    for index in spans.indices where spans[index].text != "\n" {
      let atStart = index == 0 || spans[index - 1].text == "\n"
      let atEnd = index == spans.count - 1 || spans[index + 1].text == "\n"
      var text = spans[index].text
      if atStart { text = String(text.drop(while: isBlank)) }
      if atEnd {
        while text.last.map(isBlank) == true { text.removeLast() }
      }
      spans[index].text = text
    }
    spans.removeAll { $0.text.isEmpty }
    // Trimming may have emptied a paragraph's edge, leaving a break there.
    while spans.first?.text == "\n" { spans.removeFirst() }
    while spans.last?.text == "\n" { spans.removeLast() }
    return spans
  }
}

/// A space or a tab: what CommonMark trims at a line's edges.
private func isBlank(_ character: Character) -> Bool {
  character == " " || character == "\t"
}

extension NoteBody.Style {
  static let all: NoteBody.Style = [.emphasis, .strong, .strikethrough, .code]
}
