import Foundation

public struct ScheduledExerciseNote: Equatable {
    public let index: Int
    public let step: Int
    public let sound: String
    public let hand: String?
    public let target: Exercise.Target?
    public let velocity: Int?
    public let timeMilliseconds: Double
}

public struct ExerciseTimeline: Equatable {
    public let stepDurationMilliseconds: Double
    /// Duración de un compás. La escena usa este valor para mostrar una sola
    /// rejilla legible aunque una frase MIDI tenga varios compases.
    public let barDurationMilliseconds: Double
    public let patternDurationMilliseconds: Double
    public let bars: Int
    public let notes: [ScheduledExerciseNote]

    public init(exercise: Exercise) {
        stepDurationMilliseconds = 60_000 / Double(exercise.bpm) * 4 / Double(exercise.grid)
        barDurationMilliseconds = stepDurationMilliseconds * Double(exercise.grid)
        patternDurationMilliseconds = stepDurationMilliseconds * Double(exercise.bars * exercise.grid)
        bars = exercise.bars

        var scheduled: [ScheduledExerciseNote] = []
        let totalSteps = exercise.bars * exercise.grid
        for repeatIndex in 0..<exercise.repeats {
            for (noteIndex, note) in exercise.notes.enumerated() {
                let shiftedStep = (note.step + exercise.offset) % totalSteps
                scheduled.append(ScheduledExerciseNote(
                    index: repeatIndex * exercise.notes.count + noteIndex,
                    step: shiftedStep,
                    sound: note.sound,
                    hand: note.hand,
                    target: note.target,
                    velocity: note.velocity,
                    timeMilliseconds: Double(repeatIndex) * patternDurationMilliseconds + Double(shiftedStep) * stepDurationMilliseconds
                ))
            }
        }
        notes = scheduled.sorted {
            if $0.timeMilliseconds == $1.timeMilliseconds { return $0.index < $1.index }
            return $0.timeMilliseconds < $1.timeMilliseconds
        }
    }

    /// Devuelve posiciones contiguas de la línea temporal sin recorrer notas
    /// que quedan fuera de la ventana solicitada.
    public func noteRange(from startMilliseconds: Double, through endMilliseconds: Double) -> Range<Int> {
        guard startMilliseconds <= endMilliseconds, !notes.isEmpty else { return 0..<0 }
        var lower = 0
        var upper = notes.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if notes[middle].timeMilliseconds < startMilliseconds { lower = middle + 1 }
            else { upper = middle }
        }
        let start = lower
        upper = notes.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if notes[middle].timeMilliseconds <= endMilliseconds { lower = middle + 1 }
            else { upper = middle }
        }
        return start..<lower
    }
}

public struct ScoringWindows: Equatable {
    public let perfectMilliseconds: Double
    public let goodMilliseconds: Double
    public let regularMilliseconds: Double

    public init(bpm: Int, grid: Int) {
        let subdivision = 60_000 / Double(bpm) * 4 / Double(grid)
        regularMilliseconds = min(95, subdivision * 0.45)
        goodMilliseconds = min(65, regularMilliseconds)
        perfectMilliseconds = min(35, goodMilliseconds)
    }

    public init(perfectMilliseconds: Double, goodMilliseconds: Double, regularMilliseconds: Double) {
        let perfect = max(0, perfectMilliseconds)
        let good = max(perfect, goodMilliseconds)
        let regular = max(good, regularMilliseconds)
        self.perfectMilliseconds = perfect
        self.goodMilliseconds = good
        self.regularMilliseconds = regular
    }
}

public enum RhythmJudgement: String, Codable, Equatable {
    case perfect
    case good
    case regular
    case miss
    case extra

    public var value: Double {
        switch self {
        case .perfect: return 1
        // A regular hit is still a correctly placed hit. It should encourage a
        // beginner to improve timing, not make a mostly correct pattern feel
        // like a failure.
        case .good: return 0.85
        case .regular: return 0.7
        case .miss, .extra: return 0
        }
    }
}

