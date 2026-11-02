import Foundation

public struct PracticeSessionRegistration {
    public let scoredHit: ScoredPadHit
    public let expiredMisses: [ScheduledExerciseNote]
}

public final class PracticeSession {
    public let timeline: ExerciseTimeline
    public let bpm: Int
    public let grid: Int
    public let calibrationOffsetMilliseconds: Double
    public let scoringWindows: ScoringWindows?
    private let scorer: IncrementalRhythmScorer

    public var hits: [TimedPadHit] { scorer.hits }

    public init(exercise: Exercise, calibrationOffsetMilliseconds: Double = 0, scoringWindows: ScoringWindows? = nil) {
        let timeline = ExerciseTimeline(exercise: exercise)
        self.timeline = timeline
        bpm = exercise.bpm
        grid = exercise.grid
        self.calibrationOffsetMilliseconds = calibrationOffsetMilliseconds
        self.scoringWindows = scoringWindows
        scorer = IncrementalRhythmScorer(
            timeline: timeline,
            bpm: exercise.bpm,
            grid: exercise.grid,
            calibrationOffsetMilliseconds: calibrationOffsetMilliseconds,
            scoringWindows: scoringWindows
        )
    }

    @discardableResult
    public func register(_ hit: TimedPadHit) -> ScoredPadHit {
        registerWithMisses(hit).scoredHit
    }

    public func registerWithMisses(_ hit: TimedPadHit) -> PracticeSessionRegistration {
        let scoredHit = scorer.register(hit)
        return PracticeSessionRegistration(scoredHit: scoredHit, expiredMisses: scorer.takeNewlyExpiredMisses())
    }

    /// Descarta los golpes de la cuenta de entrada que quedan fuera de la
    /// ventana anticipada del primer pulso. Se siguen reproduciendo en vivo;
    /// sencillamente no forman parte del intento puntuable.
    @discardableResult
    public func registerIfScorable(_ hit: TimedPadHit) -> ScoredPadHit? {
        registerIfScorableWithMisses(hit)?.scoredHit
    }

    public func registerIfScorableWithMisses(_ hit: TimedPadHit) -> PracticeSessionRegistration? {
        let regularWindow = scoringWindows?.regularMilliseconds
            ?? ScoringWindows(bpm: bpm, grid: grid).regularMilliseconds
        guard hit.timeMilliseconds - calibrationOffsetMilliseconds >= -regularWindow else { return nil }
        return registerWithMisses(hit)
    }

    public var score: ExerciseScore {
        scorer.score
    }
}
