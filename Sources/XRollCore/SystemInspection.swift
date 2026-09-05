import AVFoundation
import CoreAudio
import CoreMIDI
import Foundation

public struct MIDIEndpointDescription: Equatable {
    public let name: String
    public let uniqueID: MIDIUniqueID?
}

public enum MIDIInspector {
    public static func sources() -> [MIDIEndpointDescription] {
        (0..<MIDIGetNumberOfSources()).compactMap { index in
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { return nil }

            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            var uniqueID: Int32 = 0
            let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

            return MIDIEndpointDescription(
                name: name?.takeRetainedValue() as String? ?? "Dispositivo MIDI sin nombre",
                uniqueID: status == noErr ? uniqueID : nil
            )
        }
    }

    public static func source(withUniqueID uniqueID: MIDIUniqueID) -> MIDIEndpointRef? {
        (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).first { endpoint in
            var endpointID: MIDIUniqueID = 0
            let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointID)
            return status == noErr && endpointID == uniqueID
        }
    }
}

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

public enum AudioInspector {
    public static func currentOutput() -> AudioOutputDescription {
        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        let deviceID = defaultOutputDeviceID()
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

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
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
