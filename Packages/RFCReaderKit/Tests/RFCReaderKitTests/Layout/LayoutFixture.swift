import Foundation

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A text laid out headless: a content storage, a layout manager and a container.
/// The storage is kept because the layout manager holds it weakly. Written through
/// `install`, never `attributedString`: see CLAUDE.md.
@MainActor
final class LayoutFixture {
  let storage = NSTextContentStorage()
  let layout = NSTextLayoutManager()

  init(text: NSAttributedString, width: CGFloat) {
    storage.install(text)
    storage.addTextLayoutManager(layout)
    layout.textContainer = NSTextContainer(size: CGSize(width: width, height: 10_000_000))
  }

  /// The built text of a committed fixture, at the reader's default style.
  static func built(
    _ name: String = "rfc8999.xml", measure: CGFloat = 712
  ) throws -> BuiltDocument {
    DocumentTextBuilder.build(
      try Fixtures.document(named: name), style: ReadingStyle(measure: measure))
  }

  func setWidth(_ width: CGFloat) {
    layout.textContainer?.size = CGSize(width: width, height: 10_000_000)
  }

  /// The paragraph fragment holding `characterOffset`, laid out.
  func fragment(at characterOffset: Int) -> NSTextLayoutFragment? {
    guard let location = layout.location(atOffset: characterOffset),
      let fragment = layout.textLayoutFragment(for: location)
    else { return nil }
    layout.ensureLayout(for: fragment.rangeInElement)
    return layout.textLayoutFragment(for: location)
  }
}
