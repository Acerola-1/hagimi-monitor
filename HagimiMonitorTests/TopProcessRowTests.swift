import AppKit
import Foundation
import Testing
@testable import HagimiMonitorDirect

/// TOP 榜的系统路径判定，以及 Apple container 分组的行名。
/// 不启动容器：路径和参数都用固定字符串。
struct TopProcessRowTests {
    private let runtime = "/usr/local/libexec/container/plugins/container-runtime-linux/bin/container-runtime-linux"
    private let virtualMachine = "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine"

    @Test func localInstallPrefixIsNotASystemProcess() {
        #expect(isSystemProcessPath("/usr/local/bin/container", includeSystemProcesses: false) == false)
        #expect(isSystemProcessPath(runtime, includeSystemProcesses: false) == false)
    }

    @Test func otherUsrAndSystemPathsStayExcluded() {
        let hidden = [
            "/usr/bin/ssh",
            "/usr/libexec/containermanagerd",
            "/System/Library/CoreServices/WindowServer",
            "/usr/localfoo/bin/not-local",
            virtualMachine,
        ]
        for path in hidden {
            #expect(isSystemProcessPath(path, includeSystemProcesses: false), "\(path) 仍应算系统进程")
        }
    }

    @Test func groupFilterUsesHostPathNotVirtualMachinePath() {
        // 虚机自身在 /System 下，仍算系统进程；是否上榜只看 runtime 宿主路径。
        #expect(isSystemProcessPath(virtualMachine, includeSystemProcesses: false))
        #expect(isSystemProcessPath(runtime, includeSystemProcesses: false) == false)

        let paths: [pid_t: String] = [10: runtime, 11: virtualMachine]
        let host = processGroupKey(
            for: 11,
            responsiblePid: 10,
            parentOf: { _ in 1 },
            pathOf: { paths[$0] ?? "" }
        )
        #expect(host == 10)
        #expect(isSystemProcessPath(paths[host] ?? "", includeSystemProcesses: false) == false)
    }

    @Test func uuidWinsAndRootPathDoesNotBecomeTheLabel() {
        let root = "/Users/a/Library/Application Support/com.apple.container/containers/hagimi-memory-probe"
        let identifier = containerIdentifier(in: [
            runtime, "start", "--root", root, "--uuid", "hagimi-memory-probe",
        ])
        #expect(identifier == "hagimi-memory-probe")
        #expect(identifier != root)
        #expect(identifier.contains("/") == false)
    }

    @Test func rootLastComponentIsUsedWhenUuidIsMissing() {
        let identifier = containerIdentifier(in: [
            runtime, "start", "--root", "/Users/a/containers/only-root",
        ])
        #expect(identifier == "only-root")
    }

    @Test func missingArgumentsYieldAnEmptyIdentifier() {
        #expect(containerIdentifier(in: [runtime, "start"]) == "")
        #expect(containerIdentifier(in: []) == "")
    }

    @Test func twoContainersStaySeparateRowsWithoutATotal() {
        let rows = [
            (pid: pid_t(10), id: "clickhouse"),
            (pid: pid_t(20), id: "redis"),
        ].map { item in
            containerRowLabel(
                path: runtime,
                arguments: [runtime, "start", "--uuid", item.id],
                fallbackName: "container-runtime-linux"
            )
        }
        #expect(rows == ["clickhouse", "redis"])
        #expect(rows.count == 2)
    }

    @Test func unreadArgumentsKeepTheExecutableName() {
        #expect(containerRowLabel(path: runtime, arguments: nil, fallbackName: "container-runtime-linux") == "container-runtime-linux")
        #expect(containerRowLabel(path: runtime, arguments: [runtime, "start"], fallbackName: "container-runtime-linux") == "container-runtime-linux")
    }

    @Test func directCanReadItsOwnArguments() {
        let arguments = processArguments(for: getpid())
        #expect(arguments?.isEmpty == false)
        if let own = arguments, let expected = CommandLine.arguments.last {
            #expect(own.contains(expected))
        }
    }

    @MainActor
    @Test func processActionSafetyBlocksSelfSystemAndMismatchedPIDReuse() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        #expect(ProcessActionHelper.isProtectedSystemProcess(pid: 0, name: "kernel_task"))
        #expect(ProcessActionHelper.isProtectedSystemProcess(pid: 1, name: "launchd"))
        #expect(ProcessActionHelper.isProtectedSystemProcess(pid: 1234, name: "WindowServer"))
        #expect(ProcessActionHelper.isProtectedSystemProcess(pid: selfPID, name: "HagimiMonitorDirect"))
        #expect(ProcessActionHelper.isProtectedSystemProcess(pid: 99999, name: "Safari") == false)

        #if DIRECT_DISTRIBUTION
        #expect(ProcessActionHelper.canTerminate(pid: selfPID, name: "HagimiMonitorDirect") == false)
        #expect(ProcessActionHelper.canTerminate(pid: 1, name: "launchd") == false)
        if let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
            #expect(ProcessActionHelper.matchesIdentity(app: finder, expectedName: "DefinitelyNotFinderApp") == false)
            #expect(ProcessActionHelper.terminate(pid: finder.processIdentifier, expectedName: "DefinitelyNotFinderApp") == false)
        }
        #endif
    }

    @Test func processRankingFreezePreservesOrderRefreshesValuesAndUnfreezes() {
        struct Item: Equatable {
            let pid: pid_t
            let name: String
            var value: String
        }
        let initial = [
            Item(pid: 101, name: "Safari", value: "42.0%"),
            Item(pid: 202, name: "Xcode", value: "30.0%")
        ]
        let updatedLive = [
            Item(pid: 303, name: "Finder", value: "60.0%"),
            Item(pid: 202, name: "Xcode", value: "50.0%")
        ]
        let frozenResolved = ProcessRankingFreeze.resolve(
            live: updatedLive,
            frozen: initial,
            id: \.pid
        ) { existing, updated in
            Item(pid: existing.pid, name: existing.name, value: updated.value)
        }
        #expect(frozenResolved == [
            Item(pid: 101, name: "Safari", value: "42.0%"),
            Item(pid: 202, name: "Xcode", value: "50.0%")
        ])
        let unfrozenResolved = ProcessRankingFreeze.resolve(
            live: updatedLive,
            frozen: nil,
            id: \.pid
        ) { existing, updated in
            Item(pid: existing.pid, name: existing.name, value: updated.value)
        }
        #expect(unfrozenResolved == updatedLive)
    }

    @Test func metricCopyPayloadIncludesAttributeAndValue() {
        #expect(MetricCopyFeedback.formattedPayload(label: "空闲", value: "72 %") == "空闲: 72 %")
        #expect(MetricCopyFeedback.formattedPayload(label: "热压力", value: "75 °C · 正常") == "热压力: 75 °C · 正常")
    }
}
