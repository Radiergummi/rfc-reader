/// Who says how far the document's title has come into the toolbar (#281).
///
/// One rule: the title shows unless a reader with a header on screen says
/// otherwise. While a document loads, its header counts as pending, so the title
/// stays out rather than flashing in before the header appears, and it stays pending
/// until the reader reports or the load fails. The original text has no header.
///
/// Three places used to write the reveal, two of them to patch around the third, and
/// every reader mode without a header had to remember to show the title itself.
public struct ToolbarTitleOwnership: Sendable {
  /// What the reader on screen last said, and which reader said it.
  private var report: (reader: ObjectIdentifier, state: ToolbarTitleState)?
  /// Whether a header is on its way: from the start of a load until it fails.
  private var headerPending = false
  /// The 72-column original, which has no header, instead of the rendered document.
  public var showsOriginal = false

  public init() {}

  public var state: ToolbarTitleState {
    if showsOriginal { return .shown }
    return report?.state ?? (headerPending ? .hidden : .shown)
  }

  /// A document starts loading, under a header of its own. What the last
  /// document's reader said no longer applies.
  public mutating func beginLoading() {
    headerPending = true
    report = nil
  }

  /// The load failed, and there is no header coming.
  public mutating func failLoading() {
    headerPending = false
  }

  public mutating func report(_ state: ToolbarTitleState, from reader: ObjectIdentifier) {
    report = (reader, state)
  }

  /// `reader` has gone away and gives the title back. A reader is made per
  /// document, so the last one's teardown can arrive after the next one has
  /// reported; only the reader that made the report can clear it.
  public mutating func release(from reader: ObjectIdentifier) {
    guard report?.reader == reader else { return }
    report = nil
  }
}
