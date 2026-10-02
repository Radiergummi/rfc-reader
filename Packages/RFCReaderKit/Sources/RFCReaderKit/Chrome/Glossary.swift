import RFCKit

/// What the labels the app shows mean, in its own words (#362): every status, stream
/// and series, and the terms of the process that publishes them. A label that names
/// one of them opens its entry.
///
/// Plain data rather than a bundled file, so a status or stream added to RFCKit
/// without an entry fails to compile here instead of opening nothing at run time.
/// The text keeps to what RFC 2026, RFC 6410, RFC 7127, RFC 8729 and RFC 9280 say,
/// in plain words.
public enum Glossary {
  /// A term the app explains.
  public enum Term: Sendable, Hashable, Identifiable, CaseIterable {
    case status(PublicationStatus)
    case stream(PublicationStream)
    case series(DocumentID.Series)
    case process(ProcessTerm)

    public var id: Self { self }

    public static let allCases: [Term] =
      PublicationStatus.allCases.map(Term.status) + PublicationStream.allCases.map(Term.stream)
      + DocumentID.Series.allCases.map(Term.series) + ProcessTerm.allCases.map(Term.process)
  }

  /// The words of the publishing process the app shows beside a document.
  public enum ProcessTerm: Sendable, Hashable, CaseIterable {
    case internetDraft
    case obsoletes
    case updates
    case errata
    case workingGroup
  }

  public struct Entry: Sendable, Hashable {
    public let title: String
    /// What the term means, in a sentence or two: a list row's tooltip, and the
    /// Info pane's status box. The explanation opens with it.
    public let summary: String
    /// The rest of the explanation.
    public let detail: String
    /// Terms that explain this one further, each opening its own entry.
    public let related: [Term]

    /// The whole explanation, two to four sentences: the summary, then the detail.
    public var explanation: String { summary + " " + detail }
  }

  public static func entry(for term: Term) -> Entry {
    switch term {
    case .status(let status): entry(for: status)
    case .stream(let stream): entry(for: stream)
    case .series(let series): entry(for: series)
    case .process(let term): entry(for: term)
    }
  }

  private static func entry(for status: PublicationStatus) -> Entry {
    switch status {
    case .internetStandard:
      Entry(
        title: status.displayName,
        summary: """
          The IETF's highest maturity level: a stable standard, widely implemented and deployed.
          """,
        detail: """
          A Proposed Standard reaches it after significant implementation and successful \
          operational experience, and is then also given an STD number.
          """,
        related: [.status(.proposedStandard), .status(.draftStandard), .series(.std)])
    case .draftStandard:
      Entry(
        title: status.displayName,
        summary: """
          A standard at a maturity level the IETF has since retired, between Proposed and \
          Internet Standard.
          """,
        detail: """
          It asked for at least two independent, interoperable implementations. RFC 6410 removed \
          the level in 2011, and a document still at it stays there until it is reclassified.
          """,
        related: [.status(.proposedStandard), .status(.internetStandard)])
    case .proposedStandard:
      Entry(
        title: status.displayName,
        summary: """
          A standard the IETF has approved. Most of the Internet's standards remain at this \
          level.
          """,
        detail: """
          It is the first level of the standards track: the specification is stable, well \
          understood and reviewed by the community, and many Proposed Standards are deployed \
          widely without ever advancing.
          """,
        related: [.status(.internetStandard), .stream(.ietf), .process(.internetDraft)])
    case .bestCurrentPractice:
      Entry(
        title: status.displayName,
        summary: """
          Guidance the IETF recommends, for operating the Internet or for its own processes.
          """,
        detail: """
          A BCP is approved with the same consensus as a standard, but describes a practice \
          rather than a protocol. Each is also given a BCP number.
          """,
        related: [.series(.bcp), .stream(.ietf)])
    case .informational:
      Entry(
        title: status.displayName,
        summary: "Published for information. Not a standard, and not a recommendation.",
        detail: """
          An Informational RFC can come from any stream and need not reflect any community \
          consensus.
          """,
        related: [.status(.experimental), .stream(.independent), .series(.fyi)])
    case .experimental:
      Entry(
        title: status.displayName,
        summary: "Published for experimentation and evaluation. Not a standard.",
        detail: """
          It records work that is part of a research or development effort, so that others can \
          try it and report what they learn.
          """,
        related: [.status(.informational), .stream(.irtf)])
    case .historic:
      Entry(
        title: status.displayName,
        summary: "Superseded or no longer in use, kept for the record.",
        detail: """
          A document is made Historic when a newer specification replaces it or when what it \
          describes has fallen out of use.
          """,
        related: [.process(.obsoletes)])
    case .unknown:
      Entry(
        title: status.displayName,
        summary: "The RFC Editor's index records no status for this document.",
        detail: """
          Most such documents are early RFCs, published before the IETF defined its statuses.
          """,
        related: [.stream(.legacy), .series(.rfc)])
    }
  }

