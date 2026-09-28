import Foundation
import SQLite3

/// Persistent catalogue: WAL SQLite + FTS5, incremental by path/mtime/size.
actor CatalogueIndexStore {
    static let shared = CatalogueIndexStore()

    private var db: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let schemaVersion = "2"

    init() {
        db = Self.connect()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func loadAll() -> [IndexedTrackRecord] {
        guard let db else { return [] }
        let sql = """
        SELECT path, title, artist, album, track_number, year, duration, format,
               sample_rate, bit_depth, channel_count, file_size, mtime, artwork_hash, filename, labels
        FROM tracks
        ORDER BY artist COLLATE NOCASE, album COLLATE NOCASE, track_number ASC, title COLLATE NOCASE
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [IndexedTrackRecord] = []
        rows.reserveCapacity(4096)
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(record(from: stmt))
        }
        return rows
    }

    func fingerprints(underPrefix prefix: String? = nil) -> [String: StoredFingerprint] {
        guard let db else { return [:] }
        let sql: String
        if prefix != nil {
            sql = "SELECT path, file_size, mtime FROM tracks WHERE path LIKE ? ESCAPE '\\'"
        } else {
            sql = "SELECT path, file_size, mtime FROM tracks"
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [:] }
        defer { sqlite3_finalize(stmt) }
        if let prefix {
            bindText(stmt, 1, likePrefix(prefix))
        }

        var map: [String: StoredFingerprint] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = string(stmt, 0)
            map[path] = StoredFingerprint(
                path: path,
                fileSize: sqlite3_column_int64(stmt, 1),
                mtime: sqlite3_column_double(stmt, 2)
            )
        }
        return map
    }

    func upsert(_ records: [IndexedTrackRecord]) {
        guard let db, !records.isEmpty else { return }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        let sql = """
        INSERT INTO tracks (
            path, title, artist, album, track_number, year, duration, format,
            sample_rate, bit_depth, channel_count, file_size, mtime, artwork_hash, filename, labels
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            title=excluded.title,
            artist=excluded.artist,
            album=excluded.album,
            track_number=excluded.track_number,
            year=excluded.year,
            duration=excluded.duration,
            format=excluded.format,
            sample_rate=excluded.sample_rate,
            bit_depth=excluded.bit_depth,
            channel_count=excluded.channel_count,
            file_size=excluded.file_size,
            mtime=excluded.mtime,
            artwork_hash=excluded.artwork_hash,
            filename=excluded.filename,
            labels=excluded.labels
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for record in records {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            bindText(stmt, 1, record.path)
            bindText(stmt, 2, record.title)
            bindText(stmt, 3, record.artist)
            bindText(stmt, 4, record.album)
            bindOptionalInt(stmt, 5, record.trackNumber)
            bindOptionalInt(stmt, 6, record.year)
            sqlite3_bind_double(stmt, 7, record.duration)
            bindText(stmt, 8, record.format.rawValue)
            bindOptionalInt(stmt, 9, record.sampleRateHz)
            bindOptionalInt(stmt, 10, record.bitDepth)
            bindOptionalInt(stmt, 11, record.channelCount)
            sqlite3_bind_int64(stmt, 12, record.fileSize)
            sqlite3_bind_double(stmt, 13, record.mtime)
            if let hash = record.artworkHash {
                bindText(stmt, 14, hash)
            } else {
                sqlite3_bind_null(stmt, 14)
            }
            bindText(stmt, 15, record.filename)
            bindText(stmt, 16, encodeLabels(record.labels))
            sqlite3_step(stmt)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    func delete(paths: [String]) {
        guard let db, !paths.isEmpty else { return }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM tracks WHERE path = ?", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }
        for path in paths {
            sqlite3_reset(stmt)
            bindText(stmt, 1, path)
            sqlite3_step(stmt)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    func delete(underPrefix prefix: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM tracks WHERE path LIKE ? ESCAPE '\\'", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, likePrefix(prefix))
        sqlite3_step(stmt)
    }

    func updateLabels(path: String, labels: [String]) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE tracks SET labels = ? WHERE path = ?", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, encodeLabels(labels))
        bindText(stmt, 2, path)
        sqlite3_step(stmt)
    }

    func searchPaths(query: String) -> [String] {
        let fts = Self.ftsQuery(from: query)
        guard let db, let fts else { return [] }
        let sql = """
        SELECT t.path
        FROM tracks_fts
        JOIN tracks t ON t.rowid = tracks_fts.rowid
        WHERE tracks_fts MATCH ?
        ORDER BY rank
        LIMIT 2000
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, fts)

        var paths: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            paths.append(string(stmt, 0))
        }
        return paths
    }

    func trackCount() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM tracks", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func artworkHashes() -> Set<String> {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT DISTINCT artwork_hash FROM tracks WHERE artwork_hash IS NOT NULL", -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var hashes = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            hashes.insert(string(stmt, 0))
        }
        return hashes
    }

    private static func connect() -> OpaquePointer? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("AudioHarbor", isDirectory: true)
            .appendingPathComponent("CatalogueIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("catalogue.sqlite")

        var db: OpaquePointer?
        if sqlite3_open_v2(
            url.path,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) != SQLITE_OK {
            if let db { sqlite3_close(db) }
            return nil
        }

        applyPragmas(db)
        if !migrateIfNeeded(db) {
            sqlite3_close(db)
            db = nil
            try? FileManager.default.removeItem(at: url)
            if sqlite3_open_v2(
                url.path,
                &db,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            ) != SQLITE_OK {
                if let db { sqlite3_close(db) }
                return nil
            }
            applyPragmas(db)
            _ = migrateIfNeeded(db)
        }
        return db
    }

    private static func applyPragmas(_ db: OpaquePointer?) {
        guard let db else { return }
        sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA temp_store = MEMORY", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA cache_size = -16000", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA mmap_size = 268435456", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
    }

    private static func migrateIfNeeded(_ db: OpaquePointer?) -> Bool {
        guard let db else { return false }
        sqlite3_exec(
            db,
            "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)",
            nil, nil, nil
        )
        let version = metaValue(db, "schema_version")
        if version == schemaVersion {
            return true
        }
        if version != nil {
            sqlite3_exec(db, "DROP TABLE IF EXISTS tracks_fts", nil, nil, nil)
            sqlite3_exec(db, "DROP TABLE IF EXISTS tracks", nil, nil, nil)
        }
        return createSchema(db)
    }

    private static func createSchema(_ db: OpaquePointer?) -> Bool {
        guard let db else { return false }
        let ddl = """
        CREATE TABLE IF NOT EXISTS tracks (
            path TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT NOT NULL,
            track_number INTEGER,
            year INTEGER,
            duration REAL NOT NULL,
            format TEXT NOT NULL,
            sample_rate INTEGER,
            bit_depth INTEGER,
            channel_count INTEGER,
            file_size INTEGER NOT NULL,
            mtime REAL NOT NULL,
            artwork_hash TEXT,
            filename TEXT NOT NULL,
            labels TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_tracks_album_artist ON tracks(album, artist);
        CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);
        CREATE INDEX IF NOT EXISTS idx_tracks_filename ON tracks(filename);
        CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5(
            title, artist, album, filename, labels,
            content='tracks',
            content_rowid='rowid',
            tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER IF NOT EXISTS tracks_ai AFTER INSERT ON tracks BEGIN
            INSERT INTO tracks_fts(rowid, title, artist, album, filename, labels)
            VALUES (new.rowid, new.title, new.artist, new.album, new.filename, new.labels);
        END;
        CREATE TRIGGER IF NOT EXISTS tracks_ad AFTER DELETE ON tracks BEGIN
            INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album, filename, labels)
            VALUES ('delete', old.rowid, old.title, old.artist, old.album, old.filename, old.labels);
        END;
        CREATE TRIGGER IF NOT EXISTS tracks_au AFTER UPDATE ON tracks BEGIN
            INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album, filename, labels)
            VALUES ('delete', old.rowid, old.title, old.artist, old.album, old.filename, old.labels);
            INSERT INTO tracks_fts(rowid, title, artist, album, filename, labels)
            VALUES (new.rowid, new.title, new.artist, new.album, new.filename, new.labels);
        END;
        """
        guard sqlite3_exec(db, ddl, nil, nil, nil) == SQLITE_OK else { return false }
        setMeta(db, "schema_version", schemaVersion)
        return true
    }

    private static func metaValue(_ db: OpaquePointer?, _ key: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = ?", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    private static func setMeta(_ db: OpaquePointer?, _ key: String, _ value: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, key, -1, transient)
        sqlite3_bind_text(stmt, 2, value, -1, transient)
        sqlite3_step(stmt)
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
    }

    private func bindOptionalInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(stmt, index, Int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func string(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    private func optionalString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let c = sqlite3_column_text(stmt, index)
        else { return nil }
        return String(cString: c)
    }

    private func optionalInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, index))
    }

    private func record(from stmt: OpaquePointer?) -> IndexedTrackRecord {
        IndexedTrackRecord(
            path: string(stmt, 0),
            title: string(stmt, 1),
            artist: string(stmt, 2),
            album: string(stmt, 3),
            trackNumber: optionalInt(stmt, 4),
            year: optionalInt(stmt, 5),
            duration: sqlite3_column_double(stmt, 6),
            format: AudioFormat(rawValue: string(stmt, 7)) ?? .unknown,
            sampleRateHz: optionalInt(stmt, 8),
            bitDepth: optionalInt(stmt, 9),
            channelCount: optionalInt(stmt, 10),
            fileSize: sqlite3_column_int64(stmt, 11),
            mtime: sqlite3_column_double(stmt, 12),
            artworkHash: optionalString(stmt, 13),
            filename: string(stmt, 14),
            labels: decodeLabels(string(stmt, 15))
        )
    }

    private func likePrefix(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "\(escaped)/%"
    }

    private func encodeLabels(_ labels: [String]) -> String {
        labels.joined(separator: "\u{1f}")
    }

    private func decodeLabels(_ raw: String) -> [String] {
        raw.split(separator: "\u{1f}", omittingEmptySubsequences: true).map(String.init)
    }

    static func ftsQuery(from raw: String) -> String? {
        let tokens = raw
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens
            .map { token in
                let cleaned = token.replacingOccurrences(of: "\"", with: "")
                return "\"\(cleaned)\"*"
            }
            .joined(separator: " ")
    }
}
