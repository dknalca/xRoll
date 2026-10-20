import CoreMIDI
import Foundation
#if SWIFT_PACKAGE
import XRollRealtimeQueue
#endif

public enum MIDITimestampSource: String, Codable, Equatable {
    case coreMIDI
    case callbackFallback
}

public struct MIDITimestampResolution: Equatable {
    public let hostTime: UInt64
    public let source: MIDITimestampSource

    public init(hostTime: UInt64, source: MIDITimestampSource) {
        self.hostTime = hostTime
        self.source = source
    }
}

/// Valida el timestamp de CoreMIDI contra el instante de llegada del paquete,
/// capturado en el callback. Los límites son de sanidad, no una medición de latencia.
public enum MIDITimestampResolver {
    public static let maximumPastAgeMilliseconds = 2_000.0
    public static let maximumFutureLeadMilliseconds = 100.0

    public static func resolve(coreMIDIHostTime: UInt64, callbackHostTime: UInt64) -> MIDITimestampResolution {
        guard callbackHostTime > 0 else {
            return MIDITimestampResolution(hostTime: coreMIDIHostTime, source: .coreMIDI)
        }
        guard coreMIDIHostTime > 0 else {
            return MIDITimestampResolution(hostTime: callbackHostTime, source: .callbackFallback)
        }

        if coreMIDIHostTime < callbackHostTime {
            let age = AudioClock.milliseconds(from: coreMIDIHostTime, to: callbackHostTime)
            if age > maximumPastAgeMilliseconds {
                return MIDITimestampResolution(hostTime: callbackHostTime, source: .callbackFallback)
            }
        } else if coreMIDIHostTime > callbackHostTime {
            let lead = AudioClock.milliseconds(from: callbackHostTime, to: coreMIDIHostTime)
            if lead > maximumFutureLeadMilliseconds {
                return MIDITimestampResolution(hostTime: callbackHostTime, source: .callbackFallback)
            }
        }

        return MIDITimestampResolution(hostTime: coreMIDIHostTime, source: .coreMIDI)
    }
}

public struct MIDINoteOn: Equatable {
    public let hostTime: MIDITimeStamp
    public let coreMIDIHostTime: MIDITimeStamp
    public let callbackHostTime: MIDITimeStamp
    public let timestampSource: MIDITimestampSource
    public let channel: Int
    public let note: Int
    public let velocity: Int

    public init(
        hostTime: MIDITimeStamp,
        channel: Int,
        note: Int,
        velocity: Int,
        coreMIDIHostTime: MIDITimeStamp? = nil,
        callbackHostTime: MIDITimeStamp? = nil,
        timestampSource: MIDITimestampSource = .coreMIDI
    ) {
        self.hostTime = hostTime
        self.coreMIDIHostTime = coreMIDIHostTime ?? hostTime
        self.callbackHostTime = callbackHostTime ?? hostTime
        self.timestampSource = timestampSource
        self.channel = channel
        self.note = note
        self.velocity = velocity
    }
}

public enum MIDIByteDecoder {
    public static func noteOnEvents(bytes: [UInt8], hostTime: MIDITimeStamp) -> [MIDINoteOn] {
        noteOnEvents(bytes: bytes, hostTime: hostTime, callbackHostTime: hostTime)
    }

    public static func noteOnEvents(bytes: [UInt8], hostTime: MIDITimeStamp, callbackHostTime: MIDITimeStamp) -> [MIDINoteOn] {
        var events: [MIDINoteOn] = []
        bytes.withUnsafeBufferPointer { buffer in
            decodeNoteOnEvents(bytes: buffer, hostTime: hostTime, callbackHostTime: callbackHostTime) { events.append($0) }
        }
        return events
    }

