import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct PracticeAttempt: Codable, Equatable {
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
    public let soundStatistics: [SoundStatistics]
    public let hitRecords: [HitRecord]
    public let trainingContext: TrainingContext

    public init(exerciseID: String, timestamp: Date, bpm: Int, score: Double, stars: Int, perfect: Int, good: Int, regular: Int, miss: Int, extra: Int, meanOffsetMilliseconds: Double?, soundStatistics: [SoundStatistics] = [], hitRecords: [HitRecord] = [], trainingContext: TrainingContext = .init()) {
        self.exerciseID = exerciseID; self.timestamp = timestamp; self.bpm = bpm; self.score = score; self.stars = stars
        self.perfect = perfect; self.good = good; self.regular = regular; self.miss = miss; self.extra = extra; self.meanOffsetMilliseconds = meanOffsetMilliseconds
        self.soundStatistics = soundStatistics
        self.hitRecords = hitRecords
        self.trainingContext = trainingContext
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseID, timestamp, bpm, score, stars, perfect, good, regular, miss, extra
        case meanOffsetMilliseconds, soundStatistics, hitRecords, trainingContext, timestampUnixSeconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        exerciseID = try values.decode(String.self, forKey: .exerciseID)
        // ISO 8601 sin fracciones pierde precisión y rompe la deduplicación al
        // restaurar el propio archivo. Conservamos también el valor de SQLite.
        if let seconds = try values.decodeIfPresent(Double.self, forKey: .timestampUnixSeconds) {
            timestamp = Date(timeIntervalSince1970: seconds)
        } else {
            timestamp = try values.decode(Date.self, forKey: .timestamp)
        }
        bpm = try values.decode(Int.self, forKey: .bpm)
        score = try values.decode(Double.self, forKey: .score)
        stars = try values.decode(Int.self, forKey: .stars)
        perfect = try values.decode(Int.self, forKey: .perfect)
        good = try values.decode(Int.self, forKey: .good)
        regular = try values.decode(Int.self, forKey: .regular)
        miss = try values.decode(Int.self, forKey: .miss)
        extra = try values.decode(Int.self, forKey: .extra)
        meanOffsetMilliseconds = try values.decodeIfPresent(Double.self, forKey: .meanOffsetMilliseconds)
        soundStatistics = try values.decodeIfPresent([SoundStatistics].self, forKey: .soundStatistics) ?? []
        hitRecords = try values.decodeIfPresent([HitRecord].self, forKey: .hitRecords) ?? []
        trainingContext = try values.decodeIfPresent(TrainingContext.self, forKey: .trainingContext)
            ?? .init(evaluationScope: .legacyUnknown)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(exerciseID, forKey: .exerciseID)
        try values.encode(timestamp, forKey: .timestamp)
        try values.encode(timestamp.timeIntervalSince1970, forKey: .timestampUnixSeconds)
        try values.encode(bpm, forKey: .bpm)
        try values.encode(score, forKey: .score)
        try values.encode(stars, forKey: .stars)
        try values.encode(perfect, forKey: .perfect)
        try values.encode(good, forKey: .good)
        try values.encode(regular, forKey: .regular)
        try values.encode(miss, forKey: .miss)
        try values.encode(extra, forKey: .extra)
        try values.encodeIfPresent(meanOffsetMilliseconds, forKey: .meanOffsetMilliseconds)
        try values.encode(soundStatistics, forKey: .soundStatistics)
        try values.encode(hitRecords, forKey: .hitRecords)
        try values.encode(trainingContext, forKey: .trainingContext)
    }

    /// Rechaza datos de historial inválidos antes de convertirlos a enteros
    /// SQLite. Un archivo importado debe producir un error, no cerrar la app.
    fileprivate func validateForStorage() throws {
        guard !exerciseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              timestamp.timeIntervalSince1970.isFinite,
              bpm > 0, Int32(exactly: bpm) != nil,
              score.isFinite, (0...100).contains(score), (0...3).contains(stars),
              [perfect, good, regular, miss, extra].allSatisfy({ $0 >= 0 && Int32(exactly: $0) != nil }),
              meanOffsetMilliseconds?.isFinite != false,
              trainingContext.isValidForHistory,
              hitRecords.allSatisfy(\.isValidForHistory),
              soundStatistics.allSatisfy(\.isValidForHistory) else {
            throw ProgressStoreError.invalidAttempt(exerciseID)
        }
    }
}

/// Evidencia compacta que basta para calcular el curso y la escalera sin
/// cargar todos los registros de golpes del historial.
public struct CourseAttemptEvidence: Equatable {
    public let exerciseID: String
    public let bpm: Int
    public let score: Double
    public let stars: Int
    public let trainingContext: TrainingContext

