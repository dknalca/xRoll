import Foundation

public struct PracticeSessionProcessingResult {
    public let scoredHit: ScoredPadHit?
    public let expiredMisses: [ScheduledExerciseNote]
    public let startedHostTime: UInt64
    public let completedHostTime: UInt64
    public let calibrationAssociation: CalibrationHitAssociation?
}

/// Serializa las mutaciones de una sesión fuera de la interfaz. La cola también
/// actúa como barrera al cerrar una generación: termina los golpes admitidos
/// antes de entregar el score final y rechaza eventos posteriores.
public final class PracticeSessionProcessor {
    private let queue = DispatchQueue(label: "xRoll.practice-session", qos: .userInitiated)
    private var generation: UUID?
    private var session: PracticeSession?
    private var calibrationMatchers = [String: CalibrationMatcher]()
    private var isCalibrating = false

    public init() {}

    /// Se encola en la misma cola que los golpes; así `begin` no bloquea el
    /// cerrojo de admisión mientras termina un callback de la sesión anterior.
    public func begin(_ session: PracticeSession, generation: UUID, calibration: Bool = false) {
        queue.async { [weak self] in
            self?.generation = generation
            self?.session = session
            self?.isCalibrating = calibration
            self?.calibrationMatchers = calibration
                ? Dictionary(grouping: session.timeline.notes, by: \.sound).mapValues {
                    CalibrationMatcher(targetTimesMilliseconds: $0.map(\.timeMilliseconds))
                } : [:]
        }
    }

    /// `completion` se ejecuta en la cola del procesador. Debe limitarse a
    /// publicar el resultado; la interfaz se actualiza en el hilo principal.
    public func register(
        _ hit: TimedPadHit,
        generation requestedGeneration: UUID,
        completion: @escaping (PracticeSessionProcessingResult) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  self.generation == requestedGeneration,
                  let session = self.session else { return }
            let startedHostTime = AudioClock.currentHostTime()
            let calibrationAssociation = self.calibrationMatchers[hit.sound]?.associateHit(atMilliseconds: hit.timeMilliseconds)
            let registration = self.isCalibrating ? nil : session.registerIfScorableWithMisses(hit)
            completion(.init(
                scoredHit: registration?.scoredHit,
                expiredMisses: registration?.expiredMisses ?? [],
                startedHostTime: startedHostTime,
                completedHostTime: AudioClock.currentHostTime(),
                calibrationAssociation: calibrationAssociation
            ))
        }
    }

    /// Cierra tras todos los registros encolados anteriormente y devuelve un
    /// score estable. Los siguientes eventos de esa generación se ignoran.
    public func finish(
        generation requestedGeneration: UUID,
        completion: @escaping (ExerciseScore?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, self.generation == requestedGeneration else {
                completion(nil)
                return
            }
            let score = self.session?.score
            self.session = nil
            self.generation = nil
            self.calibrationMatchers.removeAll()
            completion(score)
        }
    }

    public func cancel(generation requestedGeneration: UUID, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, self.generation == requestedGeneration else {
                completion?()
                return
            }
            self.session = nil
            self.generation = nil
            self.calibrationMatchers.removeAll()
            completion?()
        }
    }
}

/// Puerta de admisión para la entrada de práctica. Serializa la operación que
/// encola un golpe con la que cierra la sesión, evitando perder un evento que ya
/// había sido aceptado justo antes de finalizar.
public final class PracticeSessionIngress {
    private let lock = NSLock()
    private let processor = PracticeSessionProcessor()
    private var generation: UUID?
    private var startHostTime: UInt64 = 0
    private var admissionHostTime: UInt64 = 0

    public init() {}

    public func begin(_ session: PracticeSession, generation: UUID, startHostTime: UInt64 = 0, admissionHostTime: UInt64 = AudioClock.currentHostTime(), calibration: Bool = false) {
        lock.lock()
        processor.begin(session, generation: generation, calibration: calibration)
        self.startHostTime = startHostTime
        self.admissionHostTime = admissionHostTime
        self.generation = generation
        lock.unlock()
    }

    /// Convierte el reloj y admite el golpe bajo el mismo cerrojo que cambia la
    /// generación. Un evento anterior al arranque no puede entrar en el reinicio.
    @discardableResult
    public func submit(sound: String, hostTime: UInt64, role: String? = nil, padID: String? = nil, velocity: UInt8? = nil,
                       completion: @escaping (UUID, PracticeSessionProcessingResult) -> Void) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard let generation, hostTime >= admissionHostTime else { return nil }
        let hit = TimedPadHit(sound: sound, hostTime: hostTime, practiceStartHostTime: startHostTime,
                              role: role, padID: padID, velocity: velocity)
        processor.register(hit, generation: generation) { result in completion(generation, result) }
        return generation
    }

    @discardableResult
    public func submit(
        _ hit: TimedPadHit,
        completion: @escaping (UUID, PracticeSessionProcessingResult) -> Void
    ) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard let generation else { return nil }
        processor.register(hit, generation: generation) { result in completion(generation, result) }
        return generation
    }

    public func finish(completion: @escaping (UUID, ExerciseScore?) -> Void) {
        lock.lock()
        guard let generation else {
            lock.unlock()
            return
        }
        self.generation = nil
        processor.finish(generation: generation) { score in completion(generation, score) }
        lock.unlock()
    }

    public func cancel(completion: @escaping (UUID) -> Void) {
        lock.lock()
        guard let generation else {
            lock.unlock()
            return
        }
        self.generation = nil
        processor.cancel(generation: generation) { completion(generation) }
        lock.unlock()
    }
}
