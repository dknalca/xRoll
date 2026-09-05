import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct PracticeAttempt: Equatable {
    public let exerciseID: String
    public let timestamp: Date
    public let bpm: Int
    public let score: Double
    public let stars: Int
    public let perfect: Int
    public let good: Int
    public let regular: Int
    public let miss: Int
    public let extra: Int
    public let meanOffsetMilliseconds: Double?

    public init(exerciseID: String, timestamp: Date, bpm: Int, score: Double, stars: Int, perfect: Int, good: Int, regular: Int, miss: Int, extra: Int, meanOffsetMilliseconds: Double?) {
        self.exerciseID = exerciseID; self.timestamp = timestamp; self.bpm = bpm; self.score = score; self.stars = stars
        self.perfect = perfect; self.good = good; self.regular = regular; self.miss = miss; self.extra = extra; self.meanOffsetMilliseconds = meanOffsetMilliseconds
    }
}

public struct ExerciseProgress: Equatable {
    public let attemptCount: Int
    public let bestScore: Double
    public let latestScore: Double
}

public enum ProgressStoreError: LocalizedError {
    case sqlite(String)
    public var errorDescription: String? { if case .sqlite(let message) = self { return message }; return nil }
}

public final class ProgressStore {
    private var database: OpaquePointer?

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &database) == SQLITE_OK else { throw ProgressStoreError.sqlite("No se pudo abrir la base de datos.") }
        try execute("""
        CREATE TABLE IF NOT EXISTS attempts (
          id INTEGER PRIMARY KEY, exercise_id TEXT NOT NULL, timestamp REAL NOT NULL,
          bpm INTEGER NOT NULL, score REAL NOT NULL, stars INTEGER NOT NULL,
          perfect INTEGER NOT NULL, good INTEGER NOT NULL, regular INTEGER NOT NULL,
          miss INTEGER NOT NULL, extra INTEGER NOT NULL, mean_offset_ms REAL
        )
        """)
    }

    deinit { sqlite3_close(database) }

    public func record(_ attempt: PracticeAttempt) throws {
        let statement = try prepare("INSERT INTO attempts VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, attempt.exerciseID, -1, sqliteTransient)
        sqlite3_bind_double(statement, 2, attempt.timestamp.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, Int32(attempt.bpm)); sqlite3_bind_double(statement, 4, attempt.score)
        sqlite3_bind_int(statement, 5, Int32(attempt.stars)); sqlite3_bind_int(statement, 6, Int32(attempt.perfect))
        sqlite3_bind_int(statement, 7, Int32(attempt.good)); sqlite3_bind_int(statement, 8, Int32(attempt.regular))
        sqlite3_bind_int(statement, 9, Int32(attempt.miss)); sqlite3_bind_int(statement, 10, Int32(attempt.extra))
        if let offset = attempt.meanOffsetMilliseconds { sqlite3_bind_double(statement, 11, offset) } else { sqlite3_bind_null(statement, 11) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
    }

    public func progress(for exerciseID: String) throws -> ExerciseProgress? {
        let statement = try prepare("SELECT COUNT(*), MAX(score), (SELECT score FROM attempts WHERE exercise_id = ? ORDER BY timestamp DESC, id DESC LIMIT 1) FROM attempts WHERE exercise_id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, exerciseID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, exerciseID, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_int(statement, 0) > 0 else { return nil }
        return ExerciseProgress(attemptCount: Int(sqlite3_column_int(statement, 0)), bestScore: sqlite3_column_double(statement, 1), latestScore: sqlite3_column_double(statement, 2))
    }

    public func scores(for exerciseID: String, limit: Int = 20) throws -> [Double] {
        let statement = try prepare("SELECT score FROM attempts WHERE exercise_id = ? ORDER BY timestamp ASC, id ASC LIMIT ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, exerciseID, -1, sqliteTransient)
        sqlite3_bind_int(statement, 2, Int32(max(1, limit)))
        var scores: [Double] = []
        while sqlite3_step(statement) == SQLITE_ROW { scores.append(sqlite3_column_double(statement, 0)) }
        return scores
    }

    private func execute(_ sql: String) throws { let statement = try prepare(sql); defer { sqlite3_finalize(statement) }; guard sqlite3_step(statement) == SQLITE_DONE else { throw error() } }
    private func prepare(_ sql: String) throws -> OpaquePointer? { var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }; return statement }
    private func error() -> ProgressStoreError { ProgressStoreError.sqlite(String(cString: sqlite3_errmsg(database))) }
}
