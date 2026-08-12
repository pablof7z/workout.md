import Foundation

/// Wire constants and decoding for the public Tindeq Progressor Bluetooth API.
/// Source: https://tindeq.com/progressor_api/ and Tindeq's official Python example.
enum TindeqProtocol {
    static let advertisedNamePrefix = "Progressor"
    static let serviceUUID = "7E4E1701-1EA6-40C9-9DCC-13D34FFEAD57"
    static let dataCharacteristicUUID = "7E4E1702-1EA6-40C9-9DCC-13D34FFEAD57"
    static let controlCharacteristicUUID = "7E4E1703-1EA6-40C9-9DCC-13D34FFEAD57"

    enum Command: UInt8 {
        case tare = 100
        case startWeightMeasurement = 101
        case stopWeightMeasurement = 102
        case getBatteryVoltage = 111
    }

    enum Response: UInt8 {
        case command = 0
        case weightMeasurement = 1
        case rfdPeak = 2
        case rfdPeakSeries = 3
        case lowPowerWarning = 4
    }

    struct WeightSample: Equatable, Sendable {
        let kilograms: Double
        /// Device-relative microseconds. UInt32 wrapping is handled by `elapsedSeconds`.
        let timestampMicroseconds: UInt32

        func elapsedSeconds(since earlier: WeightSample) -> Double {
            let delta = timestampMicroseconds &- earlier.timestampMicroseconds
            return Double(delta) / 1_000_000
        }
    }

    /// A weight notification is `[type, payloadLength, float32 kg, uint32 microseconds, ...]`.
    /// Invalid/truncated packets are ignored rather than partially interpreted.
    static func decodeWeightSamples(_ data: Data) -> [WeightSample] {
        guard data.count >= 10,
              data[0] == Response.weightMeasurement.rawValue else { return [] }

        let declaredPayloadLength = Int(data[1])
        let availablePayloadLength = data.count - 2
        let payloadLength = min(declaredPayloadLength, availablePayloadLength)
        guard payloadLength >= 8 else { return [] }

        var samples: [WeightSample] = []
        var offset = 2
        let end = 2 + payloadLength
        while offset + 8 <= end {
            let bits = littleEndianUInt32(data, at: offset)
            let timestamp = littleEndianUInt32(data, at: offset + 4)
            let kilograms = Double(Float(bitPattern: bits))
            if kilograms.isFinite {
                samples.append(WeightSample(kilograms: kilograms, timestampMicroseconds: timestamp))
            }
            offset += 8
        }
        return samples
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
