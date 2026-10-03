import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Acknowledgements")
struct AcknowledgementsTests {
  /// The app shows what the repository says; one is the other.
  @Test func `the app's notices are the repository's`() throws {
    // Packages/RFCReaderKit/Tests/RFCReaderKitTests/Chrome/AcknowledgementsTests.swift
    let root = URL(filePath: #filePath)
      .deletingLastPathComponent()  // AcknowledgementsTests.swift
      .deletingLastPathComponent()  // Chrome
      .deletingLastPathComponent()  // RFCReaderKitTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // RFCReaderKit
      .deletingLastPathComponent()  // Packages
    let file = try String(
      contentsOf: root.appending(path: "THIRD_PARTY_NOTICES"), encoding: .utf8)
    #expect(Acknowledgements.text == file.trimmingCharacters(in: .newlines))
  }

  @Test func `they carry both licenses`() {
    #expect(Acknowledgements.text.contains("Chroma"))
    #expect(Acknowledgements.text.contains("Pygments"))
    #expect(Acknowledgements.text.contains("Permission is hereby granted"))
    #expect(Acknowledgements.text.contains("Redistribution and use in source and binary forms"))
  }
}
