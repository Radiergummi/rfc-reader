import RFCKit

/// The readers stacked in a tab's detail column on iOS (#263): the root, and one
/// pushed over it for each citation of another RFC followed in a reader.
///
/// A projection of the tab's `NavigationHistory`, not a second history: the stack's
/// path is read from it, and the stack's own back is handed to it
/// (`NavigationHistory.popReaders(to:leaving:)`), so the history stays the one
/// record and the stack only shows it. "Back to §…" (#254) is about the document on
/// screen, and the system back button about documents: a jump within a document
/// pushes no reader.
///
/// The Mac has one reader, and no stack.
public struct ReaderPath: Equatable, Sendable {
  /// One reader in the stack.
  ///
  /// Identified by its document and its place in the stack, not by the place in
  /// the document, which changes as it is read: pushing another reader leaves every
  /// one below it the same reader, and a document cited again is a reader of its
  /// own.
  public struct Reader: Hashable, Sendable {
    public let id: DocumentID
    /// From 0, the root.
    public let depth: Int
  }

  /// How many readers the stack keeps (#263, decision 3), counted from the top. Each
  /// keeps its build, which for a long RFC is the largest thing the app holds; one
  /// deeper is let go, and made again if the stack is popped back to it, at the
  /// place it was left.
  public static let retainedReaders = 8

  /// Oldest first: the root, then each reader pushed over it.
  public let readers: [Reader]

  public init(_ history: NavigationHistory) {
    readers = history.stackedDocuments.enumerated().map { Reader(id: $1, depth: $0) }
  }

  /// The stack's root view.
  public var root: Reader? { readers.first }

  /// The readers pushed over the root: the stack's path.
  public var pushed: [Reader] { Array(readers.dropFirst()) }

  /// The reader on top, on screen.
  public var top: Reader? { readers.last }

  /// Whether the reader of `id` at `depth` is the one on top, on screen.
  public func isTop(_ id: DocumentID, at depth: Int) -> Bool {
    top == Reader(id: id, depth: depth)
  }

  /// Whether the stack holds a reader of `id` at `depth`, on top or below it.
  public func holds(_ id: DocumentID, at depth: Int) -> Bool {
    readers.indices.contains(depth) && readers[depth].id == id
  }

  /// Whether `reader` keeps its view, and with it its build: the eight nearest the
  /// top do.
  public func retains(_ reader: Reader) -> Bool {
    reader.depth >= readers.count - Self.retainedReaders
  }

  /// Whether `next` is this stack with readers taken off its top: a pop, which
  /// shows a reader kept below, where it was left.
  public func pops(to next: ReaderPath) -> Bool {
    !next.readers.isEmpty && next.readers.count < readers.count
      && readers.starts(with: next.readers)
  }
}
