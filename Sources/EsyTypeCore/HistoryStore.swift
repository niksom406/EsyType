import Foundation
import SQLite3

public struct HistoryEntry: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let createdAt: Date
    public let text: String
    public let language: String
    public let durationMs: Int
    public let modelID: String
    public let appBundleID: String?
    /// False when EsyType couldn't type it and copied it instead ("Not inserted").
    public let inserted: Bool
}

public enum HistoryError: Error, Equatable { case sqlite(String) }

/// Dictation history in one SQLite file (owner read/write only). Text only: audio is never stored.
public actor HistoryStore {
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "EsyType/history.sqlite")
    }

    // Only used inside the actor, and by deinit once nothing else can reach it.
    private nonisolated(unsafe) let db: OpaquePointer

    public init(url: URL = defaultURL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            sqlite3_close(handle)
            throw HistoryError.sqlite("Can't open the history file.")
        }
        db = handle
        try Self.exec(db, """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY,
                created_at REAL NOT NULL,
                text TEXT NOT NULL,
                language TEXT NOT NULL,
                duration_ms INTEGER NOT NULL,
                model_id TEXT NOT NULL,
                app_bundle_id TEXT
            );
            CREATE INDEX IF NOT EXISTS entries_created_at ON entries (created_at);
            """)
        // Added 2026-11-23. Older files gain the column; their rows count as typed.
        try? Self.exec(db, "ALTER TABLE entries ADD COLUMN inserted INTEGER NOT NULL DEFAULT 1;")
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    public func add(text: String, language: String, durationMs: Int, modelID: String, appBundleID: String?,
                    inserted: Bool = true, at date: Date = .now) throws -> HistoryEntry {
        try run("INSERT INTO entries (created_at, text, language, duration_ms, model_id, app_bundle_id, inserted) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [date.timeIntervalSince1970, text, language, Int64(durationMs), modelID, appBundleID, Int64(inserted ? 1 : 0)])
        return HistoryEntry(id: sqlite3_last_insert_rowid(db), createdAt: date, text: text, language: language,
                            durationMs: durationMs, modelID: modelID, appBundleID: appBundleID, inserted: inserted)
    }

    public func setInserted(id: Int64, _ inserted: Bool) throws {
        try run("UPDATE entries SET inserted = ? WHERE id = ?", [Int64(inserted ? 1 : 0), id])
    }

    /// Edit a dictation's text (History ▸ Edit).
    public func update(id: Int64, text: String) throws { try run("UPDATE entries SET text = ? WHERE id = ?", [text, id]) }

    /// Newest first. `search` matches anywhere in the text (case-insensitive for Latin letters; any script works).
    // shortcut: a full scan, fine for tens of thousands of entries; add FTS5 (trigram) if history gets far bigger.
    public func entries(search: String = "", limit: Int = 500) throws -> [HistoryEntry] {
        try query("""
            SELECT id, created_at, text, language, duration_ms, model_id, app_bundle_id, inserted FROM entries
            WHERE ?1 = '' OR instr(lower(text), lower(?1)) > 0
            ORDER BY created_at DESC, id DESC LIMIT ?2
            """, [search, Int64(limit)])
    }

    public func delete(id: Int64) throws { try run("DELETE FROM entries WHERE id = ?", [id]) }

    public func deleteAll() throws { try run("DELETE FROM entries", []) }

    public func deleteOlder(than date: Date) throws {
        try run("DELETE FROM entries WHERE created_at < ?", [date.timeIntervalSince1970])
    }

    // MARK: SQLite plumbing

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw HistoryError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func run(_ sql: String, _ values: [Any?]) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HistoryError.sqlite(String(cString: sqlite3_errmsg(db))) }
    }

    private func query(_ sql: String, _ values: [Any?]) throws -> [HistoryEntry] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var rows: [HistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(HistoryEntry(
                id: sqlite3_column_int64(statement, 0),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                text: String(cString: sqlite3_column_text(statement, 2)),
                language: String(cString: sqlite3_column_text(statement, 3)),
                durationMs: Int(sqlite3_column_int64(statement, 4)),
                modelID: String(cString: sqlite3_column_text(statement, 5)),
                appBundleID: sqlite3_column_text(statement, 6).map { String(cString: $0) },
                inserted: sqlite3_column_int64(statement, 7) != 0))
        }
        return rows
    }

    private func prepare(_ sql: String, _ values: [Any?]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self) // SQLITE_TRANSIENT: SQLite copies the text
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let text as String: sqlite3_bind_text(statement, position, text, -1, transient)
            case let number as Int64: sqlite3_bind_int64(statement, position, number)
            case let number as Double: sqlite3_bind_double(statement, position, number)
            default: sqlite3_bind_null(statement, position)
            }
        }
        return statement
    }
}

/// History exports (History ▸ Export CSV / JSON): when, app, words, status and the text.
public enum HistoryExport {
    public static func csv(_ entries: [HistoryEntry], appName: (String) -> String?) -> Data {
        CSVFile.export(header: ["date", "app", "words", "seconds", "language", "inserted", "text"], rows: entries.map {
            [SnippetCSV.stamp($0.createdAt), $0.appBundleID.flatMap(appName) ?? "", "\(InsightsLog.wordCount($0.text))",
             "\($0.durationMs / 1000)", $0.language, $0.inserted ? "true" : "false", $0.text]
        })
    }

    public static func json(_ entries: [HistoryEntry], appName: (String) -> String?) -> Data {
        CSVFile.exportJSON(entries.map {
            ["date": SnippetCSV.stamp($0.createdAt), "app": $0.appBundleID.flatMap(appName) ?? "", "words": InsightsLog.wordCount($0.text),
             "seconds": $0.durationMs / 1000, "language": $0.language, "inserted": $0.inserted, "text": $0.text]
        })
    }
}
