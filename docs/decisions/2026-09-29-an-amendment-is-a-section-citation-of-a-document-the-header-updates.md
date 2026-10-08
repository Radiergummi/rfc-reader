# An amendment is a section citation of a document the header updates

*Decided September 2026 (issue #179).*
When RFC B updates RFC A, the sections of A it amends are the sections of A it cites: `Amendments.links(in:)` in RFCKit takes every citation of a *section* of a document in `header.updates`, from the abstract and from each section's own heading and blocks, one link per place.
A section that holds a bibliography is left out: a citation in a reference's annotation describes that entry, and amends nothing (none in the corpus does today, and the rule keeps one from turning up as a false positive).
Only the documents the header says it updates count, so an ordinary citation of another document's section is never an amendment; a citation of a whole document names no section and is left to the document-level status.
A citation of a section of a series, a BCP, STD or FYI, names no RFC, and counts as one of the RFC in it that the document updates, given the series' members (`links(in:members:)`, from the index): only when exactly one member is updated, never guessing between two (#417, October 2026). No document in either corpus has such a citation today, because a section cited through a `<referencegroup>` already resolves to its member (#444), so the rule is for what a caller passes in, not a measured gain.
The broad rule was chosen over one that reads only sections titled after the amended document (`Updates to RFC 2119`), which is more precise and misses every document that states its amendments in its introduction.
Measured over the 9,835 documents of the corpus: 605 of the 1,255 that update another amend by section, 2,632 links to 1,836 distinct sections.
Its precision is not measured yet, and has to be before a marker shows it.
The rows are the shape #174's extractors take, so the pack can carry them and a reader can ask which later documents amend the open one; nothing shows them until it does.
