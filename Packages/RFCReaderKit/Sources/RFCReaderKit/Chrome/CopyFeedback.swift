import Foundation

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

  public func announcement(in locale: Locale = .interface) -> String {
    switch self {
    case .citation: String(kit: "Citation copied", locale: locale)
    case .link: String(kit: "Link copied", locale: locale)
    case .figure: String(kit: "Figure copied", locale: locale)
    case .quote: String(kit: "Quote copied", locale: locale)
    case .checklist: String(kit: "Checklist copied", locale: locale)
    case .code: String(kit: "Code copied", locale: locale)
    }
  }
}
