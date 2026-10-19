import Foundation

/// What changed between two texts, word by word (#729): the runs that turn one into
/// the other, read in order, each kept, inserted or deleted.
///
/// A word is a run of anything but whitespace, and whitespace counts as one space
/// whatever it was, so a paragraph that only rewrapped is unchanged. The runs keep
/// the new text's whitespace, and a deleted run its own.
public enum WordDiff {
  public enum Run: Hashable, Sendable {
    case same(String)
    case inserted(String)
    case deleted(String)

    public var text: String {
      switch self {
      case .same(let text), .inserted(let text), .deleted(let text): text
      }
    }
  }

  /// The runs from `old` to `new`, a deletion before the insertion that replaces it,
  /// and runs of one kind joined. Empty for two empty texts.
  public static func runs(from old: String, to new: String) -> [Run] {
    let oldTokens = tokens(of: old)
    let newTokens = tokens(of: new)
    let difference = newTokens.map(\.key).difference(from: oldTokens.map(\.key))
    var removed: Set<Int> = []
    var inserted: Set<Int> = []
    for change in difference {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
      }
    }
    var runs: [Run] = []
    func add(_ run: Run) {
      switch (runs.last, run) {
      case (.same(let last), .same(let text)): runs[runs.count - 1] = .same(last + text)
      case (.inserted(let last), .inserted(let text)): runs[runs.count - 1] = .inserted(last + text)
      case (.deleted(let last), .deleted(let text)): runs[runs.count - 1] = .deleted(last + text)
      default: runs.append(run)
      }
    }
    var oldIndex = 0
    var newIndex = 0
    while oldIndex < oldTokens.count || newIndex < newTokens.count {
      if oldIndex < oldTokens.count, removed.contains(oldIndex) {
        add(.deleted(oldTokens[oldIndex].text))
        oldIndex += 1
      } else if newIndex < newTokens.count, inserted.contains(newIndex) {
        add(.inserted(newTokens[newIndex].text))
        newIndex += 1
      } else {
        add(.same(newTokens[newIndex].text))
        oldIndex += 1
        newIndex += 1
      }
    }
    return runs
  }

  /// Whether `runs` hold any change.
  public static func changes(_ runs: [Run]) -> Bool {
    runs.contains { if case .same = $0 { false } else { true } }
  }

  /// A word, or a stretch of whitespace, with what it is compared by.
  private struct Token {
    let text: String
    /// The word itself, or one space for any whitespace.
    var key: String { text.first?.isWhitespace == true ? " " : text }
  }

  private static func tokens(of text: String) -> [Token] {
    var tokens: [Token] = []
    var current = ""
    var isSpace = false
    for character in text {
      let space = character.isWhitespace
      if !current.isEmpty, space != isSpace {
        tokens.append(Token(text: current))
        current = ""
      }
      current.append(character)
      isSpace = space
    }
    if !current.isEmpty { tokens.append(Token(text: current)) }
    return tokens
  }
}
