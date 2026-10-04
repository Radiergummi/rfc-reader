/// The dividers of a Mac reader window's split view, which its toolbar's tracking
/// separators follow: the window's items are the sidebar, the list, the reader, while
/// a document is compared the reader beside it (#187), and the contents panel.
public enum ReaderWindowDividers {
  /// The divider in front of the contents panel, whose toolbar section starts there:
  /// after the reader, or after the reader beside it while comparing.
  public static func panel(comparing: Bool) -> Int {
    comparing ? 3 : 2
  }
}
