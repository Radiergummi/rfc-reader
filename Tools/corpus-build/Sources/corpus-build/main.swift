import Foundation
import RFCKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// corpus-build: the offline half of RFC Reader's data pipeline.
//
//   corpus-build fetch    --out corpus [--index rfc-index.xml] [--limit N] [--concurrency 6]
//   corpus-build convert  --in corpus/text.noindex --out corpus/xml.noindex [--overrides corpus/overrides] [--report corpus/report.json]
//   corpus-build manifest --dir corpus/xml.noindex --out corpus/manifest.json --version 2026.09
//
// See docs/DATA_PIPELINE.md for the why and the pack layout.

let arguments = Arguments(CommandLine.arguments.dropFirst())

do {
    switch arguments.command {
    case "fetch": try await Fetch.run(arguments)
    case "convert": try Convert.run(arguments)
    case "manifest": try Manifest.run(arguments)
    default:
        FileHandle.standardError.write(Data("usage: corpus-build fetch|convert|manifest [options]\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

// MARK: - Commands

enum Fetch {
    static func run(_ arguments: Arguments) async throws {
        let outDirectory = URL(fileURLWithPath: arguments.require("out"))
        let textDirectory = outDirectory.appending(path: "text.noindex")
        try FileManager.default.createDirectory(at: textDirectory, withIntermediateDirectories: true)

        let index: RFCIndex
        if let path = arguments["index"] {
            log("reading index from \(path)")
            index = try RFCIndexParser.parse(contentsOf: URL(fileURLWithPath: path))
        } else {
            log("downloading index")
            let data = try await download(RFCEditorEndpoints.index)
            try data.write(to: outDirectory.appending(path: "rfc-index.xml"), options: .atomic)
            index = try RFCIndexParser.parse(data)
        }

        // A few early RFCs exist only as PDF scans; there is nothing to fetch for them.
        var wanted = index.rfcs.filter { !$0.hasXMLSource && $0.formats.contains(.text) }.map(\.id)
        if let limit = arguments["limit"].flatMap(Int.init) { wanted = Array(wanted.prefix(limit)) }
        let missing = wanted.filter { !FileManager.default.fileExists(atPath: textDirectory.appending(path: "\($0.fileStem).txt").path) }
        log("\(wanted.count) legacy RFCs, \(missing.count) to fetch")

        let concurrency = arguments["concurrency"].flatMap(Int.init) ?? 6
        var failures: [String] = []
        var completed = 0
        try await withThrowingTaskGroup(of: (DocumentID, Result<Data, any Error>).self) { group in
            var iterator = missing.makeIterator()
            func enqueue() {
                guard let id = iterator.next() else { return }
                group.addTask {
                    do { return (id, .success(try await download(RFCEditorEndpoints.document(id, format: .text)))) }
                    catch { return (id, .failure(error)) }
                }
            }
            for _ in 0..<concurrency { enqueue() }
            while let (id, result) = try await group.next() {
                switch result {
                case .success(let data):
                    try data.write(to: textDirectory.appending(path: "\(id.fileStem).txt"), options: .atomic)
                case .failure(let error):
                    failures.append("\(id): \(error)")
                }
                completed += 1
                if completed % 250 == 0 { log("\(completed)/\(missing.count)") }
                enqueue()
            }
        }
        log("done, \(failures.count) failures")
        for failure in failures { log("  \(failure)") }
        if !failures.isEmpty { exit(1) }
    }

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("rfc-reader corpus-build (+https://github.com/Radiergummi/rfc-reader)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PipelineError.http((response as? HTTPURLResponse)?.statusCode ?? -1, url)
        }
        return data
    }
}

enum Convert {
    struct Report: Codable {
        var id: String
        var title: String
        var sections: Int
        var paragraphs: Int
        var lists: Int
        var artwork: Int
        var references: Int
        var resolvedDocuments: Int
        var overridden: Bool
        var warnings: [String]
    }

    static func run(_ arguments: Arguments) throws {
        let inDirectory = URL(fileURLWithPath: arguments.require("in"))
        let outDirectory = URL(fileURLWithPath: arguments.require("out"))
        let overrides = arguments["overrides"].map { URL(fileURLWithPath: $0) }
        try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)

        let files = try FileManager.default.contentsOfDirectory(atPath: inDirectory.path)
            .filter { $0.hasSuffix(".txt") }
            .sorted { ($0.rfcNumber ?? 0) < ($1.rfcNumber ?? 0) }
        log("converting \(files.count) documents")

        var reports: [Report] = []
        for (offset, file) in files.enumerated() {
            let stem = String(file.dropLast(4))
            let outputURL = outDirectory.appending(path: "\(stem).xml")

            if let overrides, FileManager.default.fileExists(atPath: overrides.appending(path: "\(stem).xml").path) {
                let data = try Data(contentsOf: overrides.appending(path: "\(stem).xml"))
                let document = try RFCXMLParser.parse(data)   // overrides must at least parse
                try data.write(to: outputURL, options: .atomic)
                reports.append(report(for: document, id: stem, overridden: true))
                continue
            }

            // 34 pre-2000 RFCs are Latin-1 / Windows-1252 rather than UTF-8 (accented names, curly quotes).
            let bytes = try Data(contentsOf: inDirectory.appending(path: file))
            let text = String(data: bytes, encoding: .utf8)
                ?? String(data: bytes, encoding: .windowsCP1252)
                ?? String(decoding: bytes, as: UTF8.self)
            let document = LegacyTextParser.parse(text)
            let sourceURL = DocumentID(parsing: stem).map { RFCEditorEndpoints.document($0, format: .text) }
            let serializer = RFCXMLSerializer(options: .init(
                generatorComment: "Generated by rfc-reader corpus-build from \(file). Structure recovered heuristically from the plain-text RFC; the text itself is unchanged. Corrections: https://github.com/Radiergummi/rfc-reader",
                sourceURL: sourceURL
            ))
            let xml = serializer.serialize(document)
            try Data(xml.utf8).write(to: outputURL, options: .atomic)

            // Round-trip check: the XML must parse back into the same section tree.
            var warnings: [String] = []
            do {
                let reparsed = try RFCXMLParser.parse(Data(xml.utf8))
                if reparsed.allSections.count != document.allSections.count {
                    warnings.append("round trip changed section count \(document.allSections.count) → \(reparsed.allSections.count)")
                }
            } catch {
                warnings.append("generated XML does not parse: \(error)")
            }
            var entry = report(for: document, id: stem, overridden: false)
            entry.warnings += warnings
            reports.append(entry)

            if (offset + 1) % 500 == 0 { log("\(offset + 1)/\(files.count)") }
        }

        if let reportPath = arguments["report"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(reports).write(to: URL(fileURLWithPath: reportPath), options: .atomic)
        }
        let flagged = reports.filter { !$0.warnings.isEmpty }
        log("done: \(reports.count) converted, \(reports.filter(\.overridden).count) overridden, \(flagged.count) with warnings")
        for entry in flagged.prefix(40) { log("  \(entry.id): \(entry.warnings.joined(separator: "; "))") }
    }

    static func report(for document: RFCDocument, id: String, overridden: Bool) -> Report {
        var paragraphs = 0, lists = 0, artwork = 0, references = 0
        func count(_ blocks: [Block]) {
            for block in blocks {
                switch block {
                case .paragraph: paragraphs += 1
                case .list(let list): lists += 1; list.items.forEach { count($0.blocks) }
                case .definitionList(let items): items.forEach { count($0.definition) }
                case .preformatted: artwork += 1
                case .figure(let figure): count(figure.blocks)
                case .blockQuote(let inner), .aside(let inner): count(inner)
                case .references(let list): references += list.entries.count
                case .table: break
                }
            }
        }
        document.allSections.forEach { count($0.blocks) }

        var warnings: [String] = []
        if document.header.id == nil { warnings.append("no RFC number recognised in front matter") }
        if document.header.title.isEmpty { warnings.append("no title") }
        if document.sections.isEmpty { warnings.append("no sections") }
        if paragraphs == 0 { warnings.append("no prose paragraphs") }
        if artwork > paragraphs { warnings.append("more artwork than prose (\(artwork) vs \(paragraphs)); check classification") }

        return Report(
            id: id, title: document.header.title, sections: document.allSections.count,
            paragraphs: paragraphs, lists: lists, artwork: artwork, references: references,
            resolvedDocuments: document.referencedDocuments.count, overridden: overridden, warnings: warnings
        )
    }
}

enum Manifest {
    struct Entry: Codable {
        var path: String
        var bytes: Int
        var sha256: String
    }

    struct File: Codable {
        var version: String
        var generatedAt: String
        var files: [Entry]
    }

    static func run(_ arguments: Arguments) throws {
        let directory = URL(fileURLWithPath: arguments.require("dir"))
        let output = URL(fileURLWithPath: arguments.require("out"))
        let version = arguments.require("version")

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        var entries: [Entry] = []
        for name in names where !name.hasPrefix(".") {
            let data = try Data(contentsOf: directory.appending(path: name))
            entries.append(Entry(path: name, bytes: data.count, sha256: SHA256.hex(data)))
        }
        let manifest = File(version: version, generatedAt: ISO8601DateFormatter().string(from: .now), files: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: output, options: .atomic)
        log("wrote \(entries.count) entries to \(output.path)")
    }
}

// MARK: - Support

enum PipelineError: Error, CustomStringConvertible {
    case http(Int, URL)
    case missingArgument(String)

    var description: String {
        switch self {
        case .http(let status, let url): "HTTP \(status) for \(url)"
        case .missingArgument(let name): "missing --\(name)"
        }
    }
}

struct Arguments {
    let command: String
    private var options: [String: String] = [:]

    init(_ raw: ArraySlice<String>) {
        var iterator = raw.makeIterator()
        command = iterator.next() ?? ""
        while let token = iterator.next() {
            guard token.hasPrefix("--") else { continue }
            let key = String(token.dropFirst(2))
            options[key] = iterator.next() ?? ""
        }
    }

    subscript(key: String) -> String? { options[key] }

    func require(_ key: String) -> String {
        guard let value = options[key], !value.isEmpty else {
            FileHandle.standardError.write(Data("error: missing --\(key)\n".utf8))
            exit(2)
        }
        return value
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

extension String {
    var rfcNumber: Int? {
        DocumentID(parsing: String(split(separator: ".").first ?? ""))?.number
    }
}

/// Minimal SHA-256 so the manifest needs no crypto dependency on Linux.
enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hex(_ input: Data) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var message = [UInt8](input)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8((bitLength >> UInt64(shift)) & 0xff)) }

        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(message[j]) << 24 | UInt32(message[j + 1]) << 16 | UInt32(message[j + 2]) << 8 | UInt32(message[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotr(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
