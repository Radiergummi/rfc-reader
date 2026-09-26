/// Spells out the text of an RFCXML `<u>` element the way its `format` asks.
///
/// `<u>` marks non-ASCII text a protocol depends on (RFC 7997), and the format
/// exists so that a reader whose font lacks the glyph, or who cannot tell it
/// from a lookalike, still has the code point. The bare character is therefore
/// never enough: the expansion is text, and belongs in the model.
///
/// A format is up to three keywords joined by hyphens -- the first stands
/// alone and the rest follow in parentheses, `"ש" (HEBREW LETTER SHIN, U+05E9)`
/// -- or a template that places them itself, `{lit} character ({num})`.
/// The literal is kept as `.code`, so it is neither linkified nor collapsed
/// with the whitespace around it.
enum UnicodeElementExpansion {
  static let defaultFormat = "lit-name-num"

  static func inlines(for text: String, format: String?, ascii: String?) -> [Inline] {
    guard !text.isEmpty else { return [] }
    let format = format.flatMap { $0.isEmpty ? nil : $0 } ?? defaultFormat
    if format.contains("{") {
      return expandTemplate(format, text: text, ascii: ascii)
    }

    let parts = format.split(separator: "-").compactMap { keyword in
      part(String(keyword), text: text, ascii: ascii)
    }
    guard let first = parts.first else { return [.code(text)] }
    var result = first
    if parts.count > 1 {
      append([.text(" (")], to: &result)
      for (index, part) in parts.dropFirst().enumerated() {
        if index > 0 {
          append([.text(", ")], to: &result)
        }
        append(part, to: &result)
      }
      append([.text(")")], to: &result)
    }
    return result
  }

  /// Fills each `{keyword}` of a template in place. A keyword the vocabulary
  /// does not define is left as written rather than dropped.
  private static func expandTemplate(_ template: String, text: String, ascii: String?) -> [Inline] {
    var result: [Inline] = []
    var remainder = template[...]
    while let open = remainder.firstIndex(of: "{"),
      let close = remainder[open...].firstIndex(of: "}")
    {
      append([.text(String(remainder[..<open]))], to: &result)
      let keyword = String(remainder[remainder.index(after: open)..<close])
      let expansion = part(keyword, text: text, ascii: ascii) ?? [.text("{\(keyword)}")]
      append(expansion, to: &result)
      remainder = remainder[remainder.index(after: close)...]
    }
    append([.text(String(remainder))], to: &result)
    return result
  }

  private static func part(_ keyword: String, text: String, ascii: String?) -> [Inline]? {
    switch keyword {
    case "lit":
      return [.text("\""), .code(text), .text("\"")]
    case "char":
      return [.code(text)]
    case "num":
      return [.text(text.unicodeScalars.map(number(of:)).joined(separator: " "))]
    case "name":
      let names = text.unicodeScalars.map { scalar in
        scalar.properties.name ?? number(of: scalar)
      }
      return [.text(names.joined(separator: ", "))]
    case "ascii":
      return [.text("\"\(ascii ?? "")\"")]
    default:
      return nil
    }
  }

  /// `U+` and at least four uppercase hexadecimal digits.
  private static func number(of scalar: Unicode.Scalar) -> String {
    let digits = String(scalar.value, radix: 16, uppercase: true)
    return "U+" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
  }

  /// Appends inlines, merging adjacent text so the expansion reads as one run.
  private static func append(_ inlines: [Inline], to result: inout [Inline]) {
    for inline in inlines {
      if case .text(let text) = inline {
        if text.isEmpty {
          continue
        }
        if case .text(let previous)? = result.last {
          result[result.count - 1] = .text(previous + text)
          continue
        }
      }
      result.append(inline)
    }
  }
}
