import Foundation
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct ReportLoadingStateTests {
    @Test func emptyResultRefreshFailureAndRecoveryKeepSnapshotAttributable() async throws {
        let source = ControlledReportInput()
        let model = NativeReportViewModel(recorder: nil, snapshotLoader: { _, _ in source.load() })
        defer { model.teardown() }
        model.load()
        try await waitForLoad(model)
        #expect(!model.loadFailed)
        let capturedAt = try #require(model.snapshot?.capturedAt)
        #expect(model.rangeModel != nil)
        #expect(model.committedExportRange() != nil)

        source.shouldFail = true
        model.refreshCurrentReport()
        #expect(model.committedExportRange() == nil)
        try await waitForLoad(model)
        #expect(model.loadFailed)
        #expect(model.snapshot?.capturedAt == capturedAt)
        #expect(model.committedExportRange() == nil)

        source.shouldFail = false
        model.refreshCurrentReport()
        try await waitForLoad(model)
        #expect(!model.loadFailed)
        #expect(model.snapshot != nil)
        #expect(model.committedExportRange() != nil)
    }

    @Test func switchingRangeDuringLoadCommitsLatestRequest() async throws {
        let source = ControlledReportInput(delay: 0.1)
        let model = NativeReportViewModel(recorder: nil, snapshotLoader: { _, _ in source.load() })
        defer { model.teardown() }
        model.load()
        model.selectRange(.week)
        try await waitForLoad(model)
        #expect(!model.loadFailed)
        #expect(model.selectedRange == .week)
        #expect(model.rangeModel?.range == .week)
        #expect(model.committedExportRange()?.label == ReportTimeRange.week.label)
    }

    @Test func refreshDuringAggregationDoesNotLeaveExportsPermanentlyBusy() async throws {
        let source = ControlledReportInput()
        let model = NativeReportViewModel(recorder: nil, snapshotLoader: { _, _ in source.load() })
        defer { model.teardown() }
        model.load()
        try await waitForLoad(model)
        model.selectRange(.week)
        #expect(model.isAggregating)
        model.refreshCurrentReport()
        try await waitForLoad(model)
        #expect(!model.isAggregating)
        #expect(model.committedExportRange()?.label == ReportTimeRange.week.label)
    }

    @Test func closingWhileLoadingRejectsLateResult() async throws {
        let source = ControlledReportInput(delay: 0.1)
        let model = NativeReportViewModel(recorder: nil, snapshotLoader: { _, _ in source.load() })
        model.load()
        model.teardown()
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.snapshot == nil)
        #expect(model.rangeModel == nil)
        #expect(model.committedExportRange() == nil)
    }

    private func waitForLoad(_ model: NativeReportViewModel) async throws {
        for _ in 0..<200 {
            if !model.isLoading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Report load did not finish within the test deadline")
    }
}

nonisolated private final class ControlledReportInput: @unchecked Sendable {
    private let lock = NSLock()
    private var failure = false
    private let delay: TimeInterval

    init(delay: TimeInterval = 0) { self.delay = delay }

    var shouldFail: Bool {
        get { lock.withLock { failure } }
        set { lock.withLock { failure = newValue } }
    }

    func load() -> StatisticsReportSnapshotInput? {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        guard !shouldFail else { return nil }
        return StatisticsReportSnapshotInput(minutes: [], hours: [], days: [],
            process: nil, systemSleepIntervals: [])
    }
}
