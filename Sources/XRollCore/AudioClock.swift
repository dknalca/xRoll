import AudioToolbox
import Foundation

public enum AudioClock {
    public static func hostTime(afterMilliseconds milliseconds: Double, from now: UInt64 = AudioGetCurrentHostTime()) -> UInt64 {
        let nanoseconds = UInt64(max(0, milliseconds) * 1_000_000)
        return now + AudioConvertNanosToHostTime(nanoseconds)
    }

    public static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        guard end >= start else { return -milliseconds(from: end, to: start) }
        return Double(AudioConvertHostTimeToNanos(end - start)) / 1_000_000
    }
}
