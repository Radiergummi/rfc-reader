# RFC revisions — design

*29 September 2026. Approved in brainstorming (datatracker ideas, practitioner track first);
implementation plan to follow. Notifications for the same data are folded into #191.*

## Why

The reader's first promise is the truth about status: is this still the current document? Today
it answers from the RFC index, which only knows what has been published: obsoleted by, updated
by, errata. A practitioner also needs to know what is coming. RFC 6265 is still current, but its
replacement, `draft-ietf-httpbis-rfc6265bis`, is in the RFC Editor queue. Someone implementing
cookies today should know that, and nothing puts it where they read.

This is the first of the datatracker features. It is also the smallest one that needs both a
build-time data path and a refreshed one, so it settles how datatracker data reaches the app.

## What datatracker does and does not say

Measured against the live API on 28 September 2026:

- **Datatracker records no obsoletes or updates relation from a draft.** Querying
  `doc/relateddocument/?relationship=obs&source__type=draft` returns 0, and the same for
  `updates`. The relation appears only once the draft is published as an RFC. For 6265bis-22,
  which is in the RFC Editor queue, datatracker lists only an informative reference to RFC 6265.
- **The intent is in the draft's own header.** `draft-ietf-httpbis-rfc6265bis-22.xml` has
  `<rfc … obsoletes="6265">`. A text-only draft states it on the front page, as
  `Obsoletes: 6265 (if approved)`.
- **3,280 drafts are active; 969 of them are in a stream.** The other 2,311 are individual
  submissions that nobody has adopted.
- **A draft's state is cheap to read.** `https://datatracker.ietf.org/doc/<name>/doc.json` is
  about 11 KB and carries `rev`, `stream`, `group`, `intended_std_level`, `state`, `iesg_state`
  and `rfceditor_state`, and a `rev_history` with each revision's `published` date.
- **The listing already says what changed.** Each record of `doc/document/` carries the draft's
  `rev` and its `states`, as state IDs. The 182 state names are one request to `doc/state/`.
- **"Active" is not "recent".** `draft-morand-http-digest-2g-aka-05` dates from 2014 and is
  still active, with an ISE state of "In IESG Review" while its stream is IETF. A draft can sit
  in one state for years, and its states need not match its stream.
- **A stream is not adoption.** The four active IETF-stream drafts in no working group all have
  no stream state and the IESG state "I-D Exists": nothing has happened to them.

