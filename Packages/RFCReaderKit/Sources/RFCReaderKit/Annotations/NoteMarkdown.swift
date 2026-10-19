import Foundation

// A note's body as it is stored (#523): restricted CommonMark. Parsed with
// Foundation's CommonMark parser, whose result is reduced to the scope a note keeps,
// and serialized here, in the one spelling the parser reads back as the same body.

extension NoteBody {
  /// The body of `markdown`. Anything outside the scope is reduced to it: a heading,
  /// a block quote or a code block becomes a paragraph of its text, a table a
  /// paragraph a row, an image its text. Markdown that does not parse is kept as one
  /// paragraph of its text.
  public init(markdown: String) {
    guard
      let parsed = try? AttributedString(
        markdown: markdown, options: .init(interpretedSyntax: .full))
    else {
      self.init([.paragraph([Span(markdown)])])
      return
    }
    var leaves: [Leaf] = []
    var leafIdentity: Int?
    var cell: Int?
    for run in parsed.runs {
      let components = run.presentationIntent?.components ?? []
      // The innermost block that holds text: a paragraph, or what stands in for one.
      let block = components.first { component in
        switch component.kind {
        case .paragraph, .header, .codeBlock, .tableRow: true
        default: false
        }
      }
      let identity = block?.identity ?? -1
      var text = String(parsed[run.range].characters)
      let inline = run.inlinePresentationIntent ?? []
      if inline.contains(.lineBreak) { text = "\n" }
      if inline.contains(.softBreak) { text = " " }
      if case .codeBlock? = block?.kind {
        while text.hasSuffix("\n") { text.removeLast() }
      }
      var style: Style = []
      if inline.contains(.emphasized) { style.insert(.emphasis) }
      if inline.contains(.stronglyEmphasized) { style.insert(.strong) }
      if inline.contains(.strikethrough) { style.insert(.strikethrough) }
      if inline.contains(.code) { style.insert(.code) }
      let span = Span(text, style: style, link: run.link)
      let thisCell = components.first { if case .tableCell = $0.kind { true } else { false } }?
        .identity
      if identity == leafIdentity, !leaves.isEmpty {
        if let thisCell, thisCell != cell { leaves[leaves.count - 1].spans.append(Span(" ")) }
        leaves[leaves.count - 1].spans.append(span)
      } else {
        leaves.append(Leaf(levels: Self.levels(components), spans: [span]))
      }
      leafIdentity = identity
      cell = thisCell
    }
    self.init(leaves: leaves)
  }

  /// The lists a block is nested in, outermost first, each with its item.
  private static func levels(_ components: [PresentationIntent.IntentType]) -> [Leaf.Level] {
    var levels: [Leaf.Level] = []
    var item: Int?
    // Innermost first: an item comes before the list that holds it.
    for component in components {
      switch component.kind {
      case .listItem:
        item = component.identity
      case .orderedList, .unorderedList:
        let isOrdered = if case .orderedList = component.kind { true } else { false }
        levels.append(
          Leaf.Level(
            list: component.identity, isOrdered: isOrdered, item: item ?? component.identity))
        item = nil
      default:
        break
      }
    }
    return levels.reversed()
  }

  /// The body as Markdown, in the spelling `init(markdown:)` reads back as this body.
  public var markdown: String {
    blocks.map { block in
      switch block {
      case .paragraph(let spans): Self.inline(spans, indent: "")
      case .list(let list): Self.markdown(list, indent: "")
      }
    }.joined(separator: "\n\n")
  }

