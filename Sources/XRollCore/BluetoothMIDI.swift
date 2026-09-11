import CoreBluetooth
import CoreMIDI
import Foundation

/// Public description of a BLE MIDI pad discovered by xRoll. It deliberately
/// contains no CoreBluetooth object so the SwiftUI layer stays independent of
/// the transport implementation.
public struct BluetoothMIDIDevice: Identifiable, Equatable {
    public enum State: Equatable {
        case discovered
        case connecting
        case connected
        case unavailable

        public var label: String {
            switch self {
            case .discovered: return "Disponible"
            case .connecting: return "Conectando…"
            case .connected: return "Conectado"
            case .unavailable: return "No disponible"
            }
        }
    }

    public let id: UUID
    public let name: String
    public let state: State

    public init(id: UUID, name: String, state: State) {
        self.id = id
        self.name = name
        self.state = state
    }
}

/// Connects BLE MIDI pads that macOS has not yet promoted to CoreMIDI.
///
/// On macOS 12 this supplements Audio MIDI Setup. Once the MIDI service and
/// its I/O characteristic are confirmed, CoreMIDI owns the connection and the
/// regular xRoll MIDI input selector sees it like a USB controller.
public final class BluetoothMIDIManager: NSObject {
    public var onUpdate: (([BluetoothMIDIDevice], String) -> Void)?

    private let midiService = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    private let midiIOCharacteristic = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")
    private var central: CBCentralManager?
    private var peripherals = [UUID: CBPeripheral]()
    private var states = [UUID: BluetoothMIDIDevice.State]()
    private var preferredID: UUID?
    private var message = "Bluetooth MIDI apagado"

    public var supportsDirectConnection: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    public func start(preferredDeviceID: UUID? = nil) {
        self.preferredID = preferredDeviceID
        if central == nil {
            central = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        } else {
            scan()
        }
    }

    public func refresh() {
        scan()
    }

    public func connect(_ id: UUID) {
        guard supportsDirectConnection else {
            message = "macOS 12 requiere conectar el pad desde Configuración de Audio MIDI y después refrescar xRoll."
            publish()
            return
        }
        guard let peripheral = peripherals[id], let central, central.state == .poweredOn else {
            message = "Activa Bluetooth en el Mac y vuelve a buscar pads MIDI."
            publish()
            return
        }
        preferredID = id
        states[id] = .connecting
        message = "Conectando (displayName(for: peripheral))…"
        central.connect(peripheral, options: nil)
        publish()
    }

    public func disconnect() {
        guard let preferredID, let peripheral = peripherals[preferredID], let central else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    private func scan() {
        guard let central else { return }
        guard central.state == .poweredOn else {
            message = bluetoothStateMessage(central.state)
            publish()
            return
        }
        central.stopScan()
        message = "Buscando pads Bluetooth MIDI…"
        central.scanForPeripherals(withServices: [midiService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        publish()
    }

    private func activateMIDI(for peripheral: CBPeripheral) {
        guard #available(macOS 13.0, *) else {
            message = "macOS 12 requiere conectar el pad desde Configuración de Audio MIDI y después refrescar xRoll."
            publish()
            return
        }
        let status = MIDIBluetoothDriverActivateAllConnections()
        if status == noErr {
            states[peripheral.identifier] = .connected
            message = "(displayName(for: peripheral)) conectado. Ya aparece en la entrada MIDI."
        } else {
            states[peripheral.identifier] = .unavailable
            message = "Bluetooth conectado, pero CoreMIDI no pudo activarlo (error \(status))."
        }
        publish()
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? peripheral.name! : "Pad Bluetooth MIDI"
    }

    private func bluetoothStateMessage(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "Bluetooth MIDI listo"
        case .poweredOff: return "Activa Bluetooth en el Mac para buscar pads MIDI."
        case .unauthorized: return "xRoll no tiene permiso para usar Bluetooth. Revísalo en Privacidad y seguridad."
        case .unsupported: return "Este Mac no ofrece Bluetooth LE MIDI."
        case .resetting: return "Bluetooth se está reiniciando…"
        case .unknown: return "Comprobando Bluetooth…"
        @unknown default: return "Estado Bluetooth desconocido."
        }
    }

    private func publish() {
        let devices = peripherals.values.map { peripheral in
            BluetoothMIDIDevice(
                id: peripheral.identifier,
                name: displayName(for: peripheral),
                state: states[peripheral.identifier] ?? .discovered
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        onUpdate?(devices, message)
    }
}

extension BluetoothMIDIManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        message = bluetoothStateMessage(central.state)
        publish()
        if central.state == .poweredOn { scan() }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        if states[peripheral.identifier] == nil { states[peripheral.identifier] = .discovered }
        publish()
        if peripheral.identifier == preferredID, peripheral.state == .disconnected {
            connect(peripheral.identifier)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripherals[peripheral.identifier] = peripheral
        states[peripheral.identifier] = .connecting
        peripheral.delegate = self
        message = "Verificando MIDI en (displayName(for: peripheral))…"
        peripheral.discoverServices([midiService])
        publish()
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        states[peripheral.identifier] = .unavailable
        message = "No se pudo conectar (displayName(for: peripheral)). \(error?.localizedDescription ?? "")"
        publish()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        states[peripheral.identifier] = .discovered
        message = "(displayName(for: peripheral)) se ha desconectado."
        publish()
    }
}

extension BluetoothMIDIManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == midiService }) else {
            states[peripheral.identifier] = .unavailable
            message = "(displayName(for: peripheral)) no expone el servicio Bluetooth MIDI."
            publish()
            return
        }
        peripheral.discoverCharacteristics([midiIOCharacteristic], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let hasMIDIIO = error == nil && service.characteristics?.contains(where: { $0.uuid == midiIOCharacteristic }) == true
        guard hasMIDIIO else {
            states[peripheral.identifier] = .unavailable
            message = "(displayName(for: peripheral)) no expone entrada/salida Bluetooth MIDI."
            publish()
            return
        }
        activateMIDI(for: peripheral)
    }
}
