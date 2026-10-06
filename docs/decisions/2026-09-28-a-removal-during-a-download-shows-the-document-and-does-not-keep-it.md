# A removal during a download shows the document and does not keep it

*Decided September 2026 (issue #116).*
`DocumentStore.document` suspends in the network fetch, and the actor runs other calls meanwhile, so a Remove Download made during that suspension finished first and the fetch then wrote the body back.
The removal was silently undone, and with the in-memory cache index it stayed undone for the session.
A removal does not cancel the fetch: one is only ever started by opening the document, so a reader is waiting for it, and canceling would turn "don't keep this offline" into an error in front of them.
Instead the reader gets the document and the disk does not.
`InFlightDownloads` (in `RFCReaderKit`, for its tests) keeps the running fetch per document, so a second open joins it rather than fetching twice, and a removal marks the running fetch so that no reader of it writes the result, a reader who joined after the removal included.
Of the readers of an unmarked fetch exactly one is told to keep it, so a shared download is written once.
The whole sequence (join, wait, finish, the decision to keep) is `InFlightDownloads.value(for:start:)`, which runs on the store's actor, so the store writes a kept result before a removal can slip in; the store holds no copy of it for the tests to re-implement.
Original Text's own `.txt` fetch goes through a second instance.

The fetch and its parse run in a task of their own, off the actor, which lasts as long as a reader waits for it.
Awaiting a task does not pass the awaiting task's cancellation on, so `InFlightDownloads` counts the readers joined to each fetch, and a reader whose wait is canceled — it left the document — leaves; the state is behind a lock, so its cancellation handler does so without a hop to the actor.
A canceled fetch throws `CancellationError`, whatever it failed with, so URLSession's `URLError.cancelled` is not shown as a load failure.
When the last one has left, the fetch is canceled and forgotten: it writes nothing, even if it finishes anyway (a parse does not look at cancellation), and the next open starts afresh.
While any reader still waits it goes on, so closing one of two tabs on a document does not fail the other.
An earlier revision let the fetch outlive its reader and kept the result, on the grounds that a document finished a moment before the reader left was always kept; that was rejected, because the app is held to being kind to metered and poor connections (`VISION.md`), and a download nobody is waiting for any more is bandwidth spent on nothing.
A fetch that finishes before its reader's cancellation reaches the actor is still kept, since there is nothing left to save.
