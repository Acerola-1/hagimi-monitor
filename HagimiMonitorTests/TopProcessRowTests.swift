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
}
