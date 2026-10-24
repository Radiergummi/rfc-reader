/// Whether Find has a text on screen to open over (#943): the More menu's Find in
/// Document, and Find…, Find Next and Find Previous on an iPad's keyboard (#763).
public enum ReaderFind {
  /// `hasDocument`: the document's body has loaded. `publishedOriginal`: why the RFC
  /// is read as its PDF or PostScript original, if it is. `showsOriginal`: Original
  /// Text is chosen. `hasOriginalText`: the original text has loaded.
  ///
  /// The reader shows what `PublishedOriginalPage` says first: a scan's page in
  /// either mode, a pointer's in place of the rendered text. Otherwise Original Text
  /// is a text view once its text is here, and the rendered document once it is.
  public static func isAvailable(
    hasDocument: Bool, publishedOriginal: PublishedOriginalPage.Kind?, showsOriginal: Bool,
    hasOriginalText: Bool
  ) -> Bool {
    switch publishedOriginal {
    case .scan: false
    case .pointer where !showsOriginal: false
    case .pointer, nil: showsOriginal ? hasOriginalText : hasDocument
    }
  }
}