    public init(exerciseID: String, bpm: Int, score: Double, stars: Int = 0, trainingContext: TrainingContext) {
        self.exerciseID = exerciseID
        self.bpm = bpm
        self.score = score
        self.stars = stars
        self.trainingContext = trainingContext
    }

    public init(attempt: PracticeAttempt) {
        self.init(exerciseID: attempt.exerciseID, bpm: attempt.bpm, score: attempt.score, stars: attempt.stars, trainingContext: attempt.trainingContext)
    }

    /// Solo el curso usa esta proyección: dos mejores intentos por condición
    /// acreditable bastan para los premios, incluido Dominio. El historial y la
    /// exportación conservan todos los intentos y sus condiciones originales.
    public static func compacted(_ evidence: [CourseAttemptEvidence]) -> [CourseAttemptEvidence] {
        struct Key: Hashable {
            let id: String
            let bpm: Int
            let scope: String
            let bars: Int
            let policy: Int?
            let stars: Int
        }
        var groups = [Key: [CourseAttemptEvidence]]()
        for item in evidence {
            let key = Key(id: item.exerciseID, bpm: item.bpm, scope: item.trainingContext.evaluationScope.rawValue,
                bars: item.trainingContext.completedBars, policy: item.trainingContext.tempoPolicyVersion, stars: item.stars)
            var best = groups[key, default: []]
            best.append(item)
            best.sort { $0.score > $1.score }
            groups[key] = Array(best.prefix(2))
        }
        return groups.values.flatMap { $0 }
    }
}

/// Instantánea de lectura calculada en el worker; las vistas no decodifican ni
/// agrupan registros de golpes al reconstruir su árbol.
public struct ProgressSnapshot {
    public let recentAttempts: [PracticeAttempt]
    public let filteredAttempts: [PracticeAttempt]
    public let courseEvidence: [CourseAttemptEvidence]
    public let courseLevels: [CourseLevelState]
    public let campaignWorlds: [CourseWorld]
    public let diagnostics: HistoricalDiagnostics
    public let masterySeals: [MasterySeal]
}

public struct ExerciseProgress: Equatable {
    public let attemptCount: Int
    public let bestScore: Double
    public let latestScore: Double
}

public struct ExerciseProgressDetail: Equatable {
    public let progress: ExerciseProgress?
    public let recentScores: [Double]
}

public struct ProgressFilter: Equatable {
    public var exerciseID: String?
    public var minimumScore: Double?
    public var maximumScore: Double?
    public var from: Date?
    public var to: Date?
    public init(exerciseID: String? = nil, minimumScore: Double? = nil, maximumScore: Double? = nil, from: Date? = nil, to: Date? = nil) {
        self.exerciseID = exerciseID; self.minimumScore = minimumScore; self.maximumScore = maximumScore; self.from = from; self.to = to
    }
}

public enum ProgressStoreError: LocalizedError {
    case sqlite(String)
    case invalidAttempt(String)
    case invalidExportDestination
    case invalidImportFile
    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): return message
        case .invalidAttempt(let id): return "El intento de \(id) contiene valores de historial no válidos."
        case .invalidExportDestination: return "Elige un archivo distinto de la base de datos del historial."
        case .invalidImportFile: return "El historial debe ser un array JSON de intentos válidos."
        }
    }
}

public final class ProgressStore {
    private var database: OpaquePointer?
    private let databaseURL: URL
    private static let exportQueue = DispatchQueue(label: "xRoll.progress-export", qos: .utility)

    public enum ExportFormat: String { case csv, json }

    private struct AttemptImportIdentity: Hashable {
        let exerciseID: String
        let timestamp: Double
        let bpm: Int
        let score: Double
        let stars: Int
        let perfect: Int
        let good: Int
        let regular: Int
        let miss: Int
        let extra: Int
        let meanOffsetMilliseconds: Double?

        init(_ attempt: PracticeAttempt) {
            exerciseID = attempt.exerciseID
            timestamp = attempt.timestamp.timeIntervalSince1970
            bpm = attempt.bpm
            score = attempt.score
            stars = attempt.stars
            perfect = attempt.perfect
            good = attempt.good
            regular = attempt.regular
            miss = attempt.miss
            extra = attempt.extra
            meanOffsetMilliseconds = attempt.meanOffsetMilliseconds
        }

        init(
            exerciseID: String,
            timestamp: Double,
            bpm: Int,
            score: Double,
            stars: Int,
            perfect: Int,
            good: Int,
            regular: Int,
            miss: Int,
            extra: Int,
            meanOffsetMilliseconds: Double?
        ) {
            self.exerciseID = exerciseID
            self.timestamp = timestamp
            self.bpm = bpm
            self.score = score
            self.stars = stars
            self.perfect = perfect
            self.good = good
            self.regular = regular
            self.miss = miss
            self.extra = extra
            self.meanOffsetMilliseconds = meanOffsetMilliseconds
        }
    }

