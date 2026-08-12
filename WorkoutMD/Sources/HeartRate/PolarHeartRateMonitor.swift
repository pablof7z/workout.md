import CoreBluetooth
import Foundation
import Observation

/// Automatically connects to the first available Polar monitor that exposes the standard
/// Bluetooth Heart Rate Service. Polar H-series sensors publish their readings through this GATT
/// service, so no vendor SDK or pairing screen is needed.
@Observable
final class PolarHeartRateMonitor: NSObject {
    private(set) var currentBPM: Int?
    private(set) var sensorName: String?

    @ObservationIgnored var onHeartRate: ((HeartRateSample, String) -> Void)?

    @ObservationIgnored private var centralManager: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var isRunning = false

    private static let heartRateService = CBUUID(string: "180D")
    private static let heartRateMeasurement = CBUUID(string: "2A37")

    /// Starts opportunistic discovery. Safe to call more than once during the same workout.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        if let centralManager {
            if centralManager.state == .poweredOn {
                findOrScanForPolar(using: centralManager)
            }
        } else {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        }
    }

    /// Stops discovery and releases the monitor when the active workout ends.
    func stop() {
        isRunning = false
        onHeartRate = nil
        centralManager?.stopScan()
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        resetConnection()
    }

    /// Decodes the Bluetooth SIG Heart Rate Measurement characteristic (0x2A37).
    /// Bit zero of the flags byte selects an 8- or 16-bit little-endian BPM value.
    static func parseHeartRateMeasurement(_ data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        let flags = data[data.startIndex]
        let valueStart = data.index(after: data.startIndex)

        if flags & 0x01 == 0 {
            return Int(data[valueStart])
        }

        guard data.distance(from: valueStart, to: data.endIndex) >= 2 else { return nil }
        let highByte = data[data.index(after: valueStart)]
        return Int(data[valueStart]) | (Int(highByte) << 8)
    }

    private func findOrScanForPolar(using central: CBCentralManager) {
        guard isRunning, peripheral == nil else { return }

        if let connectedPolar = central
            .retrieveConnectedPeripherals(withServices: [Self.heartRateService])
            .first(where: { Self.isPolar(name: $0.name) }) {
            connect(to: connectedPolar, advertisedName: connectedPolar.name, using: central)
            return
        }

        central.scanForPeripherals(
            withServices: [Self.heartRateService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func connect(to peripheral: CBPeripheral, advertisedName: String?, using central: CBCentralManager) {
        central.stopScan()
        self.peripheral = peripheral
        sensorName = advertisedName ?? peripheral.name ?? "Polar heart rate monitor"
        peripheral.delegate = self
        central.connect(peripheral)
    }

    private func restartScanIfNeeded() {
        resetConnection()
        guard isRunning, let centralManager, centralManager.state == .poweredOn else { return }
        findOrScanForPolar(using: centralManager)
    }

    private func resetConnection() {
        peripheral = nil
        sensorName = nil
        currentBPM = nil
    }

    private static func isPolar(name: String?) -> Bool {
        name?.localizedCaseInsensitiveContains("polar") == true
    }
}

extension PolarHeartRateMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard isRunning else { return }
        if central.state == .poweredOn {
            findOrScanForPolar(using: central)
        } else {
            central.stopScan()
            resetConnection()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard Self.isPolar(name: advertisedName ?? peripheral.name) else { return }
        connect(to: peripheral, advertisedName: advertisedName, using: central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.heartRateService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        restartScanIfNeeded()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        restartScanIfNeeded()
    }
}

extension PolarHeartRateMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.heartRateService }) else {
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.heartRateMeasurement], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let measurement = service.characteristics?.first(where: { $0.uuid == Self.heartRateMeasurement }) else {
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.setNotifyValue(true, for: measurement)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              characteristic.uuid == Self.heartRateMeasurement,
              let data = characteristic.value,
              let bpm = Self.parseHeartRateMeasurement(data),
              bpm > 0 else { return }

        let name = sensorName ?? peripheral.name ?? "Polar heart rate monitor"
        currentBPM = bpm
        onHeartRate?(HeartRateSample(timestamp: .now, beatsPerMinute: bpm), name)
    }
}
