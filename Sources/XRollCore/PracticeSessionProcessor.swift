import Foundation

public struct PracticeSessionProcessingResult {
    public let scoredHit: ScoredPadHit?
    public let startedHostTime: UInt64
    public let completedHostTime: UInt64
}

/// Serializa las mutaciones de una sesión fuera de la interfaz. La cola también
/// actúa como barrera al cerrar una generación: termina los golpes admitidos
/// antes de entregar el score final y rechaza eventos posteriores.
public final class PracticeSessionProcessor {
    private let queue = DispatchQueue(label: "xRoll.practice-session", qos: .userInitiated)
    private var generation: UUID?
    private var session: PracticeSession?

    public init() {}

    /// Se encola en la misma cola que los golpes; así `begin` no bloquea el
    /// cerrojo de admisión mientras termina un callback de la sesión anterior.
    public func begin(_ session: PracticeSession, generation: UUID) {
        queue.async { [weak self] in
            self?.generation = generation
            self?.session = session
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
            let scoredHit = session.registerIfScorable(hit)
            completion(.init(
                scoredHit: scoredHit,
                startedHostTime: startedHostTime,
                completedHostTime: AudioClock.currentHostTime()
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

    public init() {}

    public func begin(_ session: PracticeSession, generation: UUID) {
        lock.lock()
        processor.begin(session, generation: generation)
        self.generation = generation
        lock.unlock()
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
