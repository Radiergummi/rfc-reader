import RFCKit

/// The documents to read before a document, in the order to read them (#189): the
/// documents it cites normatively, and theirs, each after the ones it depends on, and
/// the document itself last.
///
/// A few documents are cited normatively by so much of the corpus that they would
/// open every path (RFC 2119, 8174, 5234, 3986). They are `assumed`: listed once,
/// apart, and not followed.
public struct ReadingPath: Sendable, Equatable {
  /// A document on the path, and how far it is from the root by its shortest chain
  /// of citations; the root is 0.
  public struct Step: Sendable, Hashable {
    public var document: DocumentID
    public var depth: Int

    public init(document: DocumentID, depth: Int) {
      self.document = document
      self.depth = depth
    }
  }

  /// What a document cites normatively, in the order it first cites them.
  public struct References: Sendable, Equatable {
    public var normative: [DocumentID]
    /// Its reference lists say neither normative nor informative, as a single
    /// "References" list before about RFC 2200 does, so its references are not
    /// followed: following them all would make the path its whole bibliography.
    public var isUndeclared: Bool

    public init(normative: [DocumentID], isUndeclared: Bool) {
      self.normative = normative
      self.isUndeclared = isUndeclared
    }
  }

  /// How many citations deep a walk goes unless asked for more.
  public static let defaultDepth = 4

  public var root: DocumentID
  /// Each document after the ones it depends on, the root last.
  public var steps: [Step]
  /// The assumed documents the walk reached, in the order it first met them.
  public var assumed: [DocumentID]
  /// The documents on the path whose references declare no kind, in path order.
  public var undeclared: [DocumentID]
  /// The walk stopped at its depth with documents still to follow.
  public var isCut: Bool

  /// Walks the normative references from `root` to `depth` citations deep.
  ///
  /// A document's depth is its shortest distance from the root, found breadth-first.
  /// The order is then depth-first, in citation order, each document emitted after
  /// what it cites: so a cycle is broken where citation order first closes it, the
  /// document entered first coming after the one that cites it back. A document in
  /// `assumed` is not followed, except the root.
  public static func walk<Failure: Error>(
    from root: DocumentID, depth: Int = defaultDepth, assumed: Set<DocumentID>,
    references: (DocumentID) throws(Failure) -> References
  ) throws(Failure) -> ReadingPath {
    var cache: [DocumentID: References] = [:]
    func referencesOf(_ id: DocumentID) throws(Failure) -> References {
      if let known = cache[id] { return known }
      let found = try references(id)
      cache[id] = found
      return found
    }

    var depths: [DocumentID: Int] = [root: 0]
    var reachedAssumed: [DocumentID] = []
    var isCut = false
    var queue = [root]
    var next = 0
    while next < queue.count {
      let id = queue[next]
      next += 1
      let distance = depths[id]!
      for cited in try referencesOf(id).normative where depths[cited] == nil {
        if assumed.contains(cited) {
          if !reachedAssumed.contains(cited) { reachedAssumed.append(cited) }
        } else if distance < depth {
          depths[cited] = distance + 1
          queue.append(cited)
        } else {
          isCut = true
        }
      }
    }

    var steps: [Step] = []
    var entered: Set<DocumentID> = []
    func visit(_ id: DocumentID) throws(Failure) {
      guard entered.insert(id).inserted else { return }
      let distance = depths[id]!
      if distance < depth {
        for cited in try referencesOf(id).normative where depths[cited] != nil {
          try visit(cited)
        }
      }
      steps.append(Step(document: id, depth: distance))
    }
    try visit(root)

    let undeclared = steps.map(\.document).filter { cache[$0]?.isUndeclared == true }
    return ReadingPath(
      root: root, steps: steps, assumed: reachedAssumed, undeclared: undeclared, isCut: isCut)
  }
}