/// Evento inmutable persistido para reconstruir una sesión sin depender de la UI.
/// Un registro `.miss` no tiene ejecución; uno `.extra` no tiene objetivo.
public struct HitRecord: Codable, Equatable {
    public let sequence: Int
    public let judgement: RhythmJudgement
    public let expectedSound: String?
    public let expectedStep: Int?
    public let expectedTimeMilliseconds: Double?
    public let expectedVelocity: Int?
    public let hand: String?
    public let target: Exercise.Target?
    public let actualSound: String?
    public let actualTimeMilliseconds: Double?
    public let actualVelocity: Int?
    public let role: String?
    public let padID: String?
    public let offsetMilliseconds: Double?

    public static func records(from score: ExerciseScore) -> [HitRecord] {
        var result = score.hits.enumerated().map { sequence, scored in
            HitRecord(sequence: sequence, judgement: scored.judgement,
                      expectedSound: scored.expectedNote?.sound, expectedStep: scored.expectedNote?.step,
                      expectedTimeMilliseconds: scored.expectedNote?.timeMilliseconds,
                      expectedVelocity: scored.expectedNote?.velocity, hand: scored.expectedNote?.hand, target: scored.expectedNote?.target,
                      actualSound: scored.hit.sound, actualTimeMilliseconds: scored.hit.timeMilliseconds,
                      actualVelocity: scored.hit.velocity.map(Int.init), role: scored.hit.role,
                      padID: scored.hit.padID, offsetMilliseconds: scored.offsetMilliseconds)
        }
        let base = result.count
        result += score.misses.enumerated().map { offset, note in
            HitRecord(sequence: base + offset, judgement: .miss, expectedSound: note.sound,
                      expectedStep: note.step, expectedTimeMilliseconds: note.timeMilliseconds,
                      expectedVelocity: note.velocity, hand: note.hand, target: note.target,
                      actualSound: nil, actualTimeMilliseconds: nil, actualVelocity: nil,
                      role: nil, padID: nil, offsetMilliseconds: nil)
        }
        return result.sorted {
            let lhs = $0.actualTimeMilliseconds ?? $0.expectedTimeMilliseconds ?? .greatestFiniteMagnitude
            let rhs = $1.actualTimeMilliseconds ?? $1.expectedTimeMilliseconds ?? .greatestFiniteMagnitude
            return lhs == rhs ? $0.sequence < $1.sequence : lhs < rhs
        }.enumerated().map { index, item in
            HitRecord(sequence: index, judgement: item.judgement, expectedSound: item.expectedSound, expectedStep: item.expectedStep, expectedTimeMilliseconds: item.expectedTimeMilliseconds, expectedVelocity: item.expectedVelocity, hand: item.hand, target: item.target, actualSound: item.actualSound, actualTimeMilliseconds: item.actualTimeMilliseconds, actualVelocity: item.actualVelocity, role: item.role, padID: item.padID, offsetMilliseconds: item.offsetMilliseconds)
        }
    }
}

public struct TimedPadHit: Equatable {
    public let sound: String
    public let timeMilliseconds: Double
    public let role: String?
    public let padID: String?
    public let velocity: UInt8?

    public init(sound: String, timeMilliseconds: Double, role: String? = nil, padID: String? = nil, velocity: UInt8? = nil) {
        self.sound = sound; self.timeMilliseconds = timeMilliseconds; self.role = role; self.padID = padID; self.velocity = velocity
    }

    /// Conserva el instante entregado por CoreMIDI. La cola de interfaz nunca
    /// participa en el cálculo temporal de una sesión.
    public init(sound: String, hostTime: UInt64, practiceStartHostTime: UInt64, role: String? = nil, padID: String? = nil, velocity: UInt8? = nil) {
        self.init(
            sound: sound,
            timeMilliseconds: AudioClock.milliseconds(from: practiceStartHostTime, to: hostTime),
            role: role,
            padID: padID,
            velocity: velocity
        )
    }
}

