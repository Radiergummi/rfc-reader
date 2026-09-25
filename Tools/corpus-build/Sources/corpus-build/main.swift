import Foundation
import RFCKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// corpus-build: the offline half of RFC Reader's data pipeline.
//
//   corpus-build fetch    --out corpus [--format text|xml] [--index rfc-index.xml] [--limit N] [--concurrency 6]
//   corpus-build convert  --in corpus/text.noindex --out corpus/xml.noindex [--overrides corpus/overrides] [--report corpus/report.json]
//                         [--diagnostics corpus/prose.json]
//   corpus-build manifest --dir corpus/xml.noindex --out corpus/manifest.json --version 2026.09
//   corpus-build queries  --in corpus/xml.noindex --out Tools/corpus-build/Evaluation/queries-xref.json
//                         [--limit 4000] [--seed 11] [--min-words 8]
//
// See docs/DATA_PIPELINE.md for the why and the pack layout.

let arguments = Arguments(CommandLine.arguments.dropFirst())

do {
    switch arguments.command {
    case "fetch": try await Fetch.run(arguments)
    case "convert": try Convert.run(arguments)
    case "manifest": try Manifest.run(arguments)
    case "queries": try Queries.run(arguments)
    default:
        FileHandle.standardError.write(Data("usage: corpus-build fetch|convert|manifest|queries [options]\n".utf8))
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

        // Two disjoint halves of the same corpus, fetched the same way.
        //
        //   --format text  the 8,457 RFCs published before RFCXML, which `convert`
        //                  then turns into synthetic XML
        //   --format xml   the 1,378 that were authored in RFCXML and need no
        //                  conversion at all, so they land straight in the XML
        //                  directory beside the converted ones
        //
        // `hasXMLSource` partitions the index, so the two runs never write the same
        // file and `manifest --dir xml.noindex` sees the union without being told.
        let format: FileFormat = arguments["format"] == "xml" ? .xml : .text
        let directory = outDirectory.appending(path: format == .xml ? "xml.noindex" : "text.noindex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

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
        var wanted = index.rfcs
            .filter { format == .xml ? $0.hasXMLSource : (!$0.hasXMLSource && $0.formats.contains(.text)) }
            .map(\.id)
        if let limit = arguments["limit"].flatMap(Int.init) { wanted = Array(wanted.prefix(limit)) }
        let suffix = format.pathExtension
        let missing = wanted.filter { !FileManager.default.fileExists(atPath: directory.appending(path: "\($0.fileStem).\(suffix)").path) }
        log("\(wanted.count) \(format == .xml ? "RFCXML" : "legacy") RFCs, \(missing.count) to fetch")

        let concurrency = arguments["concurrency"].flatMap(Int.init) ?? 6
        var failures: [String] = []
        var completed = 0
        try await withThrowingTaskGroup(of: (DocumentID, Result<Data, any Error>).self) { group in
            var iterator = missing.makeIterator()
            func enqueue() {
                guard let id = iterator.next() else { return }
                group.addTask {
                    do { return (id, .success(try await download(RFCEditorEndpoints.document(id, format: format)))) }
                    catch { return (id, .failure(error)) }
                }
            }
            for _ in 0..<concurrency { enqueue() }
            while let (id, result) = try await group.next() {
                switch result {
                case .success(let data):
                    try data.write(to: directory.appending(path: "\(id.fileStem).\(suffix)"), options: .atomic)
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

    /// What the prose test decided across the corpus, and where it decided narrowly.
    ///
    /// Not every block: at roughly a million of them the file would be unusable. The
    /// two things worth keeping are the shape of the whole — which guard fires, how
    /// often — and the blocks refused by exactly one guard, which is the sample
    /// hand-labelling draws from.
    struct ProseReport: Codable {
        var documents = 0
        var blocks = 0
        var prose = 0
        /// Claimed by the list parser, so never put to the prose test.
        var lists = 0
        var nearMisses = 0
        /// How often each guard refused a block, counting a block once per guard.
        var byRejection: [String: Int] = [:]
        /// How often each guard was the *only* one to refuse: relax that guard alone,
        /// and this many blocks change their verdict.
        var soleRejection: [String: Int] = [:]
        /// Which justification tell dissented, among blocks where the others agreed.
        var justificationDissent: [String: Int] = [:]
        /// The near misses themselves, capped. The counts above stay exact; this is a
        /// sample and is named one. A full corpus run puts the near-miss population in
        /// the hundreds of thousands, which is tens of megabytes of JSON nobody reads.
        var sample: [NearMiss] = []
    }

    /// Enough near misses to see the shape of each guard's population by eye.
    static let sampleLimit = 2000

    struct NearMiss: Codable {
        var document: String
        var section: String
        var firstLine: String
        var lineCount: Int
        var rejection: String
        var indent: Int
        var firstLineIndent: Int
        var artworkMatches: Int
        var sentenceRatio: Double
    }

    static func accumulate(_ text: String, id: String, into report: inout ProseReport) {
        report.documents += 1
        for block in LegacyTextParser.proseDiagnostics(for: text) {
            let diagnosis = block.diagnosis
            report.blocks += 1
            if block.claimedByList {
                report.lists += 1
                continue
            }
            if diagnosis.isProse {
                report.prose += 1
                continue
            }
            for rejection in diagnosis.rejections {
                report.byRejection[rejection.rawValue, default: 0] += 1
            }
            // The tells gate the internalGap guard and nothing else, so counting dissent
            // on a block refused elsewhere would mix in blocks where they were inert.
            if diagnosis.rejections.contains(.internalGap) {
                let dissent = diagnosis.justification.dissenting
                if dissent.count == 1, let only = dissent.first {
                    report.justificationDissent[only, default: 0] += 1
                }
            }
            guard diagnosis.isNearMiss, let rejection = diagnosis.rejections.first else { continue }
            report.nearMisses += 1
            report.soleRejection[rejection.rawValue, default: 0] += 1
            guard report.sample.count < sampleLimit else { continue }
            report.sample.append(NearMiss(
                document: id,
                section: block.section,
                firstLine: block.firstLine,
                lineCount: block.lineCount,
                rejection: rejection.rawValue,
                indent: diagnosis.indent,
                firstLineIndent: diagnosis.firstLineIndent,
                artworkMatches: diagnosis.artworkMatches,
                sentenceRatio: (diagnosis.sentenceRatio * 1000).rounded() / 1000
            ))
        }
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
        // Diagnosing re-segments every document, which roughly doubles the run. Only pay
        // it when the report is actually asked for. Overridden documents are hand-corrected,
        // so they `continue` below and never reach the accumulator at all.
        let wantsDiagnostics = arguments["diagnostics"] != nil
        var prose = ProseReport()
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
            if wantsDiagnostics { accumulate(text, id: stem, into: &prose) }
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
            try writeJSON(reports, to: reportPath)
        }
        if let diagnosticsPath = arguments["diagnostics"] {
            try writeJSON(prose, to: diagnosticsPath)
            let rejected = prose.blocks - prose.prose - prose.lists
            log("prose: \(prose.blocks) blocks, \(prose.lists) lists, \(prose.prose) prose, \(rejected) rejected, \(prose.nearMisses) by one guard only")
            for (guardName, count) in prose.soleRejection.sorted(by: { $0.value > $1.value }) {
                log("  only \(guardName): \(count)")
            }
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
        try writeJSON(manifest, to: output.path)
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

/// `.sortedKeys` is what makes these files diffable between corpus runs, so the encoder
/// is configured in one place rather than at each of the three call sites.
func writeJSON(_ value: some Encodable, to path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: URL(fileURLWithPath: path), options: .atomic)
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

// MARK: - Query set extraction

/// Builds the cross-reference judgement set used to measure search ranking (#37).
///
/// A cross reference that names a section of another RFC is a relevance judgement its
/// author already made: the sentence around it says what the target section is about.
/// Excise the citation and that sentence becomes a query whose answer is known, which
/// is the only way to get thousands of judgements without writing them by hand.
///
/// The filtering lives here rather than in a scratch script because the committed set
/// is worthless if it cannot be reproduced.
enum Queries {
    /// Function words carry no discrimination over a corpus of specifications; a
    /// sentence made only of these describes nothing and cannot identify a section.
    static let stopwords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being", "do", "does", "did",
        "how", "what", "when", "where", "why", "which", "who", "whom", "whose", "that", "this",
        "these", "those", "i", "it", "its", "he", "she", "they", "them", "their", "you", "your",
        "and", "or", "but", "if", "then", "than", "so", "as", "at", "by", "for", "from", "in",
        "into", "of", "on", "to", "with", "without", "not", "no", "can", "could", "may", "might",
        "must", "shall", "should", "will", "would", "have", "has", "had", "get", "got", "about",
        "there", "here", "out", "up", "down", "over", "under", "again", "only", "own", "same",
    ]

    /// A citation found at a known offset in the flattened text of one paragraph.
    private struct Citation {
        let target: String
        let section: String
        let start: Int
        let length: Int
    }

    private struct Candidate {
        let query: String
        let fromDoc: String
        let toDoc: String
        let toSection: String
    }

    struct Row: Encodable {
        let q: String
        let kind: String
        let primary: String
        let from: String
        let answers: [[String]]
    }

    static func run(_ arguments: Arguments) throws {
        let input = URL(fileURLWithPath: arguments.require("in"))
        let output = URL(fileURLWithPath: arguments.require("out"))
        let limit = arguments["limit"].flatMap(Int.init) ?? 4000
        let seed = arguments["seed"].flatMap(UInt64.init) ?? 11
        let minimumWords = arguments["min-words"].flatMap(Int.init) ?? 8

        let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        log("reading \(files.count) documents")

        // Every numbered section in the corpus, so a citation pointing at one that was
        // never parsed can be dropped rather than counted as a miss nobody can reach.
        var known: Set<String> = []
        var candidates: [Candidate] = []
        var unparseable = 0

        for (index, file) in files.enumerated() {
            guard let data = try? Data(contentsOf: file), let document = try? RFCXMLParser.parse(data) else {
                unparseable += 1
                continue
            }
            let id = document.header.id?.description ?? file.deletingPathExtension().lastPathComponent
            for section in document.allSections {
                if let number = section.number, !number.isEmpty { known.insert("\(id)\u{1F}\(number)") }
                collect(section.blocks) { text, citations in
                    for citation in citations {
                        guard let sentence = sentence(around: citation, in: text) else { continue }
                        candidates.append(Candidate(query: sentence, fromDoc: id,
                                                    toDoc: citation.target, toSection: citation.section))
                    }
                }
            }
            if (index + 1) % 2000 == 0 { log("  \(index + 1)/\(files.count)") }
        }
        log("\(candidates.count) citing sentences recovered (\(unparseable) documents unparseable)")

        var kept: [Row] = []
        var seen: Set<String> = []
        var dropped: [String: Int] = [:]
        let shortReason = "under \(minimumWords) content words"
        for candidate in candidates {
            guard known.contains("\(candidate.toDoc)\u{1F}\(candidate.toSection)") else {
                dropped["target not in corpus", default: 0] += 1; continue
            }
            guard candidate.fromDoc != candidate.toDoc else {
                dropped["self-citation", default: 0] += 1; continue
            }
            let content = words(in: candidate.query).map { $0.lowercased() }.filter { !stopwords.contains($0) }
            guard content.count >= minimumWords else {
                dropped[shortReason, default: 0] += 1; continue
            }
            let key = String(content.sorted().joined(separator: " ").prefix(120))
            guard seen.insert(key).inserted else {
                dropped["near-duplicate", default: 0] += 1; continue
            }
            kept.append(Row(q: candidate.query, kind: "xref", primary: candidate.toDoc,
                            from: candidate.fromDoc, answers: [[candidate.toDoc, candidate.toSection]]))
        }
        for (reason, count) in dropped.sorted(by: { $0.value > $1.value }) { log("  dropped \(count) \(reason)") }
        log("\(kept.count) usable")

        // Seeded so the committed set can be reproduced exactly; Swift's own shuffle
        // takes the system generator and would give a different sample every run.
        var generator = SplitMix64(seed: seed)
        kept.shuffle(using: &generator)
        let sample = Array(kept.prefix(limit))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(sample).write(to: output, options: .atomic)
        log("wrote \(sample.count) queries to \(output.path)")
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") })
            .map(String.init)
            .filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
    }

    /// Flattens inlines exactly as `plainText` does, recording where each qualifying
    /// cross reference landed. The two must stay in step or the offsets are lies.
    private static func flatten(_ inlines: [Inline], into text: inout [Character], citations: inout [Citation]) {
        for inline in inlines {
            switch inline {
            case .text(let value), .code(let value), .superscript(let value), .subscript(let value):
                text += value
            case .emphasis(let inner), .strong(let inner), .link(_, let inner):
                flatten(inner, into: &text, citations: &citations)
            case .lineBreak:
                text += "\n"
            case .crossReference(let reference):
                let label = reference.displayLabel
                if case .document(let id, let section) = reference.target, let section {
                    citations.append(Citation(target: id.description,
                                              section: section, start: text.count, length: label.count))
                }
                text += label
            }
        }
    }

    /// The sentence containing the citation, with the citation excised so the query
    /// cannot simply name its own answer.
    private static func sentence(around citation: Citation, in characters: [Character]) -> String? {
        let end = citation.start + citation.length
        guard citation.start < characters.count, end <= characters.count else { return nil }
        var low = citation.start
        while low > 0, characters[low - 1] != ".", characters[low - 1] != "\n" { low -= 1 }
        var high = end
        while high < characters.count {
            let character = characters[high]
            high += 1
            if character == "." || character == "\n" { break }
        }
        guard low < citation.start, high > end else { return nil }
        let before = String(characters[low..<citation.start])
        let after = String(characters[end..<high])
        return (before + " " + after)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collect(_ blocks: [Block], _ handle: ([Character], [Citation]) -> Void) {
        for block in blocks {
            switch block {
            case .paragraph(let paragraph):
                var text: [Character] = []
                var citations: [Citation] = []
                flatten(paragraph.inlines, into: &text, citations: &citations)
                if !citations.isEmpty { handle(text, citations) }
            case .list(let list):
                for item in list.items { collect(item.blocks, handle) }
            case .definitionList(let items):
                for item in items { collect(item.definition, handle) }
            case .figure(let figure):
                collect(figure.blocks, handle)
            case .blockQuote(let inner), .aside(let inner):
                collect(inner, handle)
            default:
                break
            }
        }
    }
}

/// A small seeded generator, so `--seed` reproduces a sample byte for byte on any
/// platform. `SystemRandomNumberGenerator` cannot be seeded and CI runs on Linux.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
