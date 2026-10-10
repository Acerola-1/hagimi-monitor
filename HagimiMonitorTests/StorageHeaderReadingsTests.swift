import AppKit
import Testing
@testable import HagimiMonitorDirect

struct StorageHeaderReadingsTests {
    @Test func diskReadsRawModuleMetricsAndKeepsUnknownDifferentFromZero() {
        var module = MonitorModule(kind: .storage, value: 90, summary: "90%", metrics: [
            MonitorMetric(name: "disk-read-rate", value: "", numericValue: 0),
            MonitorMetric(name: "disk-write-rate", value: "", numericValue: 1_048_576)
        ], samples: [])
        #expect(StorageHeaderReadings.rate(module, key: "disk-read-rate") == "0 B/s")
        #expect(StorageHeaderReadings.rate(module, key: "disk-write-rate") == "1.0 MB/s")
        #expect(StorageHeaderReadings.rate(module, key: "missing") == "—")
        #expect(StorageHeaderReadings.hasRates(module))
        module.isPlaceholder = true
        #expect(StorageHeaderReadings.rate(module, key: "disk-read-rate") == "—")
        #expect(!StorageHeaderReadings.hasRates(module))
    }

    @Test func unavailableDiskRatesFallBackToRealFreeCapacity() {
        let module = MonitorModule(kind: .storage, value: 90, summary: "90%", metrics: [
            MonitorMetric(name: "free", value: "128 GB", numericValue: 128_000_000_000)
        ], samples: [])
        #expect(!StorageHeaderReadings.hasRates(module))
        #expect(StorageHeaderReadings.freeSpace(module) == "128 GB")
        #expect(StorageHeaderReadings.freeSpace(.placeholder(kind: .storage)) == "—")
    }

    @MainActor @Test func storageHeaderWorstRatesFitSharedPill() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: RowHeaderPillMetrics.valueSize, weight: .medium)
        let budget = RowHeaderPillMetrics.width - 2 * RowHeaderPillMetrics.horizontalPadding
        for value in ["1023 B/s", "1024 KB/s", "1024 MB/s", "999 GB/s", "9.9 GB/s", "999.99 GB", "99999 MB", "—"] {
            let width = (value as NSString).size(withAttributes: [.font: font]).width
            #expect(width <= budget, "\(value) needs \(width)pt, budget \(budget)pt")
        }
    }
}
