import Foundation

/// Convierte la velocidad MIDI (1...127) en una ganancia musical. Se conserva
/// un mínimo audible para que un golpe suave no parezca una nota perdida.
public enum VelocityCurve {
    public static func gain(for velocity: UInt8) -> Float {
        let normalized = min(1, max(0, Double(velocity) / 127))
        return Float(0.15 + 0.85 * pow(normalized, 0.65))
    }
}
