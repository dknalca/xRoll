import CoreMIDI
import Foundation

public struct MIDINoteOn: Equatable {
    public let hostTime: MIDITimeStamp
    public let channel: Int
    public let note: Int
    public let velocity: Int
}

public enum MIDIByteDecoder {
    public static func noteOnEvents(bytes: [UInt8], hostTime: MIDITimeStamp) -> [MIDINoteOn] {
        var events: [MIDINoteOn] = []
        var index = 0
        var runningStatus: UInt8?

        while index < bytes.count {
            let byte = bytes[index]
            if byte >= 0xF8 {
                index += 1
                continue
            }

            let status: UInt8
            if byte & 0x80 != 0 {
                status = byte
                runningStatus = byte < 0xF0 ? byte : nil
                index += 1
            } else if let savedStatus = runningStatus {
                status = savedStatus
            } else {
                index += 1
                continue
            }

            guard status < 0xF0 else {
                runningStatus = nil
                continue
            }

            let dataLength = (status & 0xE0 == 0xC0) ? 1 : 2
            guard index + dataLength <= bytes.count else { break }
            let data1 = bytes[index]
            let data2 = dataLength == 2 ? bytes[index + 1] : 0
            index += dataLength

            guard status & 0xF0 == 0x90, data2 > 0 else { continue }
            events.append(MIDINoteOn(
                hostTime: hostTime,
                channel: Int(status & 0x0F) + 1,
                note: Int(data1),
                velocity: Int(data2)
            ))
        }
        return events
    }
}

public enum MIDIInputError: LocalizedError {
    case coreMIDI(OSStatus)
    case noSources

    public var errorDescription: String? {
        switch self {
        case .coreMIDI(let status):
            return "CoreMIDI devolvio el error \(status)."
        case .noSources:
            return "No hay fuentes MIDI conectadas."
        }
    }
}

public final class MIDIInputSession {
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private let onNoteOn: (MIDINoteOn) -> Void

    public init(onNoteOn: @escaping (MIDINoteOn) -> Void) throws {
        self.onNoteOn = onNoteOn

        var createdClient = MIDIClientRef()
        let clientStatus = MIDIClientCreate("xRoll MIDI" as CFString, nil, nil, &createdClient)
        guard clientStatus == noErr else { throw MIDIInputError.coreMIDI(clientStatus) }
        client = createdClient

        var createdPort = MIDIPortRef()
        let portStatus = MIDIInputPortCreate(
            client,
            "xRoll MIDI Input" as CFString,
            midiReadProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &createdPort
        )
        guard portStatus == noErr else {
            MIDIClientDispose(client)
            throw MIDIInputError.coreMIDI(portStatus)
        }
        inputPort = createdPort
    }

    deinit {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    public func connectAllSources() throws {
        let sourceCount = MIDIGetNumberOfSources()
        guard sourceCount > 0 else { throw MIDIInputError.noSources }

        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }
            try connect(source: source)
        }
    }

    public func connect(source: MIDIEndpointRef) throws {
        let status = MIDIPortConnectSource(inputPort, source, nil)
        guard status == noErr else { throw MIDIInputError.coreMIDI(status) }
    }

    fileprivate func receive(_ packetList: UnsafePointer<MIDIPacketList>) {
        let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.packet)!
        var packet = UnsafeRawPointer(packetList)
            .advanced(by: packetOffset)
            .assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<packetList.pointee.numPackets {
            let eventPacket = packet.pointee
            let bytes = withUnsafeBytes(of: eventPacket.data) {
                Array($0.prefix(Int(eventPacket.length)))
            }
            MIDIByteDecoder.noteOnEvents(bytes: bytes, hostTime: eventPacket.timeStamp).forEach(onNoteOn)
            packet = UnsafePointer(MIDIPacketNext(packet))
        }
    }
}

private func midiReadProc(
    _ packetList: UnsafePointer<MIDIPacketList>,
    _ readProcRefCon: UnsafeMutableRawPointer?,
    _ sourceConnRefCon: UnsafeMutableRawPointer?
) {
    guard let readProcRefCon else { return }
    Unmanaged<MIDIInputSession>.fromOpaque(readProcRefCon).takeUnretainedValue().receive(packetList)
}
