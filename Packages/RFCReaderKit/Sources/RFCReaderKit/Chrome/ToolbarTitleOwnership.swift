/// Who says how far the document's title has come into the toolbar (#281).
///
/// One rule: a reader with a header on screen says where the title is. Without one,
/// the title shows where the document has no header to show it instead — its
/// original text, or a failed load, where the toolbar names the RFC that failed —
/// and stays out otherwise: with no document, and while a document's header is on
/// its way, from the start of its load until its reader reports, so it does not
/// show and then drop.
///
/// Three places used to write the reveal, two of them to patch around the third, and
/// every reader mode without a header had to remember to show the title itself.
public struct ToolbarTitleOwnership: Sendable {
  /// The document the title belongs to, as far as its header goes.
  private enum Document: Sendable {
    case none
    /// Loading or open: a header is showing, or on its way.
    case withHeader
    /// Failed to load: no header is coming.
    case failed
  }

  private var document = Document.none
  /// What the reader on screen last said, and which reader said it.
  private var report: (reader: ObjectIdentifier, state: ToolbarTitleState)?
  /// The 72-column original, which has no header, instead of the rendered document.
  public var showsOriginal = false

  public init() {}

  public var state: ToolbarTitleState {
    switch document {
    case .none: .hidden
    case .failed: .shown
    case .withHeader where showsOriginal: .shown
    case .withHeader: report?.state ?? .hidden
    }
  }

  /// A document starts loading, under a header of its own. What the last
  /// document's reader said no longer applies.
  public mutating func beginLoading() {
    document = .withHeader
    report = nil
  }

  /// The load failed, and there is no header coming.
  public mutating func failLoading() {
    document = .failed
    report = nil
  }

  /// No document is on screen.
  public mutating func close() {
    document = .none
    report = nil
  }

  public mutating func report(_ state: ToolbarTitleState, from reader: ObjectIdentifier) {
    report = (reader, state)
  }

  /// `reader` has gone away, and what it said with it. A reader is made per
  /// document, so the last one's teardown can arrive after the next one has
  /// reported; only the reader that made the report can clear it.
  public mutating func release(from reader: ObjectIdentifier) {
    guard report?.reader == reader else { return }
    report = nil
  }
}
