import RFCKit

/// A datatracker document state, by the two names datatracker keeps stable: its
/// type's slug, `draft-iesg`, and its own, `idexists`. The display names ("I-D
/// Exists") are for people.
public struct DraftState: Hashable, Sendable, Codable {
  public var type: String
  public var slug: String

  public init(_ type: String, _ slug: String) {
    self.type = type
    self.slug = slug
  }

  /// A state of the stream a draft is in: IETF, IRTF, IAB, Independent or Editorial.
  public var isStreamState: Bool { type.hasPrefix("draft-stream-") }
}

/// Which drafts count as revisions under way, and how far along each is
/// (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md, "Adopted" and "Stages").
/// The pairs are datatracker's, from `doc/state/` on 29 September 2026.
public enum DraftStates {
  /// A state that means "not adopted yet" or "stopped". Checked whatever the draft's
  /// stream: states and stream need not agree.
  static let notAdopted: Set<DraftState> = [
    DraftState("draft-stream-ietf", "wg-cand"),
    DraftState("draft-stream-ietf", "c-adopt"),
    // Adopted without publication: the working group keeps it for reference.
    DraftState("draft-stream-ietf", "info"),
    DraftState("draft-stream-ietf", "parked"),
    DraftState("draft-stream-ietf", "dead"),
    DraftState("draft-stream-irtf", "candidat"),
    DraftState("draft-stream-irtf", "parked"),
    DraftState("draft-stream-irtf", "dead"),
    DraftState("draft-stream-irtf", "repl"),
    DraftState("draft-stream-iab", "candidat"),
    DraftState("draft-stream-iab", "parked"),
    DraftState("draft-stream-iab", "dead"),
    DraftState("draft-stream-iab", "repl"),
    DraftState("draft-stream-iab", "diff-org"),
    DraftState("draft-stream-ise", "receive"),
    DraftState("draft-stream-ise", "repl"),
    DraftState("draft-stream-ise", "dead"),
    DraftState("draft-stream-editorial", "repl"),
    DraftState("draft-stream-editorial", "dead"),
    DraftState("draft-iesg", "dead"),
    DraftState("draft-iesg", "nopubadw"),
    DraftState("draft-iesg", "nopubanw"),
  ]

  /// IESG states that say nothing has happened yet.
  static let untouched: Set<DraftState> = [
    DraftState("draft-iesg", "idexists"),
    DraftState("draft-iesg", "watching"),
  ]

  /// Adopted: no state excludes it, and it has a stream state or, when it has none
  /// (AD-sponsored), an IESG state past the untouched ones.
  public static func isAdopted(_ states: [DraftState]) -> Bool {
    if states.contains(where: notAdopted.contains) { return false }
    if states.contains(where: \.isStreamState) { return true }
    return states.contains { $0.type == "draft-iesg" && !untouched.contains($0) }
  }

  /// The furthest stage any of the states reaches.
  public static func stage(_ states: [DraftState]) -> RevisionStage {
    states.map(stage(of:)).max() ?? .inGroup
  }

  public static func stage(of state: DraftState) -> RevisionStage {
    switch (state.type, state.slug) {
    case ("draft-iesg", "rfcqueue"), ("draft-rfceditor", _):
      .rfcEditorQueue
    case (_, "rfc-edit") where state.isStreamState:
      .rfcEditorQueue
    case ("draft-iesg", "approved"), ("draft-iesg", "ann"), ("draft-stream-iab", "approved"):
      .approved
    case ("draft-iesg", "writeupw"), ("draft-iesg", "goaheadw"), ("draft-iesg", "iesg-eva"),
      ("draft-iesg", "defer"):
      .iesgReview
    case (_, "iesg-rev") where state.isStreamState:
      .iesgReview
    case ("draft-iesg", "lc-req"), ("draft-iesg", "lc"):
      .ietfLastCall
    case ("draft-iesg", "pub-req"), ("draft-iesg", "ad-eval"), ("draft-iesg", "review-e"),
      ("draft-stream-ietf", "sub-pub"),
      ("draft-stream-irtf", "chair-w"), ("draft-stream-irtf", "irsg-w"),
      ("draft-stream-irtf", "irsg_review"), ("draft-stream-irtf", "irsgpoll"),
      ("draft-stream-iab", "review-c"), ("draft-stream-iab", "review-i"),
      ("draft-stream-ise", "find-rev"), ("draft-stream-ise", "ise-rev"),
      ("draft-stream-ise", "need-res"),
      ("draft-stream-editorial", "rsabpoll"):
      .submitted
    // Past WG last call, waiting on the chair or the write-up: not submitted yet, and
    // not back in the group either.
    case ("draft-stream-ietf", "wg-lc"), ("draft-stream-ietf", "chair-w"),
      ("draft-stream-ietf", "writeupw"), ("draft-stream-irtf", "rg-lc"):
      .lastCall
    default:
      .inGroup
    }
  }
}
