import Foundation
import RFCKit

public enum QuoteCitation {
  public struct Quote {
    public var markdown: String
    public var rich: NSAttributedString
  }

  public static func section(at offset: Int, anchors: AnchorIndex, numbers: [String: String])
    -> String?
  { nil }

  public static func quote(of selection: NSAttributedString, document: DocumentID, section: String?)
    -> Quote
  { Quote(markdown: "", rich: NSAttributedString()) }
}