    public init(url: URL) throws {
        databaseURL = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "No se pudo abrir la base de datos."
            if let database { sqlite3_close(database) }
            database = nil
            throw ProgressStoreError.sqlite(message)
        }
        try execute("""
        CREATE TABLE IF NOT EXISTS attempts (
          id INTEGER PRIMARY KEY, exercise_id TEXT NOT NULL, timestamp REAL NOT NULL,
          bpm INTEGER NOT NULL, score REAL NOT NULL, stars INTEGER NOT NULL,
          perfect INTEGER NOT NULL, good INTEGER NOT NULL, regular INTEGER NOT NULL,
          miss INTEGER NOT NULL, extra INTEGER NOT NULL, mean_offset_ms REAL,
          sound_stats_json TEXT, hit_records_json TEXT, training_context_json TEXT
        )
        """)
        // Bases anteriores conservan los intentos y reciben las columnas nuevas.
        var columns = try columnNames(in: "attempts")
        for (name, definition) in [
            ("sound_stats_json", "TEXT"),
            ("hit_records_json", "TEXT"),
            ("training_context_json", "TEXT")
        ] where !columns.contains(name) {
            try execute("ALTER TABLE attempts ADD COLUMN \(name) \(definition)")
            columns.insert(name)
        }
        try execute("CREATE TABLE IF NOT EXISTS training_state (state_key TEXT PRIMARY KEY NOT NULL, value_json TEXT NOT NULL)")
        // El exportador tiene su propia conexión de lectura. WAL permite que
        // guardar un intento no compita con una exportación larga del historial.
        try execute("PRAGMA journal_mode=WAL")
        sqlite3_busy_timeout(database, 5_000)
        try execute("CREATE INDEX IF NOT EXISTS attempts_exercise_time ON attempts(exercise_id, timestamp DESC, id DESC)")
        try execute("CREATE INDEX IF NOT EXISTS attempts_time ON attempts(timestamp DESC, id DESC)")
    }

    private init(readOnlyURL url: URL) throws {
        databaseURL = url
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let failure = error()
            if let database { sqlite3_close(database) }
            database = nil
            throw failure
        }
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func record(_ attempt: PracticeAttempt) throws {
        try attempt.validateForStorage()
        let statement = try prepareAttemptInsert()
        defer { sqlite3_finalize(statement) }
        try insertAttempt(attempt, using: statement, encoder: JSONEncoder())
    }

    private func prepareAttemptInsert() throws -> OpaquePointer? {
        try prepare("INSERT INTO attempts (exercise_id, timestamp, bpm, score, stars, perfect, good, regular, miss, extra, mean_offset_ms, sound_stats_json, hit_records_json, training_context_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
    }

    /// Reutiliza sentencia y encoder en lotes grandes; las columnas JSON siguen
    /// perteneciendo al intento individual y la transacción al llamador.
    private func insertAttempt(_ attempt: PracticeAttempt, using statement: OpaquePointer?, encoder: JSONEncoder) throws {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        sqlite3_bind_text(statement, 1, attempt.exerciseID, -1, sqliteTransient)
        sqlite3_bind_double(statement, 2, attempt.timestamp.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, Int32(attempt.bpm)); sqlite3_bind_double(statement, 4, attempt.score)
        sqlite3_bind_int(statement, 5, Int32(attempt.stars)); sqlite3_bind_int(statement, 6, Int32(attempt.perfect))
        sqlite3_bind_int(statement, 7, Int32(attempt.good)); sqlite3_bind_int(statement, 8, Int32(attempt.regular))
        sqlite3_bind_int(statement, 9, Int32(attempt.miss)); sqlite3_bind_int(statement, 10, Int32(attempt.extra))
        if let offset = attempt.meanOffsetMilliseconds { sqlite3_bind_double(statement, 11, offset) } else { sqlite3_bind_null(statement, 11) }
        let soundData = try encoder.encode(attempt.soundStatistics)
        _ = soundData.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, 12, bytes.baseAddress, Int32(soundData.count), sqliteTransient) }
        let recordData = try encoder.encode(attempt.hitRecords)
        _ = recordData.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, 13, bytes.baseAddress, Int32(recordData.count), sqliteTransient) }
        let contextData = try encoder.encode(attempt.trainingContext)
        _ = contextData.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, 14, bytes.baseAddress, Int32(contextData.count), sqliteTransient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
    }

    /// Persiste estado didáctico versionable sin alterar la tabla histórica de
    /// intentos. Se usa para objetivos de repaso y sesiones diarias pendientes.
    public func saveTrainingState<Value: Encodable>(_ value: Value, forKey key: String) throws {
        let data = try JSONEncoder.xroll.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ProgressStoreError.sqlite("No se pudo codificar el estado de entrenamiento.")
        }
        let statement = try prepare("INSERT INTO training_state (state_key, value_json) VALUES (?, ?) ON CONFLICT(state_key) DO UPDATE SET value_json = excluded.value_json")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, json, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
    }

    public func loadTrainingState<Value: Decodable>(_ type: Value.Type, forKey key: String) throws -> Value? {
        let statement = try prepare("SELECT value_json FROM training_state WHERE state_key = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw error() }
        return try JSONDecoder.xroll.decode(type, from: Data(String(cString: text).utf8))
    }

    /// Importa intentos compartidos en una única transacción e ignora los que
    /// ya existen para que volver a elegir el mismo archivo no duplique progreso.
    @discardableResult
    public func importAttempts(_ importedAttempts: [PracticeAttempt]) throws -> Int {
        guard !importedAttempts.isEmpty else { return 0 }
        var knownAttempts = try existingAttemptImportIdentities()
        try execute("SAVEPOINT import_progress")
        do {
            let statement = try prepareAttemptInsert()
            defer { sqlite3_finalize(statement) }
            let encoder = JSONEncoder()
            var importedCount = 0
            for attempt in importedAttempts {
                try attempt.validateForStorage()
                guard knownAttempts.insert(AttemptImportIdentity(attempt)).inserted else { continue }
                try insertAttempt(attempt, using: statement, encoder: encoder)
                importedCount += 1
            }
            try execute("RELEASE import_progress")
            return importedCount
        } catch {
            try? execute("ROLLBACK TO import_progress")
            try? execute("RELEASE import_progress")
            throw error
        }
    }

    private func existingAttemptImportIdentities() throws -> Set<AttemptImportIdentity> {
        let statement = try prepare("SELECT exercise_id, timestamp, bpm, score, stars, perfect, good, regular, miss, extra, mean_offset_ms FROM attempts")
        defer { sqlite3_finalize(statement) }
        var result = Set<AttemptImportIdentity>()
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let exerciseID = sqlite3_column_text(statement, 0) else { throw error() }
            result.insert(AttemptImportIdentity(
                exerciseID: String(cString: exerciseID),
                timestamp: sqlite3_column_double(statement, 1),
                bpm: Int(sqlite3_column_int(statement, 2)),
                score: sqlite3_column_double(statement, 3),
                stars: Int(sqlite3_column_int(statement, 4)),
                perfect: Int(sqlite3_column_int(statement, 5)),
                good: Int(sqlite3_column_int(statement, 6)),
                regular: Int(sqlite3_column_int(statement, 7)),
                miss: Int(sqlite3_column_int(statement, 8)),
                extra: Int(sqlite3_column_int(statement, 9)),
                meanOffsetMilliseconds: sqlite3_column_type(statement, 10) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_double(statement, 10)
            ))
        }
    }

    public func progress(for exerciseID: String) throws -> ExerciseProgress? {
        let statement = try prepare("SELECT COUNT(*), MAX(score), (SELECT score FROM attempts WHERE exercise_id = ? ORDER BY timestamp DESC, id DESC LIMIT 1) FROM attempts WHERE exercise_id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, exerciseID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, exerciseID, -1, sqliteTransient)
        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW else {
            if status == SQLITE_DONE { return nil }
            throw error()
        }
        guard sqlite3_column_int(statement, 0) > 0 else { return nil }
        return ExerciseProgress(attemptCount: Int(sqlite3_column_int(statement, 0)), bestScore: sqlite3_column_double(statement, 1), latestScore: sqlite3_column_double(statement, 2))
    }

    public func loadProgressDetailInBackground(for exerciseID: String,
                                               completion: @escaping (Result<ExerciseProgressDetail, Error>) -> Void) {
        let source = databaseURL
        Self.exportQueue.async {
            let result = Result {
                let reader = try ProgressStore(readOnlyURL: source)
                let progress = try reader.progress(for: exerciseID)
                let scores = try reader.scores(for: exerciseID)
                return ExerciseProgressDetail(progress: progress, recentScores: scores)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Resumen por todos los ejercicios para recomendaciones de calentamiento;
    /// una consulta agrupada sustituye 129 accesos SQLite en el hilo de interfaz.
    public func loadExerciseProgressInBackground(completion: @escaping (Result<[String: ExerciseProgress], Error>) -> Void) {
        let source = databaseURL
        Self.exportQueue.async {
            let result = Result { try ProgressStore(readOnlyURL: source).allExerciseProgress() }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func allExerciseProgress() throws -> [String: ExerciseProgress] {
        let statement = try prepare("SELECT exercise_id, COUNT(*), MAX(score), (SELECT score FROM attempts AS latest WHERE latest.exercise_id = attempts.exercise_id ORDER BY timestamp DESC, id DESC LIMIT 1) FROM attempts GROUP BY exercise_id")
        defer { sqlite3_finalize(statement) }
        var result = [String: ExerciseProgress]()
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let id = sqlite3_column_text(statement, 0) else { throw error() }
            result[String(cString: id)] = ExerciseProgress(attemptCount: Int(sqlite3_column_int(statement, 1)),
                bestScore: sqlite3_column_double(statement, 2), latestScore: sqlite3_column_double(statement, 3))
        }
    }

    public func scores(for exerciseID: String, limit: Int = 20) throws -> [Double] {
        let statement = try prepare("SELECT score FROM (SELECT score, timestamp, id FROM attempts WHERE exercise_id = ? ORDER BY timestamp DESC, id DESC LIMIT ?) ORDER BY timestamp ASC, id ASC")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, exerciseID, -1, sqliteTransient)
        sqlite3_bind_int(statement, 2, Int32(clamping: max(1, limit)))
        var scores: [Double] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw error() }
            scores.append(sqlite3_column_double(statement, 0))
        }
        return scores
    }

    private func attemptsStatement(filter: ProgressFilter, limit: Int? = nil, ascending: Bool = false) throws -> OpaquePointer? {
        var clauses: [String] = []
        if filter.exerciseID != nil { clauses.append("exercise_id = ?") }
        if filter.minimumScore != nil { clauses.append("score >= ?") }
        if filter.maximumScore != nil { clauses.append("score <= ?") }
        if filter.from != nil { clauses.append("timestamp >= ?") }
        if filter.to != nil { clauses.append("timestamp <= ?") }
        let whereClause = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let order = ascending ? "ASC" : "DESC"
        let suffix = limit == nil ? "" : " LIMIT ?"
        let statement = try prepare("SELECT exercise_id, timestamp, bpm, score, stars, perfect, good, regular, miss, extra, mean_offset_ms, sound_stats_json, hit_records_json, training_context_json FROM attempts\(whereClause) ORDER BY timestamp \(order), id \(order)\(suffix)")
        var index: Int32 = 1
        if let value = filter.exerciseID { sqlite3_bind_text(statement, index, value, -1, sqliteTransient); index += 1 }
        if let value = filter.minimumScore { sqlite3_bind_double(statement, index, value); index += 1 }
        if let value = filter.maximumScore { sqlite3_bind_double(statement, index, value); index += 1 }
        if let value = filter.from { sqlite3_bind_double(statement, index, value.timeIntervalSince1970); index += 1 }
        if let value = filter.to { sqlite3_bind_double(statement, index, value.timeIntervalSince1970); index += 1 }
        if let limit { sqlite3_bind_int64(statement, index, sqlite3_int64(max(1, limit))) }
        return statement
    }

    public func attempts(filter: ProgressFilter = .init(), limit: Int = 100) throws -> [PracticeAttempt] {
        let statement = try attemptsStatement(filter: filter, limit: limit)
        defer { sqlite3_finalize(statement) }
        var result: [PracticeAttempt] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw error() }
            result.append(readAttempt(statement))
        }
        return result
    }

    private func readAttempt(_ statement: OpaquePointer?) -> PracticeAttempt {
        PracticeAttempt(
            exerciseID: String(cString: sqlite3_column_text(statement, 0)),
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            bpm: Int(sqlite3_column_int(statement, 2)), score: sqlite3_column_double(statement, 3),
            stars: Int(sqlite3_column_int(statement, 4)), perfect: Int(sqlite3_column_int(statement, 5)),
            good: Int(sqlite3_column_int(statement, 6)), regular: Int(sqlite3_column_int(statement, 7)),
            miss: Int(sqlite3_column_int(statement, 8)), extra: Int(sqlite3_column_int(statement, 9)),
            meanOffsetMilliseconds: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 10),
            soundStatistics: (decodeColumn([SoundStatistics].self, statement: statement, index: 11) ?? []).filter(\.isValidForHistory),
            hitRecords: (decodeColumn([HitRecord].self, statement: statement, index: 12) ?? []).filter(\.isValidForHistory),
            trainingContext: readContext(statement, index: 13))
    }

    private func readContext(_ statement: OpaquePointer?, index: Int32) -> TrainingContext {
        guard let context = decodeColumn(TrainingContext.self, statement: statement, index: index) else {
            // Solo la ausencia histórica admite la política de legado. Un blob
            // dañado no puede convertirse en evidencia completa por accidente.
            return .init(evaluationScope: sqlite3_column_type(statement, index) == SQLITE_NULL ? .legacyUnknown : .fragment)
        }
        return context.isValidForHistory ? context : .init(evaluationScope: .fragment)
    }

    private func decodeColumn<Value: Decodable>(_ type: Value.Type, statement: OpaquePointer?, index: Int32) -> Value? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_blob(statement, index) else { return nil }
        return try? JSONDecoder().decode(type, from: Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, index))))
    }

    /// Devuelve toda la evidencia ligera necesaria para acreditaciones. No
    /// aplica el límite de intentos recientes ni carga HitRecord ni estadísticas.
    public func courseEvidence() throws -> [CourseAttemptEvidence] {
        let statement = try prepare("SELECT exercise_id, bpm, score, stars, training_context_json FROM attempts ORDER BY timestamp DESC, id DESC")
        defer { sqlite3_finalize(statement) }
        var result = [CourseAttemptEvidence]()
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw error() }
            let context = readContext(statement, index: 4)
            result.append(CourseAttemptEvidence(
                exerciseID: String(cString: sqlite3_column_text(statement, 0)),
                bpm: Int(sqlite3_column_int(statement, 1)),
                score: sqlite3_column_double(statement, 2),
                stars: Int(sqlite3_column_int(statement, 3)),
                trainingContext: context
            ))
        }
        return result
    }

    @discardableResult
    public func exportCSV(to url: URL, filter: ProgressFilter = .init()) throws -> Int {
        try export(to: url, format: .csv, filter: filter)
    }

    @discardableResult
    public func exportJSON(to url: URL, filter: ProgressFilter = .init()) throws -> Int {
        try export(to: url, format: .json, filter: filter)
    }

    /// La interfaz recibe el resultado en main; SQLite y la escritura usan una
    /// conexión exclusiva del worker, nunca la conexión del coordinador.
    public func exportInBackground(to url: URL, format: ExportFormat, filter: ProgressFilter = .init(),
                                   completion: @escaping (Result<Int, Error>) -> Void) {
        let source = databaseURL
        Self.exportQueue.async {
            let result = Result { try ProgressStore(readOnlyURL: source).export(to: url, format: format, filter: filter) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    public func loadSnapshot(exercises: [Exercise], graph: CourseGraph?, filter: ProgressFilter = .init(), selectedExerciseID: String? = nil,
                             diagnosticExerciseID: String? = nil) throws -> ProgressSnapshot {
        try execute("BEGIN")
        defer { try? execute("ROLLBACK") }
        let recent = try attempts(limit: 1_000)
        let filtered = filter == ProgressFilter() ? recent : try attempts(filter: filter, limit: 1_000)
        let evidence = try compactedCourseEvidence()
        let levels = graph?.states(evidence: evidence) ?? []
        let worlds = graph?.worlds(evidence: evidence, states: levels) ?? []
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = selectedExerciseID.flatMap { byID[$0] }
        let masteryAttempts = try selected.map { try attempts(filter: .init(exerciseID: $0.id), limit: 1_000) } ?? []
        let diagnosticSelection = diagnosticExerciseID ?? filter.exerciseID
        let diagnosticAttempts = diagnosticSelection.map { id in filtered.filter { $0.exerciseID == id } } ?? filtered
        return ProgressSnapshot(recentAttempts: recent, filteredAttempts: filtered, courseEvidence: evidence,
            courseLevels: levels, campaignWorlds: worlds,
            diagnostics: HistoricalDiagnosticsBuilder.build(attempts: diagnosticAttempts, exercisesByID: byID),
            masterySeals: selected.map { MasteryEvaluator.seals(exercise: $0, attempts: masteryAttempts) } ?? [])
    }

    /// Cada operación posee su conexión; nunca traslada la del coordinador.
    public func loadSnapshotInBackground(exercises: [Exercise], graph: CourseGraph?, filter: ProgressFilter = .init(), selectedExerciseID: String? = nil,
                                         diagnosticExerciseID: String? = nil,
                                         completion: @escaping (Result<ProgressSnapshot, Error>) -> Void) {
        let source = databaseURL
        Self.exportQueue.async {
            let result = Result { try ProgressStore(readOnlyURL: source).loadSnapshot(exercises: exercises, graph: graph,
                filter: filter, selectedExerciseID: selectedExerciseID, diagnosticExerciseID: diagnosticExerciseID) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Agrupa evidencia directamente desde SQLite y retiene solo dos intentos
    /// por condición curricular, sin construir primero toda la tabla en memoria.
    private func compactedCourseEvidence() throws -> [CourseAttemptEvidence] {
        struct Key: Hashable {
            let id: String
            let bpm: Int
            let scope: EvaluationScope
            let bars: Int
            let policy: Int?
            let stars: Int
        }
        let statement = try prepare("SELECT exercise_id, bpm, score, stars, training_context_json FROM attempts ORDER BY timestamp DESC, id DESC")
        defer { sqlite3_finalize(statement) }
        var grouped = [Key: [CourseAttemptEvidence]]()
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, let pointer = sqlite3_column_text(statement, 0) else { throw error() }
            let context = readContext(statement, index: 4)
            let item = CourseAttemptEvidence(exerciseID: String(cString: pointer),
                bpm: Int(sqlite3_column_int(statement, 1)), score: sqlite3_column_double(statement, 2),
                stars: Int(sqlite3_column_int(statement, 3)), trainingContext: context)
            let key = Key(id: item.exerciseID, bpm: item.bpm, scope: context.evaluationScope,
                bars: context.completedBars, policy: context.tempoPolicyVersion, stars: item.stars)
            var best = grouped[key, default: []]
            if best.count < 2 { best.append(item) }
            else if let weakest = best.indices.min(by: { best[$0].score < best[$1].score }), item.score > best[weakest].score {
                best[weakest] = item
            }
            grouped[key] = best
        }
        return grouped.values.flatMap { $0 }
    }

    /// Lee un objeto cada vez, dentro de una transacción. No carga el array
    /// completo ni mantiene en RAM todas las identidades del historial previo.
    public func importJSON(from url: URL) throws -> Int {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try execute("SAVEPOINT import_json")
        do {
            let existing = try prepare("SELECT 1 FROM attempts WHERE exercise_id = ? AND timestamp = ? AND bpm = ? AND score = ? AND stars = ? AND perfect = ? AND good = ? AND regular = ? AND miss = ? AND extra = ? AND mean_offset_ms IS ? LIMIT 1")
            defer { sqlite3_finalize(existing) }
            let insert = try prepareAttemptInsert()
            defer { sqlite3_finalize(insert) }
            let encoder = JSONEncoder()
            var count = 0
            let decoder = JSONDecoder.xroll
            try ProgressJSONStream.read(file) { data in
                let attempt = try decoder.decode(PracticeAttempt.self, from: data)
                try attempt.validateForStorage()
                sqlite3_reset(existing)
                sqlite3_clear_bindings(existing)
                sqlite3_bind_text(existing, 1, attempt.exerciseID, -1, sqliteTransient)
                sqlite3_bind_double(existing, 2, attempt.timestamp.timeIntervalSince1970)
                sqlite3_bind_int(existing, 3, Int32(attempt.bpm))
                sqlite3_bind_double(existing, 4, attempt.score)
                for (offset, value) in [attempt.stars, attempt.perfect, attempt.good, attempt.regular, attempt.miss, attempt.extra].enumerated() {
                    sqlite3_bind_int(existing, Int32(5 + offset), Int32(value))
                }
                if let offset = attempt.meanOffsetMilliseconds { sqlite3_bind_double(existing, 11, offset) }
                else { sqlite3_bind_null(existing, 11) }
                let status = sqlite3_step(existing)
                guard status == SQLITE_DONE || status == SQLITE_ROW else { throw error() }
                if status == SQLITE_DONE {
                    try insertAttempt(attempt, using: insert, encoder: encoder)
                    count += 1
                }
            }
            try execute("RELEASE import_json")
            return count
        } catch {
            try? execute("ROLLBACK TO import_json")
            try? execute("RELEASE import_json")
            throw error
        }
    }

    public func importJSONInBackground(from url: URL, completion: @escaping (Result<Int, Error>) -> Void) {
        let source = databaseURL
        Self.exportQueue.async {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let result = Result { try ProgressStore(url: source).importJSON(from: url) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Un cursor estable recorre todos los resultados en bloques de 256. Solo
    /// se sustituye el destino cuando se cerró correctamente el archivo temporal.
    private func export(to url: URL, format: ExportFormat, filter: ProgressFilter) throws -> Int {
        let destination = url.standardizedFileURL.resolvingSymlinksInPath()
        let source = databaseURL.standardizedFileURL.resolvingSymlinksInPath()
        guard destination != source,
              ![source.path + "-wal", source.path + "-shm"].contains(destination.path) else {
            throw ProgressStoreError.invalidExportDestination
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".xroll-export-\(UUID().uuidString).tmp")
        let manager = FileManager.default
        guard manager.createFile(atPath: temporary.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? manager.removeItem(at: temporary) }
        let file = try FileHandle(forWritingTo: temporary)
        defer { try? file.close() }
        let statement = try attemptsStatement(filter: filter, ascending: format == .csv)
        defer { sqlite3_finalize(statement) }
        let header = format == .csv ? "exercise_id,timestamp,bpm,score,stars,perfect,good,regular,miss,extra,mean_offset_ms\n" : "[\n"
        try file.write(contentsOf: Data(header.utf8))
        let encoder = JSONEncoder.xroll
        encoder.outputFormatting = [.sortedKeys]
        var count = 0
        var ended = false
        while !ended {
            try autoreleasepool {
                var block = Data()
                for _ in 0..<256 {
                    let status = sqlite3_step(statement)
                    if status == SQLITE_DONE { ended = true; break }
                    guard status == SQLITE_ROW else { throw error() }
                    let attempt = readAttempt(statement)
                    if format == .json {
                        if count > 0 { block.append(contentsOf: ",\n".utf8) }
                        block.append(try encoder.encode(attempt))
                    } else {
                        let offset = attempt.meanOffsetMilliseconds.map { "\($0)" } ?? ""
                        let values = ["\"\(attempt.exerciseID.replacingOccurrences(of: "\"", with: "\"\""))\"", "\(attempt.timestamp.timeIntervalSince1970)", "\(attempt.bpm)", "\(attempt.score)", "\(attempt.stars)", "\(attempt.perfect)", "\(attempt.good)", "\(attempt.regular)", "\(attempt.miss)", "\(attempt.extra)", offset]
                        block.append(contentsOf: (values.joined(separator: ",") + "\n").utf8)
                    }
                    count += 1
                }
                try file.write(contentsOf: block)
            }
        }
        if format == .json { try file.write(contentsOf: Data("\n]\n".utf8)) }
        try file.close()
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        } else { try manager.moveItem(at: temporary, to: destination) }
        return count
    }

    private func columnNames(in table: String) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return columns }
            guard status == SQLITE_ROW, let name = sqlite3_column_text(statement, 1) else { throw error() }
            columns.insert(String(cString: name))
        }
    }

    private func execute(_ sql: String) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return }
            guard status == SQLITE_ROW else { throw error() }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        return statement
    }

    private func error() -> ProgressStoreError {
        ProgressStoreError.sqlite(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Error de SQLite.")
    }
}

