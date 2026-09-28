import Foundation

public struct Amendment: Sendable, Hashable, Codable {
  public var amended: DocumentID
  public var section: String
  public var by: DocumentID?
  public var from: String?
}

public enum Amendments {
  public static func links(in document: RFCDocument) -> [Amendment] { [] }
}
