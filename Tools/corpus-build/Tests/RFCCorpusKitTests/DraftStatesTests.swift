import RFCCorpusKit
import RFCKit
import Testing

/// Datatracker's states, by their slugs: which make a draft adopted, and how far
/// along each says it is (spec, "Adopted" and "Stages").
@Suite("Draft states")
struct DraftStatesTests {
  private static let active = DraftState("draft", "active")

  @Test(arguments: [
    DraftState("draft-stream-ietf", "wg-cand"), DraftState("draft-stream-ietf", "c-adopt"),
    DraftState("draft-stream-ietf", "info"), DraftState("draft-stream-ietf", "parked"),
    DraftState("draft-stream-ietf", "dead"), DraftState("draft-stream-irtf", "candidat"),
    DraftState("draft-stream-irtf", "parked"), DraftState("draft-stream-irtf", "dead"),
    DraftState("draft-stream-irtf", "repl"), DraftState("draft-stream-iab", "candidat"),
    DraftState("draft-stream-iab", "parked"), DraftState("draft-stream-iab", "dead"),
    DraftState("draft-stream-iab", "repl"), DraftState("draft-stream-iab", "diff-org"),
    DraftState("draft-stream-ise", "receive"), DraftState("draft-stream-ise", "repl"),
    DraftState("draft-stream-ise", "dead"), DraftState("draft-stream-editorial", "repl"),
    DraftState("draft-stream-editorial", "dead"), DraftState("draft-iesg", "dead"),
    DraftState("draft-iesg", "nopubadw"), DraftState("draft-iesg", "nopubanw"),
  ])
  func `a state that means not adopted or stopped excludes the draft`(state: DraftState) {
    #expect(!DraftStates.isAdopted([Self.active, DraftState("draft-iesg", "pub-req"), state]))
  }

  @Test func `a working group document is adopted`() {
    #expect(
      DraftStates.isAdopted([
        Self.active, DraftState("draft-stream-ietf", "wg-doc"),
        DraftState("draft-iesg", "idexists"),
      ]))
  }

  /// An AD-sponsored draft has no stream state, only an IESG state that has moved.
  @Test func `a draft with no stream state counts once the IESG has it`() {
    #expect(DraftStates.isAdopted([Self.active, DraftState("draft-iesg", "pub-req")]))
  }

  /// Measured: every active IETF-stream draft in no group had exactly these.
  @Test(arguments: ["idexists", "watching"])
  func `a draft with no stream state and an untouched IESG state is not adopted`(slug: String) {
    #expect(!DraftStates.isAdopted([Self.active, DraftState("draft-iesg", slug)]))
  }

  @Test func `a draft with no states beyond active is not adopted`() {
    #expect(!DraftStates.isAdopted([Self.active]))
  }

  /// States and stream need not agree: an IETF-stream draft can carry an ISE state.
  @Test func `an excluded state counts whatever the draft's stream`() {
    #expect(
      !DraftStates.isAdopted([
        Self.active, DraftState("draft-stream-ise", "dead"), DraftState("draft-iesg", "pub-req"),
      ]))
  }

  @Test(arguments: [
    (DraftState("draft-iesg", "rfcqueue"), RevisionStage.rfcEditorQueue),
    (DraftState("draft-rfceditor", "auth48"), .rfcEditorQueue),
    (DraftState("draft-rfceditor", "missref"), .rfcEditorQueue),
    (DraftState("draft-stream-ise", "rfc-edit"), .rfcEditorQueue),
    (DraftState("draft-stream-editorial", "rfc-edit"), .rfcEditorQueue),
    (DraftState("draft-iesg", "approved"), .approved),
    (DraftState("draft-iesg", "ann"), .approved),
    (DraftState("draft-stream-iab", "approved"), .approved),
    (DraftState("draft-iesg", "iesg-eva"), .iesgReview),
    (DraftState("draft-iesg", "defer"), .iesgReview),
    (DraftState("draft-iesg", "writeupw"), .iesgReview),
    (DraftState("draft-iesg", "goaheadw"), .iesgReview),
    (DraftState("draft-stream-irtf", "iesg-rev"), .iesgReview),
    (DraftState("draft-iesg", "lc-req"), .ietfLastCall),
    (DraftState("draft-iesg", "lc"), .ietfLastCall),
    (DraftState("draft-iesg", "pub-req"), .submitted),
    (DraftState("draft-iesg", "ad-eval"), .submitted),
    (DraftState("draft-iesg", "review-e"), .submitted),
    (DraftState("draft-stream-ietf", "sub-pub"), .submitted),
    (DraftState("draft-stream-irtf", "irsg_review"), .submitted),
    (DraftState("draft-stream-iab", "review-c"), .submitted),
    (DraftState("draft-stream-ise", "ise-rev"), .submitted),
    (DraftState("draft-stream-editorial", "rsabpoll"), .submitted),
    (DraftState("draft-stream-ietf", "wg-lc"), .lastCall),
    (DraftState("draft-stream-irtf", "rg-lc"), .lastCall),
    (DraftState("draft-stream-ietf", "wg-doc"), .inGroup),
    (DraftState("draft-iesg", "idexists"), .inGroup),
  ])
  func `each state maps to its stage`(state: DraftState, stage: RevisionStage) {
    #expect(DraftStates.stage(of: state) == stage)
  }

  @Test func `the furthest stage of a draft's states wins`() {
    let states = [
      Self.active, DraftState("draft-stream-ietf", "sub-pub"), DraftState("draft-iesg", "rfcqueue"),
      DraftState("draft-rfceditor", "edit"),
    ]
    #expect(DraftStates.stage(states) == .rfcEditorQueue)
  }

  /// A state datatracker adds later degrades to the vaguest true answer.
  @Test func `an unknown state falls back to in the group`() {
    #expect(DraftStates.stage([DraftState("draft-stream-ietf", "something-new")]) == .inGroup)
  }
}
