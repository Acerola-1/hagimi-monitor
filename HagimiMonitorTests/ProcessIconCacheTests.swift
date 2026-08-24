import Testing
import AppKit
@testable import HagimiMonitorDirect

@Suite("ProcessIconCache downscaling & caching")
struct ProcessIconCacheTests {

    /// 使用一个必然不存在对应 NSRunningApplication 的 pid,强制走「按路径取图 + 降采样」分支,
    /// 使测试结果只取决于路径,稳定可复现。/bin/ls 在所有 macOS 上恒存在。
    private let bogusPID: pid_t = .max
    private let existingPath = "/bin/ls"

    @Test("Downscaled icon reports 16pt logical size")
    func logicalSizeIs16() throws {
        let icon = try #require(ProcessIconCache.icon(forPID: bogusPID, path: existingPath))
        #expect(icon.size == NSSize(width: 16, height: 16))
    }

    @Test("Underlying bitmap is downscaled to a small representation")
    func bitmapIsDownscaled() throws {
        let icon = try #require(ProcessIconCache.icon(forPID: bogusPID, path: existingPath))
        let rep = try #require(icon.representations.first)
        // 目标为 16pt@2x = 32px。远小于系统 App 图标常见的 512/1024px 源 rep,
        // 证明底层大位图确实被丢弃、只保留降采样后的小位图。
        #expect(rep.pixelsWide <= 64)
        #expect(rep.pixelsHigh <= 64)
    }

    // 注:不断言两次调用返回同一 NSImage 实例。ProcessIconCache 使用 NSCache,
    // 其条目可在任意时刻(尤其并行测试的内存压力下)被系统丢弃,`===` 不受保证——
    // 这种自动回收正是内存敏感场景所需的特性。缓存命中属于 CPU 侧优化,不影响正确性,
    // 故此处只验证「降采样 + 稳定输出」这一核心内存收益,不对缓存命中做时序断言。
    @Test("Repeated calls stay stable and downscaled")
    func repeatedCallsStayDownscaled() throws {
        let a = try #require(ProcessIconCache.icon(forPID: bogusPID, path: existingPath))
        let b = try #require(ProcessIconCache.icon(forPID: bogusPID, path: existingPath))
        #expect(a.size == NSSize(width: 16, height: 16))
        #expect(b.size == NSSize(width: 16, height: 16))
        #expect((b.representations.first?.pixelsWide ?? .max) <= 64)
    }

    @Test("Empty path with no running app yields no icon")
    func emptyPathNoApp() {
        // bogus pid 无对应 App,path 为空 → 无来源,返回 nil,视图侧回退到占位图标。
        let icon = ProcessIconCache.icon(forPID: bogusPID, path: "")
        #expect(icon == nil)
    }
}

@Suite("MonitorStore process sampling gating")
struct MonitorStoreProcessGatingTests {

    @Test("Only expanded AND enabled kinds are sampled")
    func intersectsExpandedAndEnabled() {
        #expect(
            MonitorStore.activeProcessKinds(expanded: [.cpu, .memory], enabled: [.cpu, .network]) == [.cpu]
        )
    }

    @Test("Collapsed panel (nothing expanded) samples nothing")
    func nothingExpandedSamplesNothing() {
        #expect(
            MonitorStore.activeProcessKinds(expanded: [], enabled: [.cpu, .memory, .storage, .network]).isEmpty
        )
    }

    @Test("Expanded kind with its list disabled is not sampled")
    func expandedButDisabledSkipped() {
        #expect(
            MonitorStore.activeProcessKinds(expanded: [.storage], enabled: []).isEmpty
        )
    }
}