    /// Decodifica sobre memoria prestada para que el worker MIDI no cree arrays
    /// intermedios antes de reproducir el golpe.
    public static func decodeNoteOnEvents(
        bytes: UnsafeBufferPointer<UInt8>,
        hostTime: MIDITimeStamp,
        callbackHostTime: MIDITimeStamp? = nil,
        consume: (MIDINoteOn) -> Void
    ) {
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
            var data1: UInt8 = 0
            var data2: UInt8 = 0
            var receivedDataCount = 0
            while index < bytes.count && receivedDataCount < dataLength {
                let data = bytes[index]
                // Clock, Active Sensing y demás realtime pueden aparecer entre
                // cualesquiera dos bytes sin consumir datos ni running status.
                if data >= 0xF8 { index += 1; continue }
                // Un nuevo status interrumpe el mensaje incompleto. La siguiente
                // iteración lo procesará sin interpretarlo como nota o velocity.
                guard data < 0x80 else { break }
                if receivedDataCount == 0 { data1 = data } else { data2 = data }
                receivedDataCount += 1
                index += 1
            }
            guard receivedDataCount == dataLength else { continue }

            guard status & 0xF0 == 0x90, data2 > 0 else { continue }
            let arrivalHostTime = callbackHostTime ?? hostTime
            let timestamp = MIDITimestampResolver.resolve(coreMIDIHostTime: hostTime, callbackHostTime: arrivalHostTime)
            consume(MIDINoteOn(
                hostTime: timestamp.hostTime,
                channel: Int(status & 0x0F) + 1,
                note: Int(data1),
                velocity: Int(data2),
                coreMIDIHostTime: hostTime,
                callbackHostTime: arrivalHostTime,
                timestampSource: timestamp.source
            ))
        }
    }
}

public enum MIDIInputError: LocalizedError {
    case coreMIDI(OSStatus)
    case noSources
    case queueAllocationFailure

    public var errorDescription: String? {
        switch self {
        case .coreMIDI(let status):
            return "CoreMIDI devolvio el error \(status)."
        case .noSources:
            return "No hay fuentes MIDI conectadas."
        case .queueAllocationFailure:
            return "No se pudo reservar la cola de entrada MIDI."
        }
    }
}

public final class MIDIInputSession {
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private let delivery: MIDIEventDelivery
    private let callbackContext: MIDIInputCallbackContext
    private var callbackReference: UnsafeMutableRawPointer?

    /// Paquetes descartados porque la cola de entrada estaba llena. Es un
    /// diagnóstico de presión, no una medida de latencia.
    public var droppedPacketCount: UInt64 { delivery.droppedPacketCount }

    public init(onNoteOn: @escaping (MIDINoteOn) -> Void) throws {
        delivery = try MIDIEventDelivery(onNoteOn: onNoteOn)
        callbackContext = MIDIInputCallbackContext(delivery: delivery)

        var createdClient = MIDIClientRef()
        let clientStatus = MIDIClientCreate("xRoll MIDI" as CFString, nil, nil, &createdClient)
        guard clientStatus == noErr else { throw MIDIInputError.coreMIDI(clientStatus) }
        client = createdClient

        var createdPort = MIDIPortRef()
        let reference = Unmanaged.passRetained(callbackContext).toOpaque()
        let portStatus = MIDIInputPortCreate(
            client,
            "xRoll MIDI Input" as CFString,
            midiReadProc,
            reference,
            &createdPort
        )
        guard portStatus == noErr else {
            Unmanaged<MIDIInputCallbackContext>.fromOpaque(reference).release()
            MIDIClientDispose(client)
            throw MIDIInputError.coreMIDI(portStatus)
        }
        inputPort = createdPort
        callbackReference = reference
        delivery.start()
    }

    deinit {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if client != 0 { MIDIClientDispose(client) }
        delivery.stop()
        if let callbackReference {
            Unmanaged<MIDIInputCallbackContext>.fromOpaque(callbackReference).release()
        }
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

}

private final class MIDIInputCallbackContext {
    private let delivery: MIDIEventDelivery

    init(delivery: MIDIEventDelivery) { self.delivery = delivery }

    func receive(_ packetList: UnsafePointer<MIDIPacketList>) {
        let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.packet)!
        var packet = UnsafeRawPointer(packetList)
            .advanced(by: packetOffset)
            .assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<packetList.pointee.numPackets {
            let eventPacket = packet.pointee
            withUnsafeBytes(of: eventPacket.data) { bytes in
                delivery.enqueue(
                    hostTime: eventPacket.timeStamp,
                    callbackHostTime: AudioClock.currentHostTime(),
                    bytes: bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    length: eventPacket.length
                )
            }
            packet = UnsafePointer(MIDIPacketNext(packet))
        }
    }
}

/// La lectura de CoreMIDI solo copia un paquete a una cola acotada. Decodificar
/// MIDI y llamar al consumidor ocurre en este worker, nunca en `midiReadProc`.
private final class MIDIEventDelivery {
    private let queue: OpaquePointer
    private let onNoteOn: (MIDINoteOn) -> Void
    private let wake = DispatchSemaphore(value: 0)
    private let stopped = DispatchSemaphore(value: 0)
    private var thread: Thread?

    init(onNoteOn: @escaping (MIDINoteOn) -> Void) throws {
        guard let queue = xroll_realtime_queue_create(1_024) else {
            throw MIDIInputError.queueAllocationFailure
        }
        self.queue = queue
        self.onNoteOn = onNoteOn
    }

