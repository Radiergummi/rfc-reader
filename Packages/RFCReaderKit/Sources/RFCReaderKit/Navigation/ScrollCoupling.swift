import Foundation
import RFCKit

/// One of the two readers of a side-by-side reading (#187): its text view's
/// coordinator, as far as the coupling needs it.
@MainActor
public protocol CoupledReader: AnyObject {
  /// Its build's sections, or nil while it has none.
  var alignedSide: AlignedScrolling.Side? { get }
  /// Moves its reader's line, without taking the lead.
  func follow(_ follow: AlignedScrolling.Follow)
}

/// Couples the scrolling of two readers: the one the reader last used leads, and the
/// other follows it, through `AlignedScrolling`.
///
/// Only the leader's moves are followed. That is what keeps the two from driving each
/// other in a loop: a follower's own move reports a new place too, as does a rebuild
/// of it after a resize, and neither is the reader's. A reader takes the lead when it
/// is used — scrolled, clicked or sent to a place — and not when it is moved.
@MainActor
public final class ScrollCoupling {
  /// The two documents' counterparts; nil until they are aligned, and no reader
  /// follows the other before then.
  public var scrolling: AlignedScrolling? {
    didSet { followLeader() }
  }

  /// The section of the leading document whose counterpart is missing, while the
  /// leader is in one; nil otherwise. Told on every change.
  public var onUnaligned: (_ document: DocumentID, _ section: String?) -> Void = { _, _ in }

  public private(set) var leader: DocumentID
  private let documents: Set<DocumentID>
  private var readers: [DocumentID: WeakReader] = [:]
  /// Where each reader's line was last reported, nil above its text.
  private var places: [DocumentID: Int?] = [:]
  /// Set while a follower is moved, so that what it reports is not taken for a move
  /// of its own.
  private var isFollowing = false
  private var unaligned: String?

  private struct WeakReader {
    weak var reader: (any CoupledReader)?
  }

  /// `leader` leads until the other is used: the document the reading started from.
  public init(leader: DocumentID, follower: DocumentID) {
    self.leader = leader
    documents = [leader, follower]
  }

  /// The other document of the two.
  public func other(than document: DocumentID) -> DocumentID {
    documents.first { $0 != document } ?? document
  }

  /// A reader is showing `document`. The follower is put where the leader is.
  public func attach(_ reader: any CoupledReader, showing document: DocumentID) {
    guard documents.contains(document) else { return }
    readers[document] = WeakReader(reader: reader)
    followLeader()
  }

  /// The reader is going; only `reader` itself, not a newer one showing the same
  /// document.
  public func detach(_ reader: any CoupledReader, showing document: DocumentID) {
    guard readers[document]?.reader === reader else { return }
    readers[document] = nil
  }

  /// The reader of `document` was used.
  public func lead(_ document: DocumentID) {
    guard documents.contains(document), !isFollowing, leader != document else { return }
    leader = document
  }

  /// The reader of `document` reports its line at `offset`, nil above its text.
  public func moved(_ document: DocumentID, to offset: Int?) {
    guard documents.contains(document) else { return }
    places[document] = offset
    guard document == leader, !isFollowing else { return }
    followLeader()
  }

  private func followLeader() {
    let followerDocument = other(than: leader)
    guard let scrolling, let place = places[leader],
      let leading = readers[leader]?.reader?.alignedSide,
      let follower = readers[followerDocument]?.reader,
      let following = follower.alignedSide
    else { return }
    let follow = scrolling.follow(place, from: leading, to: following)
    if case .unaligned(let section) = follow {
      report(unaligned: section)
      return
    }
    report(unaligned: nil)
    isFollowing = true
    defer { isFollowing = false }
    follower.follow(follow)
  }

  private func report(unaligned section: String?) {
    guard section != unaligned else { return }
    unaligned = section
    onUnaligned(leader, section)
  }
}
