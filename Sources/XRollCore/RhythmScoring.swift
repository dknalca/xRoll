import Foundation

public struct ScheduledExerciseNote: Equatable {
    public let index: Int
    public let sound: String
    public let hand: String?
    public let timeMilliseconds: Double
}

public struct ExerciseTimeline: Equatable {
    public let stepDurationMilliseconds: Double
    public let patternDurationMilliseconds: Double
    public let notes: [ScheduledExerciseNote]

    public init(exercise: Exercise) {
        stepDurationMilliseconds = 60_000 / Double(exercise.bpm) * 4 / Double(exercise.grid)
        patternDurationMilliseconds = stepDurationMilliseconds * Double(exercise.bars * exercise.grid)

        var scheduled: [ScheduledExerciseNote] = []
        let totalSteps = exercise.bars * exercise.grid
        for repeatIndex in 0..<exercise.repeats {
            for (noteIndex, note) in exercise.notes.enumerated() {
                let shiftedStep = (note.step + exercise.offset) % totalSteps
                scheduled.append(ScheduledExerciseNote(
                    index: repeatIndex * exercise.notes.count + noteIndex,
                    sound: note.sound,
                    hand: note.hand,
                    timeMilliseconds: Double(repeatIndex) * patternDurationMilliseconds + Double(shiftedStep) * stepDurationMilliseconds
                ))
            }
        }
        notes = scheduled.sorted {
            if $0.timeMilliseconds == $1.timeMilliseconds { return $0.index < $1.index }
            return $0.timeMilliseconds < $1.timeMilliseconds
        }
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

public enum RhythmJudgement: String, Equatable {
    case perfect
    case good
    case regular
    case miss
    case extra

    public var value: Double {
        switch self {
        case .perfect: return 1
        case .good: return 0.7
        case .regular: return 0.4
        case .miss, .extra: return 0
        }
    }
}

public struct TimedPadHit: Equatable {
    public let sound: String
    public let timeMilliseconds: Double

    public init(sound: String, timeMilliseconds: Double) {
        self.sound = sound
        self.timeMilliseconds = timeMilliseconds
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

public enum RhythmScorer {
    public static func score(
        timeline: ExerciseTimeline,
        bpm: Int,
        grid: Int,
        hits: [TimedPadHit],
        calibrationOffsetMilliseconds: Double = 0,
        scoringWindows: ScoringWindows? = nil
    ) -> ExerciseScore {
        let windows = scoringWindows ?? ScoringWindows(bpm: bpm, grid: grid)
        var pending = Set(timeline.notes.map(\.index))
        var results: [ScoredPadHit] = []

        for hit in hits.sorted(by: { $0.timeMilliseconds < $1.timeMilliseconds }) {
            let candidates = timeline.notes.filter { note in
                guard pending.contains(note.index), note.sound == hit.sound else { return false }
                let scoredOffset = hit.timeMilliseconds - note.timeMilliseconds - calibrationOffsetMilliseconds
                return abs(scoredOffset) <= windows.regularMilliseconds
            }
            let expected = candidates.min { left, right in
                let leftDistance = abs(hit.timeMilliseconds - left.timeMilliseconds - calibrationOffsetMilliseconds)
                let rightDistance = abs(hit.timeMilliseconds - right.timeMilliseconds - calibrationOffsetMilliseconds)
                return leftDistance == rightDistance ? left.timeMilliseconds < right.timeMilliseconds : leftDistance < rightDistance
            }

            guard let expected else {
                results.append(.init(hit: hit, expectedNote: nil, judgement: .extra, offsetMilliseconds: nil))
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
            results.append(.init(hit: hit, expectedNote: expected, judgement: judgement, offsetMilliseconds: offset))
        }

        let misses = timeline.notes.filter { pending.contains($0.index) }
        let earned = results.reduce(0) { $0 + $1.judgement.value }
        let penalty = Double(results.filter { $0.judgement == .extra }.count) * 0.5
        let possible = Double(timeline.notes.count)
        let percentage = possible == 0 ? 0 : min(100, max(0, (earned - penalty) / possible * 100))
        let offsets = results.compactMap(\.offsetMilliseconds)
        let meanOffset = offsets.isEmpty ? nil : offsets.reduce(0, +) / Double(offsets.count)
        let stars = percentage >= 90 ? 3 : percentage >= 75 ? 2 : percentage >= 50 ? 1 : 0
        return ExerciseScore(
            hits: results,
            misses: misses,
            percentage: percentage,
            stars: stars,
            meanOffsetMilliseconds: meanOffset
        )
    }
}
