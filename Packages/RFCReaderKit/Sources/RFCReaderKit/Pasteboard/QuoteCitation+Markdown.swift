import Foundation

extension QuoteCitation {
  static func escapedMarkdownLine(_ line: String) -> String {
    line.replacingOccurrences(of: "<", with: "&lt;")
  }
}