So "which drafts revise RFC X" cannot be answered from datatracker one document at a time.
Something has to read the headers of every adopted draft and keep the result.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Where the scan runs | A scheduled GitHub Action, publishing one JSON file for the app and one scan record for the next run. | One crawler for all users instead of one per device, and it runs on infrastructure the project already has. A pack-time snapshot would be as stale as the pack, and drafts change weekly. |
| Which drafts count | Only adopted drafts: in a stream (IETF, IRTF, IAB, Independent), and not in a state that means "not adopted yet" or "stopped" (see [Adopted](#adopted)). | "Being revised" must be a statement the reader can trust. An individual draft's `obsoletes` is a proposal, not a revision under way. The scanner can record individual drafts later if the display ever wants them. |
| Where it shows | The reader's status banner and the inspector's Relationships section. Not in lists, not as notifications. | That is where readers already look for status. List markers and notifications (#191) use the same data later. |
| Name | `revisions`: `corpus-build revisions`, `.github/workflows/revisions.yml`, the release tag `revisions`, the file `revisions.json`, the type `RFCRevisions`. | Short, and it says what the file holds. |
| Following the draft | Its name links to its datatracker page, opened in the browser. | The errata link already works that way. Reading drafts in the app is VISION.md Tier 2. |

## The scanner

### Command

A new subcommand of `Tools/corpus-build`, `RevisionsCommand`, registered in
`CorpusBuild.swift`. The logic that is a pure function of its inputs lives in `RFCCorpusKit`,
beside `FetchPlan` and `Manifest`, so it is tested without the network:

```
corpus-build revisions [--scan <revisions-scan.json>] --out <directory>
```

It writes `revisions.json` and `revisions-scan.json` into `<directory>`. `--scan` is the
previous run's scan record. Without it, the run reads every adopted draft.

### The scan record

`revisions-scan.json` is how the scanner remembers what it has read, so a daily run reads only
what changed. The app never downloads it. It is a `Codable` type in `RFCCorpusKit` holding one
entry per adopted draft, keyed by name, **including drafts that revise nothing**:

- the `rev` and the state IDs that were read;
- the outcome: the relations and metadata that were read, or that the read failed.

`revisions.json` is a pure function of the scan record. Keeping the record separate keeps the
app's file small and its format independent of how the scanner works.

The design does not use datatracker's `time` field to find changes. `time` is not documented
to move on every state change (an RFC Editor queue step, for one), and when a draft whose read
failed has not changed since, a filter on `time` never selects it again.

### Run

1. **List the drafts.** Record the run's start time; it becomes `generatedAt`. Page through
   `doc/document/?type=draft&states__type=draft&states__slug=active&stream__isnull=false`
   in full, about ten pages. Keep the ones that are [adopted](#adopted). Read the state names
   once from `doc/state/`.
2. **Decide what to read, against the scan record.** Read a draft's header when the draft is new,
   or its `rev` changed, or the last read failed. Read its `doc.json` when any of those holds or
   its state IDs changed. Everything else carries over unchanged.
3. **Read the header.** Fetch `https://www.ietf.org/archive/id/<name>-<rev>.xml` and read
   `obsoletes` and `updates` from the `<rfc>` element, stopping the parse once that element
   starts. v2 drafts often declare external entities in a DOCTYPE, and nothing past the root is
   needed. The attribute values go through `RFCXMLParser`'s `parseDocumentList`, which is a
   `private` instance method today and becomes an internal `static` function, so the scanner and
   a guard-level test can reach it. If the draft has no XML, fetch the `.txt` and read the front
   page's `Obsoletes:` and `Updates:` lines, including numbers continued on the next line and the
   `(if approved)` suffix.

   A missing attribute or line means the draft revises nothing. It is not an error. An
   attribute that is present but gives no number is logged, since `parseDocumentList` silently
   drops entries such as `RFC6265` or a draft name, and a silent drop hides an entry.
4. **Read the state and metadata** from `doc.json`: stream, group, intended status, states, and
   the current revision's `published` date from `rev_history`.
5. **Build the new scan record.** Drafts that are no longer listed are left out; they expired,
   were replaced, or were published as RFCs. A draft whose read failed keeps its previous
   outcome, if it had one, and is marked for another try.
6. **Write** both files. `revisions.json` lists only drafts that obsolete or update at least
   one RFC.

The first run reads at most 970 headers. A daily run reads the drafts that changed that day,
typically a few dozen, plus the listing. Requests are sequential, with a short pause between
them, and send a `User-Agent` naming the project and its repository URL.

### Output format

A `Codable` type in RFCKit, shared by the scanner and the app:

```swift
public struct RFCRevisions: Codable, Sendable, Equatable {
  /// Bumped on any change a reader of an older version would misread.
  public var version: Int  // 1
  public var generatedAt: Date
  /// RFC number → the drafts that intend to obsolete or update it.
  public var revisions: [Int: [Revision]]

  public struct Revision: Codable, Sendable, Equatable {
    public enum Relation: String, Codable, Sendable { case obsoletes, updates }
    public var relation: Relation
    public var draft: String            // "draft-ietf-httpbis-rfc6265bis"
    public var revision: String         // "22"
    public var published: Date          // when this revision was posted
    public var stream: String           // "ietf", "irtf", "iab", "ise"
    public var group: String?           // "httpbis"; nil when AD-sponsored or not in a group
    public var intendedStatus: String?  // "Proposed Standard"
    public var stage: RevisionStage
  }
}
```

Dictionary keys encode as strings in JSON. That is acceptable, and is pinned by the round-trip
test. `generatedAt` is the run's start, not its end, so a change made during a run is never
older than the file that claims to include it. Synthesized `Codable` does not check `version`,
so `RFCRevisions` has a hand-written `init(from:)` that decodes `version` first and throws on
any value it does not know.

### Adopted

A draft counts when it is active, has a stream, and none of its states is one of these:

- IETF stream: "Candidate for WG Adoption", "Call For Adoption By WG Issued",
  "Parked WG Document", "Dead WG Document";
- IRTF stream: "Candidate RG Document", "Parked RG Document", "Dead IRTF Document",
  "Replaced";
- IAB stream: "Candidate IAB Document", "Parked IAB Document", "Dead IAB Document",
  "Replaced", "Sent to a Different Organization for Publication";
- Independent stream: "Submission Received", "Replaced",
  "No Longer In Independent Submission Stream";
- IESG: "Dead", "DNP-waiting for AD note", "DNP-announcement to be sent".

A draft with no stream state counts only if its IESG state has moved past "I-D Exists" and
"AD is watching". That keeps AD-sponsored drafts and leaves out drafts that merely carry a
stream. The exclusions apply to all of a draft's states, whatever its stream, because states
and stream need not agree (see the 2014 draft above). The rule is a pure function in
`RFCCorpusKit` with a table test. The state names are datatracker's, as listed by
`doc/state/?type=<type>` on 29 September 2026.

### Stages

`RevisionStage` is an enum in RFCKit, ordered from earliest to furthest along. The table lists
it furthest first:

| Stage | Shown as | From |
|---|---|---|
| `rfcEditorQueue` | In the RFC Editor queue | IESG "RFC Ed Queue"; any `draft-rfceditor` state; a stream state "Sent to the RFC Editor" |
| `approved` | Approved for publication | IESG "Approved-announcement to be sent" or "Approved-announcement sent"; IAB "Approved by IAB, To Be Sent to RFC Editor" |
| `iesgReview` | Under IESG review | IESG "Waiting for Writeup", "Waiting for AD Go-Ahead", "IESG Evaluation", "IESG Evaluation - Defer"; a stream state "In IESG Review" |
| `ietfLastCall` | In IETF Last Call | IESG "Last Call Requested", "In Last Call" |
| `submitted` | Submitted for publication | IESG "Publication Requested", "AD Evaluation", "Expert Review"; IETF "Submitted to IESG for Publication"; IRTF "Waiting for IRTF Chair", "Awaiting IRSG Reviews", "IRSG Review", "In IRSG Poll"; IAB "Community Review", "IAB Review"; Independent "Finding Reviewers", "In ISE Review", "Response to Review Needed" |
| `lastCall` | In working group last call | IETF "In WG Last Call"; IRTF "In RG Last Call" |
| `inGroup` | In the working group | any other state of an adopted draft |

"In the working group" also covers research groups and the IAB program a draft sits in. The
Independent stream has no group, so an Independent draft in `inGroup` shows as
"Under review" instead. Every Independent state named above maps to a later stage, so this
applies only to a state datatracker adds later. It exists because of the fallback below.

IETF Last Call has its own stage, apart from IESG review, because it is the moment the whole
community is asked to comment, which is what a practitioner acts on.

The mapping is a pure function over the state strings: the furthest stage any of the draft's
states reaches wins. A state not named above maps to `inGroup`, so a new datatracker state
degrades to the vaguest true answer instead of a wrong one.

### Failures

- **One draft cannot be read.** Its header or `doc.json` cannot be fetched. The draft is marked
  failed in the scan record and logged, and the run goes on. It keeps its previous outcome, if
  it had one, and the next run tries it again.
- **Datatracker is unreachable or answers with errors** on the listing or the state names. The
  run fails and publishes nothing, so the previous files stay live.
- **The result shrinks by more than half** against the previous `revisions.json`, which had at
  least ten RFCs in it. The run fails instead of publishing. A real change in the drafts does
  not do that; a broken query or a changed API does. The floor keeps small numbers from
  tripping it. A `workflow_dispatch` input, `allow-shrink`, publishes anyway, for the day the
  shrink is real.

### Workflow

`.github/workflows/revisions.yml`, following `corpus.yml`:

- runs on `schedule` (daily, at an off-hour minute) and on `workflow_dispatch`, with the
  `allow-shrink` input;
- uses the same pinned `swift:6.3` container and the pinned actions `corpus.yml` already uses,
  and installs `gh` with `apt-get` as `corpus.yml` does, because the image lacks it;
- downloads the current `revisions.json` and `revisions-scan.json` from the `revisions`
  release, if there is one, and passes the scan record as `--scan`;
- runs `corpus-build revisions`;
- uploads both files to the `revisions` release with `gh release upload … --clobber`. On the
  first run it creates the release with `--prerelease`, so it never becomes the repository's
  "Latest release";
- has `permissions: contents: write` only on that job, and `persist-credentials: false` on
  checkout, as `corpus.yml` does.

`--clobber` deletes the old asset before uploading the new one, so for a moment the URL
returns 404. The app treats that like any failed fetch.

The file's stable URL is
`https://github.com/Radiergummi/rfc-reader/releases/download/revisions/revisions.json`.

## The app

### Fetching and caching

- **Client.** A `fetchRevisions()` method on a small client in RFCKit, a plain GET built on the
  same `data(for:)` transport `RFCEditorClient` uses. It returns the decoded `RFCRevisions`.
  There are no conditional requests. Every run writes a new `generatedAt` and uploads a new
  asset, so the ETag would change daily and a 304 would never come. Supporting it would also
  add request headers to `HTTPTransport` and to every test double. The file is tens of
  kilobytes.
- **Cache.** `DocumentStore` keeps the last good file on disk, with the time it was fetched,
  beside the cached index. `LibraryModel` loads it at launch, before any network request, so the
  banner is right offline.
- **Refresh.** At launch, and whenever the app becomes active (`scenePhase` turning `.active`)
  more than 24 hours after the last successful fetch. There is no background refresh; #191 adds
  that.
- **A failed fetch, or a file that does not decode** (including an unknown `version`), leaves
  the cached copy in place. Nothing is shown to the reader.

### Model

`LibraryModel.revisions: RFCRevisions?`. The questions the interface asks are answered by pure
functions in RFCReaderKit, on a small `RevisionsSummary` built from the file and an RFC number:

- the drafts revising that RFC, ordered by stage (furthest along first), then obsoletes before
  updates, then by name;
- whether the data is stale: `generatedAt` is more than three days before now, in which case
  the interface adds "as of" and the date. An old stage shown as current would be exactly the
  untrue status this feature exists to prevent;
- whether a draft is dormant: its current revision was published more than a year before now.
  An active draft can sit in one state for years, and "Under IESG review" alone would read as
  news;
- the banner's rows: at most two, then "and N more";
- the accessibility sentence for each row.

## The interface

### Status banner

`StatusBanner` in `DocumentView.swift` shows when an RFC is obsoleted, updated, or has errata.
It also shows when a draft is revising the RFC, with one row per draft after the existing rows:

> **Being replaced by** draft-ietf-httpbis-rfc6265bis-22 · In the RFC Editor queue

- "Being replaced by" for `obsoletes`, "Being updated by" for `updates`.
- The draft name and revision are a link to `https://datatracker.ietf.org/doc/<draft>/`.
- The stage is secondary text. When stale, it reads "In the RFC Editor queue, as of
  25 September". When the draft is dormant, the stage is followed by the revision's date:
  "Under IESG review, revision of May 2014".
- At most two rows. A third draft and beyond collapses into "and N more", and the inspector
  lists them all.
- A symbol distinct from the red obsoleted triangle and the orange updated arrows, in the
  secondary color. This is news, not a warning.
- An RFC that is already obsoleted still shows the row. A replacement can itself be under
  revision.
- An RFC nothing is revising shows no row, and no "no revisions" text.

### Inspector

The Relationships section built by `DocumentInfo` gains "Being replaced by" and
"Being updated by" rows after Updated by. Each draft is listed in full: name and revision,
revision date, working group, intended status, stage. For example:
"draft-ietf-httpbis-rfc6265bis-22 · 1 December 2025 · HTTPBIS · intended Proposed Standard ·
In the RFC Editor queue". `DocumentInfo` takes the summary as an input, so its tests cover the rows.

### Accessibility

Each banner row reads as one sentence, for example "Being replaced by
draft-ietf-httpbis-rfc6265bis, revision 22, in the RFC Editor queue". A dormant draft adds
the date: "…, revision 5 from May 2014, under IESG review". The link is the row's action.

## Testing

Following CLAUDE.md. No RFC or draft text is committed; hand-written inputs are shaped like a
draft, never quoted from one.

- **XML header:** `RFCXMLParser`'s `obsoletes`/`updates` parsing is already covered. Guard-level
  tests over hand-written `<rfc>` elements pin a header that declares both, a missing attribute
  (revises nothing, not a failure), an attribute with no number in it (logged), and a DOCTYPE
  with an external entity that the root-only parse never resolves.
- **Text front page:** guard-level tests over hand-written lines. A single number, several
  numbers, a list continued on the next line, the `(if approved)` suffix, and a page with
  neither.
- **Adopted:** a table test over the excluded states, per stream. A draft with no stream state
  counts when its IESG state is past "I-D Exists" and "AD is watching", and not when it is one
  of them. An excluded state counts against a draft whose stream is another one.
- **Stages:** a table test from datatracker state strings to `RevisionStage`, including IETF
  Last Call as its own stage, the furthest-stage-wins rule across a draft's several states, and
  an unknown state falling back to `inGroup`.
- **Format:** `RFCRevisions` round-trips through JSON, and its decoder rejects an unknown
  `version`. The scan record round-trips too.
- **What to read:** on scan records and listings built in code, not files. Only a new draft, a
  changed `rev` or a failed last read triggers a header read. A changed state ID alone triggers
  only a `doc.json` read. An unchanged draft reads nothing.
- **Merge:** on values built in code. A draft that left the listing is dropped. A failed read
  keeps the previous outcome and is marked for retry, and a draft that failed on its first read
  is tried again on the next run. A draft that revises nothing stays in the scan record and
  stays out of `revisions.json`. `generatedAt` is the start time passed in. The shrink guard
  trips at more than half, not below ten, and not with `allow-shrink`.
- **RFCReaderKit:** ordering, the three-day staleness rule, the one-year dormancy rule, the
  "and N more" collapse, the accessibility sentence, and `DocumentInfo`'s new rows.
- **By hand:** a first workflow run by `workflow_dispatch`, with its output reviewed before the
  schedule is enabled. A second run the next day, reviewed for how many drafts it read. It
  should be a few dozen, not 970. In the app, RFC 6265 shows 6265bis in the RFC Editor queue. An RFC
  nothing revises shows no extra row, and an offline launch with a five-day-old file shows
  "as of".

## Out of scope

- Markers in the RFC list, and a "Being revised" sidebar list.
- Notifications. They are #191, which now carries this event.
- Individual drafts.
- Reading drafts in the app (VISION.md Tier 2).
- Any other datatracker data: working group pages (#363), document history (#364),
  "cited by", people. Each gets its own design, reusing the published-file path when it needs
  refreshed data.
