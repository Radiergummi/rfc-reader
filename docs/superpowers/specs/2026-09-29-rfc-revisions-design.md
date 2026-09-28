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
  and `rfceditor_state`.

So "which drafts revise RFC X" cannot be answered from datatracker one document at a time.
Something has to read the headers of every adopted draft and keep the result.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Where the scan runs | A scheduled GitHub Action, publishing one JSON file. | One crawler for all users instead of one per device, and it runs on infrastructure the project already has. A pack-time snapshot would be as stale as the pack, and drafts change weekly. |
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
corpus-build revisions --previous <revisions.json> --out <revisions.json>
```

`--previous` is optional. Without it the run reads every adopted draft.

### Run

1. **Select the drafts.** Page through datatracker's
   `doc/document/?type=draft&states__type=draft&states__slug=active&stream__isnull=false`.
   With a previous file, also add `time__gt=<previous generatedAt>`. That returns only drafts
   whose record changed since then. Of these, keep the ones that are [adopted](#adopted).
2. **Read each changed draft's header.** Fetch
   `https://www.ietf.org/archive/id/<name>-<rev>.xml` and read `obsoletes` and `updates` from the
   `<rfc>` element, reusing the attribute parsing `RFCXMLParser` already has. That is
   `parseDocumentList`, which is `private` today and becomes an internal `static` function, so
   the scanner and a guard-level test can reach it. If the draft has no XML, fetch the `.txt` and read the front page's
   `Obsoletes:` and `Updates:` lines, including numbers continued on the next line and the
   `(if approved)` suffix.
3. **Read each changed draft's state** from its `doc.json`.
4. **Merge.** Start from the previous file's entries.
   - Drop every draft that is no longer in the active, adopted set. That covers drafts
     that expired, were replaced, or were published as RFCs. Checking this needs only the list
     from step 1 without `time__gt`, which is names only and cheap.
   - Replace the entries of every changed draft with its new ones.
   - Keep only drafts that obsolete or update at least one RFC.
5. **Write** `revisions.json`.

The first run reads at most 970 headers. A daily run reads the drafts that changed that day,
typically a few dozen. Requests are sequential, with a short pause between them, and send a
`User-Agent` naming the project and its repository URL.

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
    public var stream: String           // "ietf", "irtf", "iab", "ise"
    public var group: String?           // "httpbis"; nil when AD-sponsored or not in a group
    public var intendedStatus: String?  // "Proposed Standard"
    public var stage: RevisionStage
  }
}
```

Dictionary keys encode as strings in JSON. That is acceptable, and is pinned by the round-trip
test.

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

An AD-sponsored IETF draft has no stream state and counts. The list is a pure function in
`RFCCorpusKit` with a table test. The state names are datatracker's, as listed by
`doc/state/?type=<type>` on 29 September 2026.

### Stages

`RevisionStage` is an enum in RFCKit, ordered from earliest to furthest along. Datatracker's
states map onto it, checked in this order. The first match wins:

| Stage | Shown as | From |
|---|---|---|
| `rfcEditorQueue` | In the RFC Editor queue | IESG "RFC Ed Queue"; any `draft-rfceditor` state; a stream state "Sent to the RFC Editor" |
| `approved` | Approved for publication | IESG "Approved-announcement to be sent" or "Approved-announcement sent"; IAB "Approved by IAB, To Be Sent to RFC Editor" |
| `iesgReview` | Under IESG review | IESG "Last Call Requested", "In Last Call", "Waiting for Writeup", "Waiting for AD Go-Ahead", "IESG Evaluation", "IESG Evaluation - Defer"; a stream state "In IESG Review" |
| `submitted` | Submitted for publication | IESG "Publication Requested", "AD Evaluation", "Expert Review"; IETF "Submitted to IESG for Publication"; IRTF "Waiting for IRTF Chair", "Awaiting IRSG Reviews", "IRSG Review", "In IRSG Poll"; IAB "Community Review", "IAB Review"; Independent "Finding Reviewers", "In ISE Review", "Response to Review Needed" |
| `lastCall` | In working group last call | IETF "In WG Last Call"; IRTF "In RG Last Call" |
| `inGroup` | In the working group | any other state of an adopted draft |

"In the working group" also covers research groups and the IAB program a draft sits in. The
Independent stream has no group, so an Independent draft in `inGroup` shows as
"Under review" instead.

The mapping is a pure function over the state strings: the furthest stage any of the draft's
states reaches wins. A state not named above maps to `inGroup`, so a new datatracker state
degrades to the vaguest true answer instead of a wrong one.

### Failures

- **One draft cannot be read.** The header or `doc.json` is missing, or the header names no
  number the parser accepts. The draft is skipped and logged, and the run goes on. A skipped
  draft that was in the previous file keeps its previous entries.
- **Datatracker is unreachable or answers with errors** on the listing. The run fails and
  publishes nothing, so the previous file stays live.
- **The result shrinks by more than half** against the previous file. The run fails instead of
  publishing. A real change in the drafts does not do that; a broken query or a changed API
  does.

### Workflow

`.github/workflows/revisions.yml`, following `corpus.yml`:

- runs on `schedule` (daily, at an off-hour minute) and `workflow_dispatch`;
- uses the same pinned `swift:6.3` container and the pinned actions `corpus.yml` already uses;
- downloads the current `revisions.json` from the `revisions` release, if there is one, and
  passes it as `--previous`;
- runs `corpus-build revisions`;
- uploads the result to the `revisions` release, creating it on the first run, with
  `gh release upload revisions revisions.json --clobber`;
- has `permissions: contents: write` only on that job, and `persist-credentials: false` on
  checkout, as `corpus.yml` does.

The file's stable URL is
`https://github.com/Radiergummi/rfc-reader/releases/download/revisions/revisions.json`.

