import Foundation

enum ABNF {
  struct Rule: Sendable, Hashable {
    var name: String
    var isIncremental: Bool
    var references: [String]
    var usesGrammarSyntax: Bool
  }

  static func parse(_ text: String) -> [Rule]? { nil }

  static func recognizes(_ text: String) -> Bool { false }
}
