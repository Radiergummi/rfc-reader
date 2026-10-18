# The indexes pack ships in the app bundle

*Decided October 2026 (#738).*

The `indexes` pack, `indexes.sqlite` with its manifest, ships inside the app as a resource, uncompressed, and updates arrive with app updates. It moves to a download, on first use, through the cheap-network session and with its archive digest pinned outside the archive, once it adds more than **10 MB compressed** to the app's download.

Measured first, as the issue asked: `corpus-build index` over all 9,835 converted and modern documents, release build, M3 Pro, on 2026-10-18, writes 199,710 citations, 35,046 successions and 2,639 amendments in 86 s. The file is 20.7 MB; zipped 4.5 MB, xz 2.5 MB. The citations and their two indexes are 17.3 MB of it, the successions 3.2 MB, the amendments 0.2 MB. The installed Mac app was 31 MB before it.

The first published pack, `indexes-2026.10.1` (corpus.yml run 39169725735, converting the corpus afresh), is 20.1 MB, with 193,933 citations and 2,836 amendments over the same 9,835 documents.

It is not compressed inside the bundle: the App Store and a disk image compress the download already, so a compressed copy would save nothing there and cost the disk twice, once compressed and once unpacked for SQLite to read in place.

Where a build gets it. Building it needs the whole converted corpus, which takes about 20 minutes to fetch and convert, so no app build makes it. `corpus.yml`, asked with `publish_indexes`, publishes it as a release of its own per pack version, `indexes-YYYY.MM.N`: created as a draft, given the two files, and only then published, after which the repository's immutable releases keep it from changing. `App/indexes-pack.mk` pins the tag and both files' SHA-256, and `make indexes-pack` downloads that release into the gitignored `App/Resources/indexes` and refuses a file that differs. A Release build fails without it; a Debug build goes without, and offers no reading path. Committing the 20 MB file through Git LFS was the alternative, and the repository's Pages site the first proposal. A release suits a versioned pack: what failed for the revisions feed was rewriting one release daily, which an immutable release refuses and a pack never needs.

The app reads the bundled copy, unless one installed in `Packs/indexes` has a later manifest version (`IndexesPack.preferred`), compared number by number. Nothing downloads one yet; the debug `-installIndexesPack` stays for development, and a locally built pack, versioned `dev`, counts as later than any dated one.

The pack is one pack, not one per table: a table added later (`terms`, #397; `rules`, #695) raises `IndexSchema.version` and the pack's version, and the size is measured again against the threshold.