## The app

### Fetching and caching

- **Client.** A `fetchRevisions(ifNoneMatch:)` method on a small client in RFCKit, built on the
  same `data(for:)` transport `RFCEditorClient` uses. It returns the decoded `RFCRevisions` and
  its `ETag`, or "not modified" when the server answers 304. No ETag handling exists yet; this
  adds it.
- **Cache.** `DocumentStore` keeps the last good file and its ETag on disk, beside the cached
  index. `LibraryModel` loads it at launch, before any network request, so the banner is right
  offline.
- **Refresh.** At launch, and at most once a day after that. There is no background refresh;
  #191 adds that.
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
  25 September".
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
working group, intended status, stage. For example:
"draft-ietf-httpbis-rfc6265bis-22 · HTTPBIS · intended Proposed Standard · In the RFC Editor
queue". `DocumentInfo` takes the summary as an input, so its tests cover the rows.

### Accessibility

Each banner row reads as one sentence, for example "Being replaced by
draft-ietf-httpbis-rfc6265bis, revision 22, in the RFC Editor queue". The link is the row's
action.

## Testing

Following CLAUDE.md. No RFC or draft text is committed; hand-written inputs are shaped like a
draft, never quoted from one.

- **XML header:** `RFCXMLParser`'s `obsoletes`/`updates` parsing is already covered. One test
  pins a header that declares both.
- **Text front page:** guard-level tests over hand-written lines. A single number, several
  numbers, a list continued on the next line, the `(if approved)` suffix, and a page with
  neither.
- **Adopted:** a table test over the excluded states, per stream, and an AD-sponsored draft with
  no stream state counting.
- **Stages:** a table test from datatracker state strings to `RevisionStage`, including the
  furthest-stage-wins rule across a draft's several states, and an unknown state falling back
  to `inGroup`.
- **Format:** `RFCRevisions` round-trips through JSON, and a decoder rejects an unknown
  `version`.
- **Merge:** on values built in code, not files. A draft that left the active set is dropped; a
  changed draft's entries are replaced; a draft skipped for a read error keeps its previous
  entries; a draft that no longer obsoletes or updates anything is dropped; the shrink guard
  trips at more than half.
- **RFCReaderKit:** ordering, the three-day staleness rule, the "and N more" collapse, the
  accessibility sentence, and `DocumentInfo`'s new rows.
- **By hand:** a first workflow run by `workflow_dispatch`, with its output reviewed before the
  schedule is enabled. In the app, RFC 6265 shows 6265bis in the RFC Editor queue. An RFC
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
