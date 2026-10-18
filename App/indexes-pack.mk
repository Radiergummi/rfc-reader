# The indexes pack the app bundles (#738): a release of this repository, which
# corpus.yml publishes as `indexes-<version>` with the pack's two files, and their
# SHA-256 as that run's summary prints them. `make indexes-pack` downloads the
# pinned release's files and refuses any that differs. A new pack is pinned by
# replacing all three lines with the summary of the run that published it.
INDEXES_PACK_TAG :=
INDEXES_PACK_SQLITE_SHA256 :=
INDEXES_PACK_MANIFEST_SHA256 :=
