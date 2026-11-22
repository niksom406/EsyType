import Foundation

/// CSV reading and writing shared by the dictionary and snippets (RFC 4180, UTF-8). Data only: nothing in a file is ever run.
public enum CSVFile {
    public static let maxBytes = 2_000_000, maxRows = 10_000

    public enum FileError: Error, Equatable, LocalizedError {
        case notUTF8, empty, tooLarge, unterminatedQuote(line: Int), missingColumns([String])

        public var errorDescription: String? {
            switch self {
            case .notUTF8: "The file isn’t UTF-8 text. Save it as “CSV UTF-8” and try again."
            case .empty: "The file is empty."
            case .tooLarge: "The file is too large (limit \(CSVFile.maxBytes / 1_000_000) MB or \(CSVFile.maxRows) rows)."
            case .unterminatedQuote(let line): "A quoted value starting on line \(line) is never closed."
            case .missingColumns(let names): "The first line must name the columns. Missing: \(names.joined(separator: ", "))."
            }
        }
    }

    /// Reads a file with a header line. `make` turns one row (by column name) into an item, or a reason it's rejected.
    public static func parse<Item>(_ data: Data, required: [String],
                                   make: (_ value: (String) -> String) -> Result<Item, RowError>) throws(FileError) -> [CSVRow<Item>] {
        guard data.count <= maxBytes else { throw .tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw .notUTF8 }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() } // Excel's byte-order mark
        let records = try records(text)
        guard let header = records.first?.1 else { throw .empty }
        let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let missing = required.filter { !names.contains($0) }
        guard missing.isEmpty else { throw .missingColumns(missing) }
        guard records.count - 1 <= maxRows else { throw .tooLarge }
        let index = Dictionary(names.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return records.dropFirst().compactMap { line, fields in
            if fields.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { return nil } // blank line
            guard fields.count == names.count else {
                return CSVRow(line: line, result: .failure(RowError(reason: "Expected \(names.count) values, found \(fields.count).")))
            }
            return CSVRow(line: line, result: make { name in index[name].map { unprotect(fields[$0]) } ?? "" })
        }
    }

    /// UTF-8 with a byte-order mark (so Excel reads Hindi and Marathi correctly), CRLF line ends, every value quoted.
    public static func export(header: [String], rows: [[String]]) -> Data {
        let text = ([header] + rows.map { $0.map(protect) })
            .map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
        return Data(("\u{FEFF}" + text).utf8)
    }

    /// `true/yes/1/empty` or `false/no/0`; nil for anything else.
    public static func bool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes", "1", "": true
        case "false", "no", "0": false
        default: nil
        }
    }

    /// Spreadsheet apps run values starting with these as formulas (CSV injection). Export prefixes an apostrophe;
    /// import removes it again, so a round trip keeps the text.
    private static let formulaStarts: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]
    static func protect(_ value: String) -> String { value.first.map(formulaStarts.contains) == true ? "'" + value : value }
    static func unprotect(_ value: String) -> String {
        value.count > 1 && value.first == "'" && formulaStarts.contains(value[value.index(after: value.startIndex)])
            ? String(value.dropFirst()) : value
    }

    /// Splits RFC 4180 text into records, each with the line number it starts on.
    static func records(_ text: String) throws(FileError) -> [(Int, [String])] {
        var records: [(Int, [String])] = [], fields: [String] = [], field = ""
        var quoted = false, line = 1, start = 1, i = 0
        let chars = Array(text)
        func endRecord() { fields.append(field); records.append((start, fields)); fields = []; field = "" }
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    if c.isNewline { line += 1 }
                    field.append(c)
                }
            } else if c == "\"", field.isEmpty {
                quoted = true
            } else if c == "," {
                fields.append(field); field = ""
            } else if c.isNewline { // "\r\n" is one Character in Swift
                endRecord(); line += 1; start = line
            } else {
                field.append(c)
            }
            i += 1
        }
        if quoted { throw .unterminatedQuote(line: start) }
        if !field.isEmpty || !fields.isEmpty { endRecord() }
        return records
    }
}

/// One data row: the item, or why it was rejected. `line` is the line it starts on in the file.
public struct CSVRow<Item: Equatable & Sendable>: Equatable, Sendable {
    public let line: Int
    public let result: Result<Item, RowError>
}

public struct RowError: Error, Equatable, Sendable { public let reason: String }

/// What an import would do, shown to the user before anything changes.
public struct ImportPlan<Item: Equatable & Sendable>: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public var additions: [Item] = []
    /// Rows for items already in the list with different details. Applied only if the user says so.
    public var updates: [Item] = []
    public var skipped = 0
    public var rejected: [(line: Int, reason: String)] = []

    public static func == (a: ImportPlan, b: ImportPlan) -> Bool {
        a.additions == b.additions && a.updates == b.updates && a.skipped == b.skipped
            && a.rejected.map(\.line) == b.rejected.map(\.line) && a.rejected.map(\.reason) == b.rejected.map(\.reason)
    }

    /// Compares imported rows with `existing`. Same `scope`: identical (`same`) → skipped, different → update
    /// (with the existing item's identity, via `keeping`). Two rows in the file for the same scope with different
    /// content: the later one is rejected.
    public init(rows: [CSVRow<Item>], existing: [Item], scope: (Item) -> String, same: (Item, Item) -> Bool,
                keeping: (_ existing: Item, _ new: Item) -> Item) {
        var seen: [String: (line: Int, item: Item)] = [:]
        for row in rows {
            switch row.result {
            case .failure(let error): rejected.append((row.line, error.reason))
            case .success(let item):
                if let earlier = seen[scope(item)] {
                    if same(earlier.item, item) { skipped += 1 }
                    else { rejected.append((row.line, "Conflicts with line \(earlier.line): same words, different text.")) }
                    continue
                }
                seen[scope(item)] = (row.line, item)
                if let current = existing.first(where: { scope($0) == scope(item) }) {
                    if same(current, item) { skipped += 1 } else { updates.append(keeping(current, item)) }
                } else {
                    additions.append(item)
                }
            }
        }
    }

    init() {}
}

/// A list kept as versioned JSON in Application Support, readable only by the user.
public struct ListFile<Item: Codable & Sendable>: Sendable {
    public let url: URL

    public init(_ url: URL) { self.url = url }

    public static func inSupportFolder(_ name: String) -> URL {
        ModelStore.defaultDirectory.deletingLastPathComponent().appending(path: name)
    }

    private struct File: Codable { var version = 1; var entries: [Item] }

    /// A damaged file is moved aside (never deleted) and an empty list is used; `recovered` says so.
    public func load() -> (items: [Item], recovered: Bool) {
        guard let data = try? Data(contentsOf: url) else { return ([], false) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(File.self, from: data) { return (file.entries, false) }
        let aside = url.deletingPathExtension().appendingPathExtension("damaged-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return ([], true)
    }

    public func save(_ items: [Item]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(File(entries: items)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