public struct ScoredPadHit: Equatable {
    public let hit: TimedPadHit
    public let expectedNote: ScheduledExerciseNote?
    public let judgement: RhythmJudgement
    public let offsetMilliseconds: Double?
}

public struct ExerciseScore: Equatable {
    public let hits: [ScoredPadHit]
    public let misses: [ScheduledExerciseNote]
    public let percentage: Double
    public let stars: Int
    public let meanOffsetMilliseconds: Double?

    public var perfectCount: Int { hits.filter { $0.judgement == .perfect }.count }
    public var goodCount: Int { hits.filter { $0.judgement == .good }.count }
    public var regularCount: Int { hits.filter { $0.judgement == .regular }.count }
    public var extraCount: Int { hits.filter { $0.judgement == .extra }.count }
}

/// Puntúa en tiempo constante respecto al historial para entradas cronológicas.
/// Si llega un hostTime anterior, usa el scorer de referencia para mantener la
/// semántica batch y recuperar las asociaciones deterministas.
final class IncrementalRhythmScorer {
    private let timeline: ExerciseTimeline
    private let bpm: Int
    private let grid: Int
    private let windows: ScoringWindows
    private let calibrationOffsetMilliseconds: Double
    private let notesBySound: [String: [ScheduledExerciseNote]]
    private var consumedNoteIndices = Set<Int>()
    private var indexedResults = [(inputIndex: Int, result: ScoredPadHit)]()
    private var inputHits = [TimedPadHit]()
    private var latestInputTimeMilliseconds: Double?
    private var nextMissDeadlineIndex = 0
    private var newlyExpiredMisses = [ScheduledExerciseNote]()

    init(timeline: ExerciseTimeline, bpm: Int, grid: Int, calibrationOffsetMilliseconds: Double, scoringWindows: ScoringWindows?) {
        self.timeline = timeline
        self.bpm = bpm
        self.grid = grid
        windows = scoringWindows ?? ScoringWindows(bpm: bpm, grid: grid)
        self.calibrationOffsetMilliseconds = calibrationOffsetMilliseconds
        notesBySound = Dictionary(grouping: timeline.notes, by: \.sound)
        consumedNoteIndices.reserveCapacity(timeline.notes.count)
        indexedResults.reserveCapacity(timeline.notes.count)
        inputHits.reserveCapacity(timeline.notes.count)
    }

    var hits: [TimedPadHit] { inputHits }

    func register(_ hit: TimedPadHit) -> ScoredPadHit {
        let inputIndex = inputHits.count
        inputHits.append(hit)
        if let latestInputTimeMilliseconds, hit.timeMilliseconds < latestInputTimeMilliseconds {
            return rescoreAndReturnLatestHit(hit, inputIndex: inputIndex)
        }
        latestInputTimeMilliseconds = hit.timeMilliseconds

        let result = scoreChronologicalHit(hit)
        indexedResults.append((inputIndex, result))
        if let noteIndex = result.expectedNote?.index { consumedNoteIndices.insert(noteIndex) }
        collectMissesExpired(by: hit.timeMilliseconds)
        return result
    }

    func takeNewlyExpiredMisses() -> [ScheduledExerciseNote] {
        let misses = newlyExpiredMisses
        newlyExpiredMisses.removeAll(keepingCapacity: true)
        return misses
    }

    private func collectMissesExpired(by timeMilliseconds: Double) {
        while nextMissDeadlineIndex < timeline.notes.count {
            let note = timeline.notes[nextMissDeadlineIndex]
            let deadline = note.timeMilliseconds + calibrationOffsetMilliseconds + windows.regularMilliseconds
            // La ventana incluye el límite superior; la nota falla solo después.
            guard deadline < timeMilliseconds else { break }
            if !consumedNoteIndices.contains(note.index) {
                newlyExpiredMisses.append(note)
            }
            nextMissDeadlineIndex += 1
        }
    }

