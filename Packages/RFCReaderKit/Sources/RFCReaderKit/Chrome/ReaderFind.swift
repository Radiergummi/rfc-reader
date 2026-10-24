/// Whether Find has a text on screen to open over (#943): the More menu's Find in
/// Document, and Find…, Find Next and Find Previous on an iPad's keyboard (#763).
public enum ReaderFind {
  /// `hasDocument`: the document's body has loaded. `publishedOriginal`: why the RFC
  /// is read as its PDF or PostScript original, if it is. `showsOriginal`: Original
  /// Text is chosen. `hasOriginalText`: the original text has loaded.
  public static func isAvailable(
    hasDocument: Bool, publishedOriginal: PublishedOriginalPage.Kind?, showsOriginal: Bool,
    hasOriginalText: Bool
  ) -> Bool {
    hasDocument
  }
}