/// Reconoce las fronteras de objetos sin interpretar strings ni llaves como
/// separadores. JSONDecoder sigue validando el contenido de cada intento.
private enum ProgressJSONStream {
    static func read(_ file: FileHandle, consume: (Data) throws -> Void) throws {
        enum State { case start, value, object, separator, end }
        var state = State.start
        var object = Data()
        var depth = 0
        var inString = false
        var escaped = false
        var permitsEnd = true
        // Un intento normal máximo tiene 65.536 objetivos. El límite es por
        // objeto, nunca por historial, y evita retener un blob arbitrario.
        let maximumAttemptBytes = 64 * 1_024 * 1_024
        while let chunk = try file.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            for byte in chunk {
                let whitespace = byte == 32 || byte == 9 || byte == 10 || byte == 13
                switch state {
                case .start:
                    if whitespace { continue }
                    guard byte == 91 else { throw ProgressStoreError.invalidImportFile }
                    state = .value
                case .value:
                    if whitespace { continue }
                    if byte == 93 && permitsEnd { state = .end; continue }
                    guard byte == 123 else { throw ProgressStoreError.invalidImportFile }
                    object = Data([byte]); depth = 1; inString = false; escaped = false; state = .object
                case .object:
                    object.append(byte)
                    guard object.count <= maximumAttemptBytes else { throw ProgressStoreError.invalidImportFile }
                    if inString {
                        if escaped { escaped = false }
                        else if byte == 92 { escaped = true }
                        else if byte == 34 { inString = false }
                    } else if byte == 34 { inString = true }
                    else if byte == 123 || byte == 91 { depth += 1 }
                    else if byte == 125 || byte == 93 { depth -= 1 }
                    if depth == 0 {
                        try autoreleasepool { try consume(object) }
                        object.removeAll(keepingCapacity: false)
                        state = .separator
                    }
                case .separator:
                    if whitespace { continue }
                    if byte == 93 { state = .end }
                    else if byte == 44 { permitsEnd = false; state = .value }
                    else { throw ProgressStoreError.invalidImportFile }
                case .end:
                    guard whitespace else { throw ProgressStoreError.invalidImportFile }
                }
            }
        }
        guard case .end = state else { throw ProgressStoreError.invalidImportFile }
    }
}

private extension JSONEncoder {
    static var xroll: JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var xroll: JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
