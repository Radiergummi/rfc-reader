import CoreGraphics
import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// How far a document's heading numbers hang left of the column (#433): one width
/// for the whole document, so every heading's title starts on the column and every
/// number ends the same gap before it, `A.10.2` as `3`.
public enum SectionNumberHang {
  /// The widest number of the document's headings, each in its own heading's font,
  /// and the gap that sets it off from the title; zero where no heading is numbered.
  /// A bibliography's heading is left out, as the reader leaves it out.
  public static func width(of document: RFCDocument, style: ReadingStyle) -> CGFloat {
    var widest: CGFloat = 0
    func measure(_ sections: [Section], depth: Int) {
      for section in sections where !section.holdsOnlyReferences {
        if let number = section.number {
          let text = NSAttributedString(
            string: number, attributes: [.font: style.headingFont(depth: depth)])
          widest = max(widest, DocumentTextBuilder.lineWidth(text))
        }
        measure(section.subsections, depth: depth + 1)
      }
    }
    measure(document.sections, depth: 1)
    return widest > 0 ? widest + gap(style: style) : 0
  }

  /// Between a number's end and its title's start: a little less than an indent
  /// step, so the number reads as the title's and not as a column of its own.
  public static func gap(style: ReadingStyle) -> CGFloat {
    style.bodySize
  }
}

/// How a heading's hung number is drawn: in its own quieter color, or in the
/// label's while the pointer is over it.
public enum SectionNumberState: Sendable {
  case resting
  case hovered
}