    var score: ExerciseScore {
        let orderedResults = indexedResults.sorted {
            let leftTime = $0.result.hit.timeMilliseconds
            let rightTime = $1.result.hit.timeMilliseconds
            return leftTime == rightTime ? $0.inputIndex < $1.inputIndex : leftTime < rightTime
        }.map(\.result)
        let misses = timeline.notes.filter { !consumedNoteIndices.contains($0.index) }
        return RhythmScorer.makeScore(timeline: timeline, results: orderedResults, misses: misses)
    }

    private func rescoreAndReturnLatestHit(_ hit: TimedPadHit, inputIndex: Int) -> ScoredPadHit {
        let (_, indexed) = RhythmScorer.scoreIndexed(
            timeline: timeline,
            bpm: bpm,
            grid: grid,
            hits: inputHits,
            calibrationOffsetMilliseconds: calibrationOffsetMilliseconds,
            scoringWindows: windows
        )
        indexedResults = indexed.map { (inputIndex: $0.0, result: $0.1) }
        consumedNoteIndices = Set(indexed.compactMap { $0.1.expectedNote?.index })
        return indexed.first(where: { $0.0 == inputIndex })?.1
            ?? ScoredPadHit(hit: hit, expectedNote: nil, judgement: .extra, offsetMilliseconds: nil)
    }

    private func scoreChronologicalHit(_ hit: TimedPadHit) -> ScoredPadHit {
        guard let notes = notesBySound[hit.sound], !notes.isEmpty else {
            return .init(hit: hit, expectedNote: nil, judgement: .extra, offsetMilliseconds: nil)
        }

        let targetTime = hit.timeMilliseconds - calibrationOffsetMilliseconds
        let lowerBound = targetTime - windows.regularMilliseconds
        let upperBound = targetTime + windows.regularMilliseconds
        var low = 0
        var high = notes.count
        while low < high {
            let middle = (low + high) / 2
            if notes[middle].timeMilliseconds < lowerBound { low = middle + 1 }
            else { high = middle }
        }

        var expected: ScheduledExerciseNote?
        var expectedDistance = Double.greatestFiniteMagnitude
        for note in notes[low...] {
            guard note.timeMilliseconds <= upperBound else { break }
            guard !consumedNoteIndices.contains(note.index), RhythmScorer.targetMatches(note.target, hit: hit) else { continue }
            let distance = abs(targetTime - note.timeMilliseconds)
            if distance < expectedDistance || (distance == expectedDistance && note.timeMilliseconds < (expected?.timeMilliseconds ?? .greatestFiniteMagnitude)) {
                expected = note
                expectedDistance = distance
            }
        }

        guard let expected else {
            return .init(hit: hit, expectedNote: nil, judgement: .extra, offsetMilliseconds: nil)
        }
        let offset = hit.timeMilliseconds - expected.timeMilliseconds - calibrationOffsetMilliseconds
        let distance = abs(offset)
        let judgement: RhythmJudgement
        if distance <= windows.perfectMilliseconds { judgement = .perfect }
        else if distance <= windows.goodMilliseconds { judgement = .good }
        else { judgement = .regular }
        return .init(hit: hit, expectedNote: expected, judgement: judgement, offsetMilliseconds: offset)
    }
}

public enum RhythmScorer {
    public static func score(
        timeline: ExerciseTimeline,
        bpm: Int,
        grid: Int,
        hits: [TimedPadHit],
        calibrationOffsetMilliseconds: Double = 0,
        scoringWindows: ScoringWindows? = nil
    ) -> ExerciseScore {
        scoreIndexed(
            timeline: timeline,
            bpm: bpm,
            grid: grid,
            hits: hits,
            calibrationOffsetMilliseconds: calibrationOffsetMilliseconds,
            scoringWindows: scoringWindows
        ).0
    }

