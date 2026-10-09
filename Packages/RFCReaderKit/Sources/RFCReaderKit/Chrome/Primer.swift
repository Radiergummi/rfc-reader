import Foundation
import RFCKit

extension Glossary {
  /// "How an RFC Is Made" (#365): the stages an IETF document goes through from a
  /// first draft to a published RFC, and a word on the other streams, in the app's
  /// own words. The glossary explains a label; this explains the path the labels
  /// are steps on.
  ///
  /// Plain data, as the glossary is. The text keeps to what RFC 2026, RFC 7322,
  /// RFC 8729 and RFC 9280 say, and quotes none of them.
  public struct Primer: Sendable, Hashable {
    public let introduction: String
    /// The IETF stream's stages, in order.
    public let stages: [Stage]
    /// The streams that publish RFCs by their own review rather than the IETF's.
    public let otherStreams: Stage
  }

  /// One stage of the primer: a title, two to four sentences, and the glossary terms
  /// it names, each opening its entry.
  public struct Stage: Sendable, Hashable {
    public let title: String
    public let text: String
    public let related: [Term]
  }

  /// The primer's title: what its window, its navigation bar and a link to it say.
  public static func primerTitle(locale: Locale = .interface) -> String {
    String(kit: "How an RFC Is Made", locale: locale)
  }

  public static func primer(locale: Locale = .interface) -> Primer {
    Primer(
      introduction: String(
        kit: """
          Most RFCs come from the IETF, and go through the same stages on their way from a \
          first draft to a published document.
          """, locale: locale),
      stages: [
        Stage(
          title: String(kit: "An Internet-Draft", locale: locale),
          text: String(
            kit: """
              Today every RFC starts as an Internet-Draft, which anyone can write and submit. A \
              draft is work in progress, not a standard: it expires after six months unless it \
              is revised, and many are never published.
              """, locale: locale),
          related: [.process(.internetDraft)]),
        Stage(
          title: String(kit: "Adoption by a Working Group", locale: locale),
          text: String(
            kit: """
              A working group whose charter covers the work can adopt a draft, and from then on \
              the group decides what it says, not only its authors. A draft can also go ahead \
              without a group, as an individual submission an area director sponsors.
              """, locale: locale),
          related: [.process(.workingGroup), .stream(.ietf)]),
        Stage(
          title: String(kit: "Working Group Last Call", locale: locale),
          text: String(
            kit: """
              When the group thinks the document is done, its chairs ask the whole group for \
              final comments. If there is rough consensus, the group asks the IESG to publish it.
              """, locale: locale),
          related: [.process(.workingGroup)]),
        Stage(
          title: String(kit: "IETF Last Call and IESG Review", locale: locale),
          text: String(
            kit: """
              The whole IETF then has a few weeks to comment, and the area directors of the IESG \
              review the document. They approve it, ask for changes or decline it, and decide its \
              status, such as Proposed Standard, Best Current Practice or Informational.
              """, locale: locale),
          related: [
            .status(.proposedStandard), .status(.bestCurrentPractice), .status(.informational),
          ]),
        Stage(
          title: String(kit: "The RFC Editor", locale: locale),
          text: String(
            kit: """
              The RFC Editor edits the approved document for clarity and consistency. The authors \
              then check the result one last time, a step called AUTH48.
              """, locale: locale),
          related: [.series(.rfc)]),
        Stage(
          title: String(kit: "Publication", locale: locale),
          text: String(
            kit: """
              The document is published with an RFC number and its status, and its text never \
              changes again, though its status can. Errors are recorded beside it as errata, and \
              later work updates or obsoletes it with an RFC of its own.
              """, locale: locale),
          related: [.process(.errata), .process(.updates), .process(.obsoletes)]),
      ],
      otherStreams: Stage(
        title: String(kit: "Other Streams", locale: locale),
        text: String(
          kit: """
            Not every RFC comes from the IETF. The IAB, the IRTF, the Independent Submissions \
            Editor and, for the RFC Series' own policies, the Editorial stream each publish RFCs \
            through a review of their own, and none of them publishes standards. The earliest \
            RFCs, from before there were streams, are filed under Legacy.
            """, locale: locale),
        related: [
          .stream(.iab), .stream(.irtf), .stream(.independent), .stream(.editorial),
          .stream(.legacy),
        ])
    )
  }
}
