# The indexes pack the app bundles (#738): a release of this repository, which
# corpus.yml publishes as `indexes-<version>` with the pack's two files, and their
# SHA-256 as that run's summary prints them. `make indexes-pack` downloads the
# pinned release's files and refuses any that differs. A new pack is pinned by
# replacing all three lines with the summary of the run that published it.
INDEXES_PACK_TAG := indexes-2026.10.1
INDEXES_PACK_SQLITE_SHA256 := ed2774690eb44a3baca35545a5ba884a68ca876e8cecef0c6be22a370f6bb42b
INDEXES_PACK_MANIFEST_SHA256 := 763efa11413c39b601f9406e292ee0b529de9eebced11d9a2c2c55cf20bc9685
