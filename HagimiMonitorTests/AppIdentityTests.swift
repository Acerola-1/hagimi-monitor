import Foundation
import Testing
@testable import HagimiMonitorDirect

/// A01：稳定身份区分同名应用、改写不拆历史、拿不到身份时明确标注。
struct AppIdentityTests {
    @Test func bundleIdentityIgnoresDisplayName() {
        let before = AppIdentity(kind: .bundle, stableKey: "com.example.App", displayName: "旧名称")
        let after = AppIdentity(kind: .bundle, stableKey: "com.example.App", displayName: "新名称")
        // 改名不改变主键，历史能延续。
        #expect(before.storageKey == after.storageKey)
        #expect(before.storageKey == "bundle:com.example.App")
    }

    @Test func sameDisplayNameDifferentBundlesStaySeparate() {
        let first = AppIdentity(kind: .bundle, stableKey: "com.vendor.one", displayName: "同名应用")
        let second = AppIdentity(kind: .bundle, stableKey: "com.vendor.two", displayName: "同名应用")
        #expect(first.storageKey != second.storageKey)
    }

    @Test func systemExecutableUsesPathNotName() {
        let identity = AppIdentity(
            kind: .systemExecutable,
            stableKey: "/usr/libexec/WindowServer",
            displayName: "WindowServer"
        )
        #expect(identity.storageKey == "systemExecutable:/usr/libexec/WindowServer")
        #expect(identity.isStableAcrossLaunches)
    }

    @Test func unresolvedIdentityIsMarkedAndNotStableAcrossLaunches() {
        let identity = AppIdentity(kind: .unresolved, stableKey: "pid-42", displayName: "未知进程")
        #expect(identity.storageKey == "unresolved:pid-42")
        // 会话键不能跨重启延续历史，避免把不同进程当成同一个应用。
        #expect(identity.isStableAcrossLaunches == false)
    }

    @Test func differentPIDsNeverShareAnIdentity() {
        let first = AppIdentity(kind: .unresolved, stableKey: "pid-42", displayName: "同名进程")
        let second = AppIdentity(kind: .unresolved, stableKey: "pid-77", displayName: "同名进程")
        #expect(first.storageKey != second.storageKey)
    }

    @Test func storageKeysDoNotCollideAcrossKinds() {
        // 同一字符串在两类身份下必须产生不同主键，否则系统进程与应用会互相覆盖。
        let asBundle = AppIdentity(kind: .bundle, stableKey: "com.example.x", displayName: "x")
        let asExecutable = AppIdentity(kind: .systemExecutable, stableKey: "com.example.x", displayName: "x")
        #expect(asBundle.storageKey != asExecutable.storageKey)
    }

    // MARK: - 旧名称映射

    @Test func legacyNameMapsOnlyWhenUnambiguous() {
        let processData = ReportProcessData(
            identities: [
                "bundle:com.example.Safari": ReportAppIdentity(appKey: "bundle:com.example.Safari", name: "Safari", iconPNG: nil),
                "bundle:com.example.Xcode": ReportAppIdentity(appKey: "bundle:com.example.Xcode", name: "Xcode", iconPNG: nil),
            ],
            dailyRows: [],
            batteryHistory: [],
            alerts: []
        )
        let aliases = ReportDataAggregator.identityAliases(processData: processData)
        // 旧库以显示名为主键的行会归并到身份键。
        #expect(aliases["Safari"] == "bundle:com.example.Safari")
        #expect(aliases["Xcode"] == "bundle:com.example.Xcode")
    }

    @Test func legacyNameWithConflictingIdentitiesIsNotMerged() {
        let processData = ReportProcessData(
            identities: [
                "bundle:com.vendor.one": ReportAppIdentity(appKey: "bundle:com.vendor.one", name: "同名应用", iconPNG: nil),
                "bundle:com.vendor.two": ReportAppIdentity(appKey: "bundle:com.vendor.two", name: "同名应用", iconPNG: nil),
            ],
            dailyRows: [],
            batteryHistory: [],
            alerts: []
        )
        let aliases = ReportDataAggregator.identityAliases(processData: processData)
        // 同名对应多个身份时不归并，宁可多一行也不合并错。
        #expect(aliases["同名应用"] == nil)
    }

    @Test func identityKeyItselfIsNotRemapped() {
        let processData = ReportProcessData(
            identities: [
                "bundle:com.example.App": ReportAppIdentity(appKey: "bundle:com.example.App", name: "bundle:com.example.App", iconPNG: nil),
            ],
            dailyRows: [],
            batteryHistory: [],
            alerts: []
        )
        let aliases = ReportDataAggregator.identityAliases(processData: processData)
        #expect(aliases.isEmpty)
    }

    @Test func resolverAlwaysProducesAKeyForUnknownProcess() {
        // 用一个几乎不可能存在的 pid 解析：必须仍返回带标记的可区分身份。
        let identity = AppIdentityResolver.resolve(pid: 999_999, name: "Ghost")
        #expect(identity.storageKey.isEmpty == false)
        #expect(identity.displayName == "Ghost")
        #expect(identity.kind != .bundle)
    }
}
