import Testing

@testable import RFCReaderKit

/// The name a file saved to Downloads gets: its own, or with a number when that is
/// taken, as Safari names a second download of the same file. Asked name by name,
/// so a folder of thousands is never listed to save one file.
@Suite("Download name")
struct DownloadNameTests {
  @Test func `a free name is kept`() {
    #expect(DownloadName.unique("rfc9110.pdf", isTaken: { _ in false }) == "rfc9110.pdf")
  }

  @Test func `a taken name gets the next free number`() {
    #expect(DownloadName.unique("rfc9110.pdf", isTaken: { $0 == "rfc9110.pdf" }) == "rfc9110 2.pdf")
    #expect(
      DownloadName.unique("rfc9110.pdf", isTaken: ["rfc9110.pdf", "rfc9110 2.pdf"].contains)
        == "rfc9110 3.pdf")
  }

  @Test func `a name without an extension is numbered at its end`() {
    #expect(DownloadName.unique("README", isTaken: { $0 == "README" }) == "README 2")
  }
}