    deinit {
        stop()
        xroll_realtime_queue_destroy(queue)
    }

    var droppedPacketCount: UInt64 { xroll_realtime_queue_dropped(queue) }

    func start() {
        guard thread == nil else { return }
        let thread = Thread { [weak self] in self?.drain() }
        thread.name = "xRoll MIDI delivery"
        self.thread = thread
        thread.start()
    }

    func stop() {
        guard let thread else { return }
        thread.cancel()
        xroll_realtime_queue_clear_consumer_waiting(queue)
        wake.signal()
        stopped.wait()
        self.thread = nil
    }

    func enqueue(hostTime: MIDITimeStamp, callbackHostTime: MIDITimeStamp, bytes: UnsafePointer<UInt8>?, length: UInt16) {
        guard let bytes else { return }
        guard xroll_realtime_queue_push(queue, hostTime, callbackHostTime, bytes, length) else { return }
        if xroll_realtime_queue_consumer_needs_wake(queue) { wake.signal() }
    }

    private func drain() {
        var bytes = Array(repeating: UInt8.zero, count: 256)
        while !Thread.current.isCancelled {
            var hostTime: UInt64 = 0
            var callbackHostTime: UInt64 = 0
            var length: UInt16 = 0
            var delivered = false
            while xroll_realtime_queue_pop(queue, &hostTime, &callbackHostTime, &bytes, &length) {
                delivered = true
                bytes.withUnsafeBufferPointer { buffer in
                    let packet = UnsafeBufferPointer(start: buffer.baseAddress, count: Int(length))
                    MIDIByteDecoder.decodeNoteOnEvents(bytes: packet, hostTime: hostTime, callbackHostTime: callbackHostTime, consume: onNoteOn)
                }
            }
            guard !delivered else { continue }
            _ = xroll_realtime_queue_mark_consumer_waiting(queue)
            if xroll_realtime_queue_pop(queue, &hostTime, &callbackHostTime, &bytes, &length) {
                xroll_realtime_queue_clear_consumer_waiting(queue)
                bytes.withUnsafeBufferPointer { buffer in
                    let packet = UnsafeBufferPointer(start: buffer.baseAddress, count: Int(length))
                    MIDIByteDecoder.decodeNoteOnEvents(bytes: packet, hostTime: hostTime, callbackHostTime: callbackHostTime, consume: onNoteOn)
                }
                continue
            }
            wake.wait()
        }
        stopped.signal()
    }
}

/// Keeps an app informed when CoreMIDI publishes or removes endpoints. This
/// matters especially for BLE pads: macOS may add the source a moment after
/// the Bluetooth connection itself succeeds.
public final class MIDISetupMonitor {
    private var client = MIDIClientRef()
    private let callbackContext: MIDISetupCallbackContext
    private var callbackReference: UnsafeMutableRawPointer?

    public init(onChange: @escaping () -> Void) throws {
        callbackContext = MIDISetupCallbackContext(onChange: onChange)
        var createdClient = MIDIClientRef()
        let reference = Unmanaged.passRetained(callbackContext).toOpaque()
        let status = MIDIClientCreate(
            "xRoll MIDI Setup Monitor" as CFString,
            midiSetupNotificationProc,
            reference,
            &createdClient
        )
        guard status == noErr else {
            Unmanaged<MIDISetupCallbackContext>.fromOpaque(reference).release()
            throw MIDIInputError.coreMIDI(status)
        }
        client = createdClient
        callbackReference = reference
    }

    deinit {
        if client != 0 { MIDIClientDispose(client) }
        if let callbackReference {
            Unmanaged<MIDISetupCallbackContext>.fromOpaque(callbackReference).release()
        }
    }
}

private final class MIDISetupCallbackContext {
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange }
    func receivedSetupChange() { onChange() }
}

private func midiSetupNotificationProc(
    _ notification: UnsafePointer<MIDINotification>,
    _ refCon: UnsafeMutableRawPointer?
) {
    guard let refCon else { return }
    Unmanaged<MIDISetupCallbackContext>.fromOpaque(refCon).takeUnretainedValue().receivedSetupChange()
}

private func midiReadProc(
    _ packetList: UnsafePointer<MIDIPacketList>,
    _ readProcRefCon: UnsafeMutableRawPointer?,
    _ sourceConnRefCon: UnsafeMutableRawPointer?
) {
    guard let readProcRefCon else { return }
    Unmanaged<MIDIInputCallbackContext>.fromOpaque(readProcRefCon).takeUnretainedValue().receive(packetList)
}
