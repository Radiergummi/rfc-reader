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

  /// A document the walk has entered and not yet emitted: what it cites on the
  /// path, and how many of those it has followed.
  private struct Entered {
    var document: DocumentID
    var cited: [DocumentID]
    var next = 0
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

    // A stack of its own rather than recursion, which would go as deep as the
    // longest chain on the path, unbounded as Show Deeper raises the depth, on a
    // task's small stack.
    var steps: [Step] = []
    var entered: Set<DocumentID> = []
    var stack: [Entered] = []
    func enter(_ id: DocumentID) throws(Failure) {
      guard entered.insert(id).inserted else { return }
      // Every edge between documents on the path, a document at the depth's too: it
      // brings in nothing new, but what it cites still comes before it.
      let cited = try referencesOf(id).normative.filter { depths[$0] != nil }
      stack.append(Entered(document: id, cited: cited))
    }
    try enter(root)
    while let top = stack.last {
      if top.next < top.cited.count {
        stack[stack.count - 1].next += 1
        try enter(top.cited[top.next])
      } else {
        stack.removeLast()
        steps.append(Step(document: top.document, depth: depths[top.document]!))
      }
    }

    let undeclared = steps.map(\.document).filter { cache[$0]?.isUndeclared == true }
    return ReadingPath(
      root: root, steps: steps, assumed: reachedAssumed, undeclared: undeclared, isCut: isCut)
  }
}

extension ReadingPath {
  /// One row of the reading path's sheet.
  public struct Row: Sendable, Equatable, Identifiable {
    public var document: DocumentID
    /// The index's title, or nil for a document it does not list, such as a BCP
    /// cited as a whole.
    public var title: String?
    /// Kept on the path, since it is the text the citing document depends on, and
    /// marked with what replaced it.
    public var obsoletedBy: [DocumentID]
    /// Opened before, by its reading position.
    public var isRead: Bool

    public var id: DocumentID { document }

    public init(document: DocumentID, title: String?, obsoletedBy: [DocumentID], isRead: Bool) {
      self.document = document
      self.title = title
      self.obsoletedBy = obsoletedBy
      self.isRead = isRead
    }
  }

  /// The assumed documents, then the path: the order of the sheet, and of the
  /// collection it is saved as.
  public var documents: [DocumentID] { assumed + steps.map(\.document) }

  /// The sheet's title for the path from `root`.
  public static func title(for root: DocumentID) -> String {
    "Reading Path: \(root.displayName)"
  }

  /// The name of the collection the path is saved as: the sheet's title.
  public var collectionName: String { Self.title(for: root) }

  /// The sheet's rows: the assumed documents and the path's, each with what the
  /// index and the reading positions say of it.
  public func rows(
    metadata: (DocumentID) -> RFCMetadata?, isRead: (DocumentID) -> Bool
  ) -> (assumed: [Row], steps: [Row]) {
    func row(_ id: DocumentID) -> Row {
      let entry = metadata(id)
      return Row(
        document: id, title: entry?.title, obsoletedBy: entry?.obsoletedBy ?? [],
        isRead: isRead(id))
    }
    return (assumed.map(row), steps.map { row($0.document) })
  }
}
