import Foundation

public struct DefinedTerm: Sendable, Hashable, Codable {
  public var term: String
  public var anchor: String?
  public var definition: [Block]

  public init(term: String, anchor: String?, definition: [Block]) {
    self.term = term
    self.anchor = anchor
    self.definition = definition
  }
}

enum DefinedTerms {
  static func namesTerms(_ title: String) -> Bool { false }

  static func defined(in document: RFCDocument, indexed: [DefinedTerm] = []) -> [String:
    DefinedTerm]
  {
    [:]
  }
}

extension RFCXMLParser {
  static func primaryIndexTerms(in root: XMLTree.Element) -> [DefinedTerm] { [] }
}

extension RFCDocument {
  public var definedTerms: [String: DefinedTerm] { [:] }
}
