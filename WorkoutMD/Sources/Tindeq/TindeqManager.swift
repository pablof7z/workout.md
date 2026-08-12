import CoreBluetooth
import Foundation
import Observation

/// One app-wide CoreBluetooth connection to a Tindeq Progressor (including the second-generation
/// Progressor 200/500). Views activate measurement by step id so lazily-created pager neighbors
/// cannot accidentally stop the currently visible set.
@Observable
final class TindeqManager: NSObject {
    static let shared = TindeqManager()

    enum State: Equatable {
        case idle
        case unavailable(String)
        case scanning
        case connecting
        case preparing
        case sampling
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var deviceName = "Tindeq"
    private(set) var latestSamples: [TindeqProtocol.WeightSample] = []
    private(set) var measurementRevision = 0
    private(set) var lowBattery = false

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var dataCharacteristic: CBCharacteristic?
    @ObservationIgnored private var controlCharacteristic: CBCharacteristic?
    @ObservationIgnored private var activeStepID: UUID?
    @ObservationIgnored private var shouldStartAfterTare = false

#if targetEnvironment(simulator)
    @ObservationIgnored private var demoTimer: Timer?
    @ObservationIgnored private var demoTick: UInt32 = 0
#endif

    var isConnected: Bool {
        peripheral?.state == .connected
    }

    var statusLabel: String {
        switch state {
        case .idle: return "Tindeq"
        case .unavailable: return "Bluetooth off"
        case .scanning: return "Searching"
        case .connecting, .preparing: return "Connecting"
        case .sampling: return deviceName
        case .failed: return "Reconnect"
        }
    }

    func activate(for stepID: UUID) {
        activeStepID = stepID
        lowBattery = false
        ensureCentral()
        guard let central else { return }
        switch central.state {
        case .poweredOn:
            connectOrScan()
        case .poweredOff:
            state = .unavailable("Turn on Bluetooth to connect your Tindeq.")
        case .unauthorized:
            state = .unavailable("Allow Bluetooth access in Settings to use Tindeq.")
        case .unsupported:
            state = .unavailable("This iPhone does not support Bluetooth LE.")
        default:
            state = .preparing
        }
    }

    func deactivate(for stepID: UUID) {
        guard activeStepID == stepID else { return }
        activeStepID = nil
        stopMeasurement()
#if targetEnvironment(simulator)
        demoTimer?.invalidate()
        demoTimer = nil
#endif
    }

    func retry() {
        guard activeStepID != nil else { return }
        if peripheral?.state == .connected {
            tareAndStartMeasurement()
        } else {
            connectOrScan()
        }
    }

    func tareAndStartMeasurement() {
        guard activeStepID != nil,
              let peripheral,
              let controlCharacteristic else { return }
        state = .preparing
        latestSamples = []
        shouldStartAfterTare = true
        peripheral.writeValue(
            Data([TindeqProtocol.Command.tare.rawValue]),
            for: controlCharacteristic,
            type: .withResponse
        )
    }

    func stopMeasurement() {
        guard let peripheral, let controlCharacteristic,
              peripheral.state == .connected else {
            if activeStepID == nil { state = .idle }
            return
        }
        peripheral.writeValue(
            Data([TindeqProtocol.Command.stopWeightMeasurement.rawValue]),
            for: controlCharacteristic,
            type: .withResponse
        )
        if activeStepID == nil { state = .idle }
    }

#if targetEnvironment(simulator)
    /// Simulator-only stream for exercising the complete UI without pretending it proves BLE.
    func startDemo() {
        demoTimer?.invalidate()
        state = .sampling
        deviceName = "Tindeq Preview"
        demoTick = 0
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.activeStepID != nil else { return }
            self.demoTick &+= 50_000
            let seconds = Double(self.demoTick) / 1_000_000
            let force: Double
            if seconds < 1 { force = 0 }
            else if seconds < 2 { force = (seconds - 1) * 32 }
            else if seconds < 9.5 { force = 32 + sin(seconds * 5) * 0.8 }
            else { force = max(0, 32 - (seconds - 9.5) * 50) }
            self.latestSamples = [.init(kilograms: force, timestampMicroseconds: self.demoTick)]
            self.measurementRevision &+= 1
        }
    }
#endif

