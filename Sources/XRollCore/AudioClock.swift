import AudioToolbox
import Darwin
import Foundation

public enum AudioClock {
    private static let machTimebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Mach host time conserva la misma base que los timestamps de CoreMIDI y
    /// está disponible tanto en iOS como en macOS. En macOS equivale al reloj
    /// devuelto por AudioGetCurrentHostTime.
    public static func currentHostTime() -> UInt64 {
        mach_absolute_time()
    }

    public static func hostTime(afterMilliseconds milliseconds: Double, from now: UInt64 = currentHostTime()) -> UInt64 {
        let nanoseconds = UInt64(max(0, milliseconds) * 1_000_000)
        return now + hostTicks(fromNanoseconds: nanoseconds)
    }

    /// Aplica un delta de nanosegundos a un hostTime sin cambiar su época.
    public static func hostTime(offsetByNanoseconds offset: Int64, from hostTime: UInt64) -> UInt64 {
        let ticks = hostTicks(fromNanoseconds: offset.magnitude)
        return offset >= 0 ? hostTime &+ ticks : hostTime &- ticks
    }

    public static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        guard end >= start else { return -milliseconds(from: end, to: start) }
        return Double(nanoseconds(fromHostTicks: end - start)) / 1_000_000
    }

    private static func hostTicks(fromNanoseconds nanoseconds: UInt64) -> UInt64 {
        #if os(macOS)
        return AudioConvertNanosToHostTime(nanoseconds)
        #else
        let ticks = Double(nanoseconds) * Double(machTimebase.denom) / Double(machTimebase.numer)
        return UInt64(max(0, ticks.rounded()))
        #endif
    }

    private static func nanoseconds(fromHostTicks ticks: UInt64) -> UInt64 {
        #if os(macOS)
        return AudioConvertHostTimeToNanos(ticks)
        #else
        let nanoseconds = Double(ticks) * Double(machTimebase.numer) / Double(machTimebase.denom)
        return UInt64(max(0, nanoseconds.rounded()))
        #endif
    }
}
