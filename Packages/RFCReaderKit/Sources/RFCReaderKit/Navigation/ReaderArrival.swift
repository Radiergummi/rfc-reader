/// Where the reader's text puts the reader when it appears.
///
/// It appears whenever its text view is made, and that is not only when the
/// document opens: turning Original Text off makes it again (#449). By then the
/// scroll request that opened the document, and the reading position stored when it
/// was last left, both name where the reader was when it opened. The place the
/// reader has reached since is the one to return to.
///
/// `Request` is the navigation's scroll request, which the reader carries out as it
/// would any other.
public enum ReaderArrival<Request> {
  /// Scroll to this anchor, unanimated.
  case place(String)
  /// Carry out the navigation's scroll request: a deep link, or a place in the
  /// history.
  case request(Request)
  /// Move nothing: there is no place to go to.
  case stay

  /// - Parameters:
  ///   - pendingAnchor: where a scroll asked for while the text view was gone is
  ///     going, such as a jump from the contents panel over the original text. It
  ///     was asked for animated, over a text view that was not there; arriving, it
  ///     is not a movement the reader sees.
  ///   - anchorLeft: where the reader was when the text view last went, or nil if
  ///     it has not gone with a place yet. Taken as it goes, not as it comes back:
  ///     a text view reports the top of its text as it is made, before any restore.
  ///   - request: the navigation's scroll request, if it holds one.
  ///   - storedAnchor: the stored reading position's anchor, if the document holds
  ///     it. Read only when nothing before it decides.
  public static func onAppear(
    pendingAnchor: String?, anchorLeft: String?, request: Request?,
    storedAnchor: @autoclosure () -> String?
  ) -> Self {
    if let pendingAnchor { return .place(pendingAnchor) }
    if let anchorLeft { return .place(anchorLeft) }
    if let request { return .request(request) }
    return storedAnchor().map(Self.place) ?? .stay
  }
}

extension ReaderArrival: Equatable where Request: Equatable {}
extension ReaderArrival: Sendable where Request: Sendable {}
