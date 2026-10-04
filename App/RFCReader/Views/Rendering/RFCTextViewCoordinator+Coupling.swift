import Foundation
import RFCReaderKit

/// One of two readers scrolling together, side by side (#187). Which one leads and
/// where the other goes is `ScrollCoupling`'s and `AlignedScrolling`'s; this is only
/// the text view's end of it.
extension RFCTextViewCoordinator: CoupledReader {
  var alignedSide: AlignedScrolling.Side? {
    guard let built, let documentID else { return nil }
    return AlignedScrolling.Side(
      document: documentID, sections: sectionIndex, length: built.text.length)
  }

  /// Puts the line where the other reader's counterpart is. Not the reader's move,
  /// so it takes no lead: `ScrollCoupling` ignores what it reports meanwhile.
  func follow(_ follow: AlignedScrolling.Follow) {
    switch follow {
    case .offset(let offset):
      // Into folded text the section opens, as a jump does.
      if !show(offset) { engine.jump(toOffset: offset) }
    case .top:
      engine.jumpToTop()
    case .unaligned:
      return
    }
    reportVisibleAnchor()
  }

  /// Joins `coupling`, or leaves the one it was in. A reader joins again with every
  /// build it installs, so the follower is put back where the leader is.
  func couple(to coupling: ScrollCoupling?, installed: Bool) {
    guard let documentID else { return }
    if coupling !== self.coupling {
      self.coupling?.detach(self, showing: documentID)
      self.coupling = coupling
    } else if !installed {
      return
    }
    coupling?.attach(self, showing: documentID)
  }

  /// The reader used this side: scrolled it, clicked in it, or sent it somewhere.
  func takeLead() {
    guard let documentID else { return }
    coupling?.lead(documentID)
  }
}
