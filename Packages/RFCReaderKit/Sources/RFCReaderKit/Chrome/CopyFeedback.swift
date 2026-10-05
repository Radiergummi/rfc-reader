/// What a copy put on the pasteboard, for saying that it worked (#777). A copy from
/// a menu draws nothing, as the HIG has it, so the announcement is all VoiceOver
/// hears of it; the system's own Copy says nothing of ours.
public enum CopyFeedback: Hashable, Sendable {
  case citation
  case link
  case figure
  case quote
  case checklist
  case code

  public var announcement: String {
    switch self {
    case .citation: "Citation copied"
    case .link: "Link copied"
    case .figure: "Figure copied"
    case .quote: "Quote copied"
    case .checklist: "Checklist copied"
    case .code: "Code copied"
    }
  }
}
