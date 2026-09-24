import AVFoundation
import AudioToolbox
#if os(macOS)
import CoreAudio
#endif
import CoreMIDI
import Foundation

public struct MIDIEndpointDescription: Equatable {
    public let name: String
    public let uniqueID: MIDIUniqueID?
}

public enum MIDIInspector {
    public static func sources() -> [MIDIEndpointDescription] {
        var seen = Set<MIDIUniqueID>()
        return (0..<MIDIGetNumberOfSources()).compactMap { index in
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { return nil }

            // Drivers disagree on whether the useful label lives in Name or
            // DisplayName. Prefer DisplayName and always give a distinct,
            // stable fallback instead of several "sin nombre" entries.
            let displayName = stringProperty(endpoint, selector: kMIDIPropertyDisplayName)
            let endpointName = stringProperty(endpoint, selector: kMIDIPropertyName)
            var uniqueID: Int32 = 0
            let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

            // Some drivers expose a valid CoreMIDI source but omit
            // kMIDIPropertyUniqueID. Do not hide that controller from the UI:
            // the endpoint reference is stable for the current connection and
            // lets the user select and connect it after a refresh.
            let identifier: MIDIUniqueID = status == noErr ? uniqueID : Int32(bitPattern: UInt32(endpoint))
            guard seen.insert(identifier).inserted else { return nil }
            return MIDIEndpointDescription(
                name: displayName ?? endpointName ?? "Entrada MIDI \(index + 1)",
                uniqueID: identifier
            )
        }
    }

    public static func source(withUniqueID uniqueID: MIDIUniqueID) -> MIDIEndpointRef? {
        (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).first { endpoint in
            var endpointID: MIDIUniqueID = 0
            let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointID)
            return (status == noErr && endpointID == uniqueID) || (status != noErr && Int32(bitPattern: UInt32(endpoint)) == uniqueID)
        }
    }

    public static func device(named name: String) -> MIDIDeviceRef? {
        let expectedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedName.isEmpty else { return nil }
        return (0..<MIDIGetNumberOfDevices()).map(MIDIGetDevice).first { device in
            guard device != 0 else { return false }
            let names = [
                stringProperty(device, selector: kMIDIPropertyDisplayName),
                stringProperty(device, selector: kMIDIPropertyName)
            ].compactMap { $0 }
            return names.contains { $0.localizedCaseInsensitiveCompare(expectedName) == .orderedSame }
        }
    }

    private static func stringProperty(_ object: MIDIObjectRef, selector: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, selector, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

#if os(macOS)
public struct AudioOutputDescription: Equatable {
    public let deviceID: AudioDeviceID?
    public let deviceName: String?
    public let deviceUID: String?
    public let sampleRate: Double
    public let channelCount: AVAudioChannelCount
    public let bufferFrameSize: UInt32?
    public let bufferFrameRange: ClosedRange<UInt32>?
    public let outputLatency: TimeInterval
}

public struct AudioOutputDeviceDescription: Equatable, Identifiable {
    public let deviceID: AudioDeviceID
    public let name: String
    public let uid: String
    public var id: String { uid }
}

public enum AudioInspectorError: LocalizedError {
    case unavailableBufferRange
    case bufferOutsideRange(UInt32, ClosedRange<UInt32>)
    case coreAudio(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unavailableBufferRange:
            return "La salida no informa un rango de buffer configurable."
        case .bufferOutsideRange(let frames, let range):
            return "El buffer de \(frames) fotogramas queda fuera del rango \(range.lowerBound)...\(range.upperBound)."
        case .coreAudio(let status):
            return "Core Audio no pudo cambiar el buffer (\(status))."
        }
    }
}