    private func ensureCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    private func connectOrScan() {
        guard let central, central.state == .poweredOn else { return }
        if let peripheral, peripheral.state == .connected {
            discoverIfNeeded(on: peripheral)
            return
        }

        let service = CBUUID(string: TindeqProtocol.serviceUUID)
        if let connected = central.retrieveConnectedPeripherals(withServices: [service]).first {
            peripheral = connected
            connected.delegate = self
            state = .connecting
            central.connect(connected)
            return
        }

        state = .scanning
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func discoverIfNeeded(on peripheral: CBPeripheral) {
        if let dataCharacteristic, controlCharacteristic != nil {
            if dataCharacteristic.isNotifying {
                tareAndStartMeasurement()
            } else {
                peripheral.setNotifyValue(true, for: dataCharacteristic)
            }
        } else {
            state = .preparing
            peripheral.discoverServices([CBUUID(string: TindeqProtocol.serviceUUID)])
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
    }
}

extension TindeqManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard activeStepID != nil else { return }
        switch central.state {
        case .poweredOn: connectOrScan()
        case .poweredOff: state = .unavailable("Turn on Bluetooth to connect your Tindeq.")
        case .unauthorized: state = .unavailable("Allow Bluetooth access in Settings to use Tindeq.")
        case .unsupported: state = .unavailable("This iPhone does not support Bluetooth LE.")
        default: state = .preparing
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = localName ?? peripheral.name ?? ""
        guard name.range(
            of: TindeqProtocol.advertisedNamePrefix,
            options: [.anchored, .caseInsensitive]
        ) != nil else { return }
        central.stopScan()
        self.peripheral = peripheral
        deviceName = name.isEmpty ? "Tindeq" : name
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        discoverIfNeeded(on: peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        fail(error?.localizedDescription ?? "Could not connect to Tindeq.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dataCharacteristic = nil
        controlCharacteristic = nil
        self.peripheral = nil
        guard activeStepID != nil else { state = .idle; return }
        fail(error?.localizedDescription ?? "Tindeq disconnected.")
    }
}

extension TindeqManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { fail(error.localizedDescription); return }
        guard let service = peripheral.services?.first(where: {
            $0.uuid == CBUUID(string: TindeqProtocol.serviceUUID)
        }) else {
            fail("The connected device does not expose the Progressor service.")
            return
        }
        peripheral.discoverCharacteristics(
            [
                CBUUID(string: TindeqProtocol.dataCharacteristicUUID),
                CBUUID(string: TindeqProtocol.controlCharacteristicUUID)
            ],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { fail(error.localizedDescription); return }
        dataCharacteristic = service.characteristics?.first {
            $0.uuid == CBUUID(string: TindeqProtocol.dataCharacteristicUUID)
        }
        controlCharacteristic = service.characteristics?.first {
            $0.uuid == CBUUID(string: TindeqProtocol.controlCharacteristicUUID)
        }
        guard let dataCharacteristic, controlCharacteristic != nil else {
            fail("The Tindeq measurement characteristics were not found.")
            return
        }
        peripheral.setNotifyValue(true, for: dataCharacteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error { fail(error.localizedDescription); return }
        guard characteristic.uuid == CBUUID(string: TindeqProtocol.dataCharacteristicUUID),
              characteristic.isNotifying else { return }
        tareAndStartMeasurement()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail(error.localizedDescription); return }
        guard characteristic.uuid == CBUUID(string: TindeqProtocol.controlCharacteristicUUID),
              shouldStartAfterTare,
              let controlCharacteristic else { return }
        shouldStartAfterTare = false
        peripheral.writeValue(
            Data([TindeqProtocol.Command.startWeightMeasurement.rawValue]),
            for: controlCharacteristic,
            type: .withResponse
        )
        state = .sampling
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail(error.localizedDescription); return }
        guard characteristic.uuid == CBUUID(string: TindeqProtocol.dataCharacteristicUUID),
              let data = characteristic.value,
              !data.isEmpty else { return }

        if data[0] == TindeqProtocol.Response.lowPowerWarning.rawValue {
            lowBattery = true
            return
        }
        let samples = TindeqProtocol.decodeWeightSamples(data)
        guard !samples.isEmpty else { return }
        latestSamples = samples
        measurementRevision &+= 1
    }
}
