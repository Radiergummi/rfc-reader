import Foundation
import RFCKit

/// Two documents read side by side (#187): one and the document that obsoletes it.
///
/// Only an obsoletes edge is offered, because only along one are there counterparts
/// to scroll together (`SectionAlignment`). Two unrelated documents would scroll
/// independently, which two windows already do; a draft's revisions come with the
/// diff view.
public struct SideBySidePair: Sendable, Hashable {
  /// The document the reading started from, which is the one on the left.
  public let reading: DocumentID
  /// The one opened beside it.
  public let other: DocumentID
  /// Of the two, the obsoleted document.
  public let old: DocumentID
  /// And the one obsoleting it.
  public let new: DocumentID

  /// Nil when neither of the two obsoletes the other, according to `metadata`, the
  /// reading document's entry in the index.
  public init?(reading metadata: RFCMetadata, with other: DocumentID) {
    reading = metadata.id
    self.other = other
    if metadata.obsoletedBy.contains(other) {
      old = metadata.id
      new = other
    } else if metadata.obsoletes.contains(other) {
      old = other
      new = metadata.id
    } else {
      return nil
    }
  }

  /// The documents a reading of `metadata`'s document can be compared with: its
  /// successors first, newest first, then its predecessors, newest first.
  public static func offered(for metadata: RFCMetadata) -> [DocumentID] {
    Set(metadata.obsoletedBy).subtracting([metadata.id]).sorted(by: >)
      + Set(metadata.obsoletes).subtracting([metadata.id]).sorted(by: >)
  }

  /// What to align the two among: the two, and the old document's other successors
  /// and the new one's other predecessors, as far as `available` holds them.
  ///
  /// A section's counterpart is its best match across every edge aligned together,
  /// so leaving them out pairs a section that moved elsewhere with its nearest, wrong,
  /// section here: RFC 7230's message syntax went to 9112, and aligned with 9110
  /// alone it pairs with a 9110 section (`SectionAlignment`, and its decision record).
  public func alignedAmong(
    oldSuccessors: [DocumentID], newPredecessors: [DocumentID], available: Set<DocumentID>
  ) -> [DocumentID] {
    let others = Set(oldSuccessors + newPredecessors).subtracting([old, new])
      .intersection(available)
    return [old, new] + others.sorted()
  }
}
