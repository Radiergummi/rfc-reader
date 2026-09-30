/// Where the reader's text puts the reader when it appears.
///
/// It appears whenever its text view is made, and that is not only when the
/// document opens: turning Original Text off makes it again (#449). By then the
/// scroll request that opened the document, and the reading position stored when it
/// was last left, both name where the reader was when it opened. The place the
/// reader has reached since is the one to return to.
public enum ReaderArrival: Sendable, Equatable {
  /// Scroll to this anchor, unanimated.
  case place(String)
  /// Carry out the navigation's scroll request: a deep link, or a place in the
  /// history.
  case request
  /// Move nothing: a scroll is already waiting for the text view, or there is no
  /// place to go to.
  case stay

  /// - Parameters:
  ///   - anchorLeft: where the reader was when the text view last went, or nil if
  ///     it has not gone yet. Taken as it goes, not as it comes back: a text view
  ///     reports the top of its text as it is made, before any restore.
  ///   - hasPendingScroll: whether a scroll was asked for while the text view was
  ///     gone, such as a jump from the contents panel over the original text. The
  ///     text view carries it out as it is made.
  ///   - hasRequest: whether the navigation holds a scroll request.
  ///   - storedAnchor: the stored reading position's anchor, if the document holds
  ///     it. Read only when nothing before it decides.
  public static func onAppear(
    anchorLeft: String?, hasPendingScroll: Bool, hasRequest: Bool,
    storedAnchor: @autoclosure () -> String?
  ) -> Self {
    if hasPendingScroll { return .stay }
    if let anchorLeft { return .place(anchorLeft) }
    if hasRequest { return .request }
    return storedAnchor().map(Self.place) ?? .stay
  }
}
