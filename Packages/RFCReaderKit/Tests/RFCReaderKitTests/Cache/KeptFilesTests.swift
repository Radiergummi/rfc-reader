import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The data files the store keeps beside the index, read back with when they were
/// kept, which is when they were fetched (#758).
@Suite("Kept files")
struct KeptFilesTests {
  private let sandbox = DocumentStoreTests.Sandbox()

  private func setModified(_ name: String, ago: TimeInterval) throws {
    try FileManager.default.setAttributes(
      [.modificationDate: Date.now.addingTimeInterval(-ago)],
      ofItemAtPath: sandbox.directory.appending(path: name).path)
  }

  // MARK: - Registries

  private static let statusCodes = """
    <?xml version='1.0' encoding='UTF-8'?>
    <registry xmlns="http://www.iana.org/assignments" id="http-status-codes">
      <registry id="http-status-codes-1">
        <record>
          <value>425</value>
          <description>Too Early</description>
        </record>
      </registry>
    </registry>
    """

  @Test func `a registry kept within its age is read, and not due`() async throws {
    defer { sandbox.remove() }
    let store = sandbox.store()
    try await store.storeRegistry(Data(Self.statusCodes.utf8), for: .httpStatusCodes)
    let cached = await store.cachedRegistries(maximumAge: RegistryRefresh.maximumAge)
    #expect(cached.entries[.httpStatusCodes]?.map(\.value) == ["425"])
    #expect(!cached.stale.contains(.httpStatusCodes))
    #expect(Set(cached.stale) == Set(IANARegistry.allCases).subtracting([.httpStatusCodes]))
  }

  /// Read all the same, to answer with until the fetch succeeds.
  @Test func `a registry kept past its age is read, and due`() async throws {
    defer { sandbox.remove() }
    let store = sandbox.store()
    try await store.storeRegistry(Data(Self.statusCodes.utf8), for: .httpStatusCodes)
    try setModified("Registries/http-status-codes.xml", ago: RegistryRefresh.maximumAge + 60)
    let cached = await store.cachedRegistries(maximumAge: RegistryRefresh.maximumAge)
    #expect(cached.entries[.httpStatusCodes]?.map(\.value) == ["425"])
    #expect(cached.stale.contains(.httpStatusCodes))
  }

  @Test func `a registry kept that no longer parses is due, with nothing read`() async throws {
    defer { sandbox.remove() }
    let store = sandbox.store()
    try await store.storeRegistry(Data("<html/>".utf8), for: .httpStatusCodes)
    let cached = await store.cachedRegistries(maximumAge: RegistryRefresh.maximumAge)
    #expect(cached.entries[.httpStatusCodes] == nil)
    #expect(cached.stale.contains(.httpStatusCodes))
  }
}