public enum AudioInspector {
    public static func outputDevices() -> [AudioOutputDeviceDescription] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32()
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else {
            return []
        }
        return devices.compactMap { deviceID in
            guard hasOutputStreams(deviceID), let uid = deviceStringProperty(for: deviceID, selector: kAudioDevicePropertyDeviceUID) else {
                return nil
            }
            return AudioOutputDeviceDescription(
                deviceID: deviceID,
                name: deviceStringProperty(for: deviceID, selector: kAudioObjectPropertyName) ?? "Salida de audio sin nombre",
                uid: uid
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func defaultOutputDeviceID() -> AudioDeviceID? {
        defaultOutputDevice()
    }

    public static func currentOutput() -> AudioOutputDescription {
        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        let deviceID = defaultOutputDevice()
        return AudioOutputDescription(
            deviceID: deviceID,
            deviceName: deviceID.flatMap { deviceStringProperty(for: $0, selector: kAudioObjectPropertyName) },
            deviceUID: deviceID.flatMap { deviceStringProperty(for: $0, selector: kAudioDevicePropertyDeviceUID) },
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            bufferFrameSize: deviceID.flatMap(bufferFrameSize(for:)),
            bufferFrameRange: deviceID.flatMap(bufferFrameRange(for:)),
            outputLatency: engine.outputNode.presentationLatency
        )
    }

    /// Describe una salida concreta para que la calibración no dependa de cuál
    /// sea la salida predeterminada global de macOS.
    public static func output(deviceID: AudioDeviceID) -> AudioOutputDescription {
        AudioOutputDescription(
            deviceID: deviceID,
            deviceName: deviceStringProperty(for: deviceID, selector: kAudioObjectPropertyName),
            deviceUID: deviceStringProperty(for: deviceID, selector: kAudioDevicePropertyDeviceUID),
            sampleRate: nominalSampleRate(for: deviceID),
            channelCount: 0,
            bufferFrameSize: bufferFrameSize(for: deviceID),
            bufferFrameRange: bufferFrameRange(for: deviceID),
            outputLatency: 0
        )
    }

    public static func setBufferFrameSize(_ frames: UInt32, for deviceID: AudioDeviceID) throws {
        guard let range = bufferFrameRange(for: deviceID) else {
            throw AudioInspectorError.unavailableBufferRange
        }
        guard range.contains(frames) else {
            throw AudioInspectorError.bufferOutsideRange(frames, range)
        }
        var requested = frames
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &requested)
        guard status == noErr else { throw AudioInspectorError.coreAudio(status) }
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32()
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func bufferFrameSize(for deviceID: AudioDeviceID) -> UInt32? {
        var bufferFrameSize = UInt32()
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &bufferFrameSize
        )
        return status == noErr ? bufferFrameSize : nil
    }

    private static func nominalSampleRate(for deviceID: AudioDeviceID) -> Double {
        var sampleRate = Double.zero
        var size = UInt32(MemoryLayout<Double>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        return status == noErr ? sampleRate : 0
    }

    private static func bufferFrameRange(for deviceID: AudioDeviceID) -> ClosedRange<UInt32>? {
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &range
        )
        guard status == noErr, range.mMinimum >= 1, range.mMaximum >= range.mMinimum else {
            return nil
        }
        return UInt32(range.mMinimum)...UInt32(range.mMaximum)
    }

    private static func deviceStringProperty(
        for deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

/// Observa los cambios globales de dispositivos y de salida predeterminada. La
/// aplicación decide la política de fallback; Core no cambia rutas por sí solo.
public final class AudioRouteMonitor {
    private let onChange: () -> Void
    private let listener: AudioObjectPropertyListenerBlock
    private var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        listener = { _, _ in onChange() }
        let object = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListenerBlock(object, &devicesAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(object, &defaultOutputAddress, .main, listener)
    }

    deinit {
        let object = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectRemovePropertyListenerBlock(object, &devicesAddress, .main, listener)
        AudioObjectRemovePropertyListenerBlock(object, &defaultOutputAddress, .main, listener)
    }
}
#else
/// Descripción de la ruta administrada por AVAudioSession en iOS. iOS no
/// expone la selección HAL de dispositivos ni el ajuste de tamaño de buffer de
/// CoreAudio disponible en macOS.
public struct AudioOutputDescription: Equatable {
    public let sampleRate: Double
    public let channelCount: AVAudioChannelCount
    public let outputLatency: TimeInterval
}

public struct AudioOutputDeviceDescription: Equatable, Identifiable {
    public let uid: String
    public let name: String
    public var id: String { uid }
}

public enum AudioInspectorError: LocalizedError {
    case unavailableBufferRange
    case bufferOutsideRange(UInt32, ClosedRange<UInt32>)
    case coreAudio(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unavailableBufferRange:
            return "iOS administra el tamaño del buffer de audio."
        case .bufferOutsideRange(let frames, let range):
            return "El buffer de \(frames) fotogramas queda fuera del rango \(range.lowerBound)...\(range.upperBound)."
        case .coreAudio(let status):
            return "No se pudo configurar el audio (\(status))."
        }
    }
}

public enum AudioInspector {
    /// En iOS la ruta la elige el sistema; no hay selector de AudioDeviceID.
    public static func outputDevices() -> [AudioOutputDeviceDescription] { [] }
    public static func defaultOutputDeviceID() -> UInt32? { nil }

    public static func currentOutput() -> AudioOutputDescription {
        let session = AVAudioSession.sharedInstance()
        return AudioOutputDescription(
            sampleRate: session.sampleRate,
            channelCount: AVAudioChannelCount(session.outputNumberOfChannels),
            outputLatency: session.outputLatency
        )
    }

    public static func setBufferFrameSize(_ frames: UInt32, for deviceID: UInt32) throws {
        throw AudioInspectorError.unavailableBufferRange
    }
}

/// Informa cambios de ruta sin consultar CoreAudio HAL.
public final class AudioRouteMonitor {
    private var observer: NSObjectProtocol?

    public init(onChange: @escaping () -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { _ in onChange() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
#endif