  private static func entry(for stream: PublicationStream) -> Entry {
    switch stream {
    case .ietf:
      Entry(
        title: "IETF Stream",
        summary: """
          Documents from the Internet Engineering Task Force, most of them written in its \
          working groups and approved by the IESG.
          """,
        detail: """
          It is the only stream that publishes standards and Best Current Practices.
          """,
        related: [
          .process(.workingGroup), .process(.internetDraft), .status(.proposedStandard),
          .stream(.iab),
        ])
    case .irtf:
      Entry(
        title: "IRTF Stream",
        summary: """
          Documents from the research groups of the Internet Research Task Force, which studies \
          longer-term questions than the IETF.
          """,
        detail: """
          They are published as Informational or Experimental, never as standards.
          """,
        related: [.status(.experimental), .status(.informational)])
    case .iab:
      Entry(
        title: "IAB Stream",
        summary: """
          Documents from the Internet Architecture Board, which oversees the architecture of the \
          Internet and the IETF's standards process.
          """,
        detail: """
          They are mostly Informational, giving architectural guidance.
          """,
        related: [.status(.informational), .stream(.ietf)])
    case .independent:
      Entry(
        title: "Independent Submission",
        summary: """
          Documents published outside the IETF's process, reviewed and approved by the \
          Independent Submissions Editor.
          """,
        detail: """
          They are Informational, Experimental or Historic, and represent no community \
          consensus.
          """,
        related: [.status(.informational), .status(.experimental)])
    case .editorial:
      Entry(
        title: "Editorial Stream",
        summary: "Documents about the policies of the RFC Series itself.",
        detail: """
          The stream was created in 2022, by RFC 9280: its documents are written in the RFC \
          Series Working Group and approved by the RFC Series Approval Board.
          """,
        related: [.series(.rfc)])
    case .legacy:
      Entry(
        title: "Legacy",
        summary: "Published before the RFC Editor recorded which stream a document came through.",
        detail: """
          Streams were defined in 2007, by RFC 4844, and earlier RFCs carry no stream of their \
          own.
          """,
        related: [.status(.unknown), .series(.rfc)])
    }
  }

  private static func entry(for series: DocumentID.Series) -> Entry {
    switch series {
    case .rfc:
      Entry(
        title: "RFC Series",
        summary: """
          The Internet's technical documents, numbered in the order they are published since \
          1969.
          """,
        detail: """
          An RFC never changes once published: a correction is recorded as an erratum, and a \
          revision is a new RFC.
          """,
        related: [.process(.errata), .process(.obsoletes), .process(.updates), .stream(.editorial)])
    case .std:
      Entry(
        title: "STD Series",
        summary: """
          A number for an Internet Standard that stays the same when the RFCs behind it are \
          replaced.
          """,
        detail: """
          One STD can consist of several RFCs, and citing the STD number cites whichever RFCs \
          make it up today.
          """,
        related: [.status(.internetStandard), .series(.rfc)])
    case .bcp:
      Entry(
        title: "BCP Series",
        summary: """
          A number for a Best Current Practice that stays the same when the RFCs behind it are \
          replaced.
          """,
        detail: """
          One BCP can consist of several RFCs: BCP 14 is RFC 2119 and RFC 8174 together.
          """,
        related: [.status(.bestCurrentPractice), .series(.rfc)])
    case .fyi:
      Entry(
        title: "FYI Series",
        summary: "A series of introductory Informational RFCs, for readers new to the Internet.",
        detail: """
          It was closed in 2011, by RFC 6360, and no new FYI numbers are given.
          """,
        related: [.status(.informational), .series(.rfc)])
    }
  }

  private static func entry(for term: ProcessTerm) -> Entry {
    switch term {
    case .internetDraft:
      Entry(
        title: "Internet-Draft",
        summary: "A working document, not yet an RFC.",
        detail: """
          Drafts expire after six months unless revised, and are not meant to be cited as \
          anything but work in progress. Many are revised until a stream approves them for \
          publication as an RFC.
          """,
        related: [.process(.workingGroup), .series(.rfc)])
    case .obsoletes:
      Entry(
        title: "Obsoletes and Obsoleted By",
        summary: "A newer RFC that obsoletes an older one replaces it entirely.",
        detail: """
          The older RFC stays published, unchanged, but the newer one is the one to implement \
          and cite.
          """,
        related: [.process(.updates), .status(.historic)])
    case .updates:
      Entry(
        title: "Updates and Updated By",
        summary: """
          A newer RFC that updates an older one changes or extends part of it, and the rest of \
          the older RFC still stands.
          """,
        detail: """
          The two have to be read together.
          """,
        related: [.process(.obsoletes), .process(.errata)])
    case .errata:
      Entry(
        title: "Errata",
        summary: """
          Errors reported in a published RFC, which the RFC Editor records beside it, since the \
          RFC itself never changes.
          """,
        detail: """
          An erratum is verified when the body that approved the document confirms it.
          """,
        related: [.series(.rfc), .process(.updates)])
    case .workingGroup:
      Entry(
        title: "Working Group",
        summary: """
          An IETF group chartered for one piece of work within an area, such as HTTP or QUIC.
          """,
        detail: """
          Anyone can take part, mostly on its mailing list, and its decisions are made by rough \
          consensus.
          """,
        related: [.process(.internetDraft), .stream(.ietf)])
    }
  }

}