  private static func markdown(_ list: List, indent: String) -> String {
    var lines: [String] = []
    for (index, item) in list.items.enumerated() {
      let marker = list.isOrdered ? "\(index + 1). " : "- "
      let inner = indent + String(repeating: " ", count: marker.count)
      let text = inline(item.spans, indent: inner)
      lines.append(text.isEmpty ? indent + marker.trimmingCharacters(in: .whitespaces) : indent + marker + text)
      for nested in item.lists {
        lines.append(markdown(nested, indent: inner))
      }
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - Inline

  /// A paragraph's spans, its line breaks continued at `indent`.
  private static func inline(_ spans: [Span], indent: String) -> String {
    var output = ""
    var open: [Style] = []
    var atLineStart = true
    let order: [Style] = [.strikethrough, .strong, .emphasis]
    var index = 0
    while index < spans.count {
      let span = spans[index]
      if span.text == "\n" {
        closeAll(&open, into: &output)
        output += "\\\n" + indent
        atLineStart = true
        index += 1
        continue
      }
      // A link's spans go out together, its style around it.
      var end = index + 1
      if let link = span.link {
        while end < spans.count, spans[end].link == link, spans[end].text != "\n" { end += 1 }
      }
      let wanted = order.filter { span.style.contains($0) }
      // Keep what is open and still wanted, from the outside in; close the rest.
      var keep = 0
      while keep < open.count, keep < wanted.count, open[keep] == wanted[keep] { keep += 1 }
      while open.count > keep { output += delimiter(open.removeLast()) }
      for style in wanted.dropFirst(keep) {
        output += delimiter(style)
        open.append(style)
      }
      if let link = span.link {
        let text = spans[index..<end].map(\.text).joined()
        output += "[" + escaped(text, atLineStart: false) + "](" + destination(link) + ")"
      } else if span.style.contains(.code) {
        output += code(span.text)
      } else {
        output += escaped(span.text, atLineStart: atLineStart)
      }
      atLineStart = false
      index = end
    }
    closeAll(&open, into: &output)
    return output
  }

  private static func closeAll(_ open: inout [Style], into output: inout String) {
    while let style = open.popLast() { output += delimiter(style) }
  }

  private static func delimiter(_ style: Style) -> String {
    switch style {
    case .strikethrough: "~~"
    case .strong: "**"
    default: "*"
    }
  }

  /// A code span, fenced by one backtick more than the longest run inside it, and
  /// padded where CommonMark would otherwise take its edges.
  private static func code(_ text: String) -> String {
    var longest = 0
    var run = 0
    for character in text {
      run = character == "`" ? run + 1 : 0
      longest = max(longest, run)
    }
    let fence = String(repeating: "`", count: longest + 1)
    let isAllSpaces = text.allSatisfy { $0 == " " }
    let pads =
      text.hasPrefix("`") || text.hasSuffix("`")
      || (!isAllSpaces && text.hasPrefix(" ") && text.hasSuffix(" "))
    return pads ? fence + " " + text + " " + fence : fence + text + fence
  }

  /// A link's destination, its parentheses and angle brackets escaped.
  private static func destination(_ url: URL) -> String {
    var output = ""
    for character in url.absoluteString {
      if "()<>\\ ".contains(character) { output.append("\\") }
      output.append(character)
    }
    return output
  }

  /// Plain text, escaped so that it reads back as itself: every character CommonMark
  /// gives a meaning anywhere, what starts a block at a line's start, and what its
  /// extension would make a link of, a URL's `://` and a `www.`. A mail address is the
  /// one thing no escape keeps from being a link, which it becomes when read back.
  private static func escaped(_ text: String, atLineStart: Bool) -> String {
    let characters = Array(text)
    var output = ""
    var index = 0
    var lineStart = atLineStart
    while index < characters.count {
      let character = characters[index]
      if lineStart {
        lineStart = false
        if "#-+=|".contains(character) {
          output += "\\" + String(character)
          index += 1
          continue
        }
        // A number then a period or a parenthesis starts a numbered list.
        var digits = index
        while digits < characters.count, characters[digits].isASCII,
          characters[digits].isNumber
        {
          digits += 1
        }
        if digits > index, digits < characters.count, ".)".contains(characters[digits]) {
          output += String(characters[index..<digits]) + "\\" + String(characters[digits])
          index = digits + 1
          continue
        }
      }
      if "\\*_~`[]<>&!".contains(character) {
        output += "\\" + String(character)
      } else if character == ":", index + 2 < characters.count, characters[index + 1] == "/",
        characters[index + 2] == "/"
      {
        output += "\\:"
      } else if character == ".", index >= 3,
        String(characters[(index - 3)..<index]).lowercased() == "www",
        index == 3 || !(characters[index - 4].isLetter || characters[index - 4].isNumber)
      {
        output += "\\."
      } else {
        output.append(character)
      }
      index += 1
    }
    return output
  }
}
