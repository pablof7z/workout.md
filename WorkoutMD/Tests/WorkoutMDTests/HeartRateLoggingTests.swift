import Foundation
import Testing
@testable import WorkoutMD

struct HeartRateLoggingTests {
    @Test func parsesEightBitMeasurement() {
        #expect(PolarHeartRateMonitor.parseHeartRateMeasurement(Data([0x00, 72])) == 72)
    }

    @Test func parsesSixteenBitLittleEndianMeasurement() {
        #expect(PolarHeartRateMonitor.parseHeartRateMeasurement(Data([0x01, 0x2C, 0x01])) == 300)
    }

    @Test func rejectsTruncatedMeasurements() {
        #expect(PolarHeartRateMonitor.parseHeartRateMeasurement(Data()) == nil)
        #expect(PolarHeartRateMonitor.parseHeartRateMeasurement(Data([0x00])) == nil)
        #expect(PolarHeartRateMonitor.parseHeartRateMeasurement(Data([0x01, 0x2C])) == nil)
    }

    @Test func rendersPolarSummaryAndTimestampedSamplesInSessionMarkdown() {
        let record = WorkoutRecord(name: "Intervals", heartRateSensorName: "Polar H10 12345678")
        record.heartRateSamples = [
            HeartRateSampleRecord(timestamp: Date(timeIntervalSince1970: 1_700_000_000), beatsPerMinute: 120),
            HeartRateSampleRecord(timestamp: Date(timeIntervalSince1970: 1_700_000_001), beatsPerMinute: 150)
        ]

        let markdown = MarkdownGenerator.renderSession(record)

        #expect(markdown.contains("heart_rate_sensor: Polar H10 12345678"))
        #expect(markdown.contains("avg_heart_rate_bpm: 135"))
        #expect(markdown.contains("max_heart_rate_bpm: 150"))
        #expect(markdown.contains("- Heart rate: avg 135 bpm · 120–150 bpm · Polar H10 12345678"))
        #expect(markdown.contains("## Heart Rate"))
        #expect(markdown.contains("| 120 |"))
        #expect(markdown.contains("| 150 |"))
    }
}
