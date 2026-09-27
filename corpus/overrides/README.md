# Overrides

Hand-corrected RFCXML files, one per legacy RFC, named `rfcNNNN.xml`. When present, `corpus-build convert` publishes the override instead of the generated file (after checking that it parses). Fix the heuristic in RFCKit when a whole class of documents is wrong. When one document is, the correction waits for [#197](https://github.com/Radiergummi/rfc-reader/issues/197): an override is a whole converted document, which is RFC text, so no new one is committed (see `CLAUDE.md`).

An override that was corrected mechanically keeps the script that made it beside it (`rfc1142.py` for `rfc1142.xml`), so the correction can be reviewed and rerun rather than trusted. Such an override is a snapshot of the converter's output, so rerun its script after any converter change that would alter that output, and commit the result. `make corpus-overrides-check` says whether one is stale.