    static func scoreIndexed(
        timeline: ExerciseTimeline,
        bpm: Int,
        grid: Int,
        hits: [TimedPadHit],
        calibrationOffsetMilliseconds: Double = 0,
        scoringWindows: ScoringWindows? = nil
    ) -> (ExerciseScore, [(Int, ScoredPadHit)]) {
        let windows = scoringWindows ?? ScoringWindows(bpm: bpm, grid: grid)
        var pending = Set(timeline.notes.map(\.index))
        var indexedResults = [(Int, ScoredPadHit)]()

        let orderedHits = hits.enumerated().sorted {
            $0.element.timeMilliseconds == $1.element.timeMilliseconds
                ? $0.offset < $1.offset
                : $0.element.timeMilliseconds < $1.element.timeMilliseconds
        }
        for (inputIndex, hit) in orderedHits.map({ ($0.offset, $0.element) }) {
            let candidates = timeline.notes.filter { note in
                guard pending.contains(note.index), note.sound == hit.sound, targetMatches(note.target, hit: hit) else { return false }
                let scoredOffset = hit.timeMilliseconds - note.timeMilliseconds - calibrationOffsetMilliseconds
                return abs(scoredOffset) <= windows.regularMilliseconds
            }
            let expected = candidates.min { left, right in
                let leftDistance = abs(hit.timeMilliseconds - left.timeMilliseconds - calibrationOffsetMilliseconds)
                let rightDistance = abs(hit.timeMilliseconds - right.timeMilliseconds - calibrationOffsetMilliseconds)
                return leftDistance == rightDistance ? left.timeMilliseconds < right.timeMilliseconds : leftDistance < rightDistance
            }

            guard let expected else {
                indexedResults.append((inputIndex, .init(hit: hit, expectedNote: nil, judgement: .extra, offsetMilliseconds: nil)))
                continue
            }
            pending.remove(expected.index)
            let offset = hit.timeMilliseconds - expected.timeMilliseconds - calibrationOffsetMilliseconds
            let distance = abs(offset)
            let judgement: RhythmJudgement
            if distance <= windows.perfectMilliseconds {
                judgement = .perfect
            } else if distance <= windows.goodMilliseconds {
                judgement = .good
            } else {
                judgement = .regular
            }
            indexedResults.append((inputIndex, .init(hit: hit, expectedNote: expected, judgement: judgement, offsetMilliseconds: offset)))
        }

        let misses = timeline.notes.filter { pending.contains($0.index) }
        let result = indexedResults.sorted {
            $0.1.hit.timeMilliseconds == $1.1.hit.timeMilliseconds
                ? $0.0 < $1.0
                : $0.1.hit.timeMilliseconds < $1.1.hit.timeMilliseconds
        }.map(\.1)
        return (makeScore(timeline: timeline, results: result, misses: misses), indexedResults)
    }

    static func makeScore(timeline: ExerciseTimeline, results: [ScoredPadHit], misses: [ScheduledExerciseNote]) -> ExerciseScore {
        let earned = results.reduce(0) { $0 + $1.judgement.value }
        // Extras must matter, but a single accidental tap should not outweigh
        // the credit earned by a valid, if loose, hit.
        let penalty = Double(results.filter { $0.judgement == .extra }.count) * 0.25
        let possible = Double(timeline.notes.count)
        let percentage = possible == 0 ? 0 : min(100, max(0, (earned - penalty) / possible * 100))
        let offsets = results.compactMap(\.offsetMilliseconds)
        let meanOffset = offsets.isEmpty ? nil : offsets.reduce(0, +) / Double(offsets.count)
        let stars = percentage >= 90 ? 3 : percentage >= 80 ? 2 : percentage >= 70 ? 1 : 0
        return ExerciseScore(
            hits: results,
            misses: misses,
            percentage: percentage,
            stars: stars,
            meanOffsetMilliseconds: meanOffset
        )
    }

    static func targetMatches(_ target: Exercise.Target?, hit: TimedPadHit) -> Bool {
        guard let target else { return true }
        switch target.type { case .any: return true; case .role: return target.value == hit.role; case .pad: return target.value == hit.padID }
    }
}
