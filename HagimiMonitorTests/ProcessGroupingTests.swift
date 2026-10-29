import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 进程归属分组规则：responsible pid 优先；Chromium 系 helper 放弃 responsibility 时
/// 只并入同一个 `.app` 包内的祖先，不跨 App 误并。
struct ProcessGroupingTests {
    private func groupKey(
        pid: pid_t,
        responsible: pid_t,
        parents: [pid_t: pid_t],
        paths: [pid_t: String]
    ) -> pid_t {
        processGroupKey(
            for: pid,
            responsiblePid: responsible,
            parentOf: { parents[$0] },
            pathOf: { paths[$0] ?? "" }
        )
    }

    @Test func validResponsiblePidWinsWithoutWalkingParents() {
        // Safari 的 WebContent：responsible 直接指向宿主，父进程是 launchd 也不影响。
        let paths: [pid_t: String] = [
            100: "/System/Applications/Safari.app/Contents/MacOS/Safari",
            200: "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
        ]
        #expect(groupKey(pid: 200, responsible: 100, parents: [200: 1, 100: 1], paths: paths) == 100)
    }

    @Test func disclaimedRendererMergesIntoContainingApp() {
        // Chromium 系浏览器的 renderer：responsible 指回自身，ppid 指向宿主 App。
        let paths: [pid_t: String] = [
            63937: "/Applications/ego lite.app/Contents/MacOS/ego lite",
            13061: "/Applications/ego lite.app/Contents/Frameworks/ego Framework.framework/Versions/A/Helpers/ego Helper (Renderer).app/Contents/MacOS/ego Helper (Renderer)",
        ]
        let parents: [pid_t: pid_t] = [13061: 63937, 63937: 1]
        #expect(groupKey(pid: 13061, responsible: 13061, parents: parents, paths: paths) == 63937)
    }

    @Test func zygoteChainResolvesToTopmostAncestorInSameBundle() {
        // renderer -> zygote helper -> 宿主，取包内最高的祖先，宿主的名称与图标才对得上。
        let paths: [pid_t: String] = [
            100: "/Applications/Foo.app/Contents/MacOS/Foo",
            200: "/Applications/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper",
            300: "/Applications/Foo.app/Contents/Frameworks/Foo Helper (Renderer).app/Contents/MacOS/Foo Helper (Renderer)",
        ]
        let parents: [pid_t: pid_t] = [300: 200, 200: 100, 100: 1]
        #expect(groupKey(pid: 300, responsible: 300, parents: parents, paths: paths) == 100)
    }

    @Test func separateAppUnderSameParentStaysIndependent() {
        // 被另一个 App 拉起的独立 App 不在同一个 `.app` 包内，不能并进父进程。
        let paths: [pid_t: String] = [
            53729: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT",
            53955: "/Users/me/.codex/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService",
        ]
        let parents: [pid_t: pid_t] = [53955: 53729, 53729: 1]
        #expect(groupKey(pid: 53955, responsible: 53955, parents: parents, paths: paths) == 53955)
    }

    @Test func orphanedHelperKeepsOwnGroup() {
        // 宿主退出后 ppid 变为 launchd，helper 不再并组，也不会并进 pid 1。
        let paths: [pid_t: String] = [
            200: "/Applications/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper",
        ]
        #expect(groupKey(pid: 200, responsible: 200, parents: [200: 1], paths: paths) == 200)
    }

    @Test func processOutsideAppBundleKeepsOwnGroup() {
        // 终端里跑的 node 没有可归属的 App 包，不能并进终端 App。
        let paths: [pid_t: String] = [
            300: "/opt/homebrew/bin/node",
            400: "/Applications/iTerm.app/Contents/MacOS/iTerm2",
        ]
        let parents: [pid_t: pid_t] = [300: 400, 400: 1]
        #expect(groupKey(pid: 300, responsible: 300, parents: parents, paths: paths) == 300)
    }

    @Test func bundleRootUsesOutermostApp() {
        #expect(
            appBundleRoot(of: "/Applications/Foo.app/Contents/Frameworks/Bar.app/Contents/MacOS/bar")
                == "/Applications/Foo.app/"
        )
        #expect(appBundleRoot(of: "/opt/homebrew/bin/node") == nil)
    }
}
