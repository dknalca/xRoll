import Foundation

public final class PracticeSession {
    public let timeline: ExerciseTimeline
    public let bpm: Int
    public let grid: Int
    public let calibrationOffsetMilliseconds: Double
    public private(set) var hits: [TimedPadHit] = []

    public init(exercise: Exercise, calibrationOffsetMilliseconds: Double = 0) {
        timeline = ExerciseTimeline(exercise: exercise)
        bpm = exercise.bpm
        grid = exercise.grid
        self.calibrationOffsetMilliseconds = calibrationOffsetMilliseconds
    }

    @discardableResult
    public func register(_ hit: TimedPadHit) -> ScoredPadHit {
        hits.append(hit)
        return score.hits.last ?? ScoredPadHit(hit: hit, expectedNote: nil, judgement: .extra, offsetMilliseconds: nil)
    }

    public var score: ExerciseScore {
        RhythmScorer.score(
            timeline: timeline,
            bpm: bpm,
            grid: grid,
            hits: hits,
            calibrationOffsetMilliseconds: calibrationOffsetMilliseconds
        )
    }
}
