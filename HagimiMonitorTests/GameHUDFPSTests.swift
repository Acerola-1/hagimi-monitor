import Foundation
import AppKit
import SwiftUI
import Combine
import Testing
@testable import HagimiMonitorDirect

struct GameHUDFPSTests {

    // MARK: - JSON 流解析测试

    @Test func extractJSONObjectsHandlesMultipleAndPartialObjects() {
        var buffer = "  { \"a\": 1 } \n { \"b\": \"nested { brace } in string\" } \n { \"partial\": true"
        let extracted = MetalPerfTraceMeter.extractJSONObjects(from: &buffer)
        #expect(extracted.count == 2)
        #expect(extracted[0].contains("\"a\": 1"))
        #expect(extracted[1].contains("nested { brace } in string"))
        #expect(buffer.trimmingCharacters(in: .whitespacesAndNewlines) == "{ \"partial\": true")

        // 拼接补齐
        buffer += ", \"done\": 123 }"
        let secondPass = MetalPerfTraceMeter.extractJSONObjects(from: &buffer)
        #expect(secondPass.count == 1)
        #expect(secondPass[0].contains("\"done\": 123"))
        #expect(buffer.isEmpty)
    }

    // MARK: - Sample 解析测试

    @Test func parseSampleExtractsPresentedAndIntervalStats() {
        let sampleJSON = """
        {
          "PID": 9999,
          "Process": "TestGame",
          "Layers": [
            {
              "Layer Name": "MainSurface",
              "Performance Stats": {
                "Presented Frame Stats": {
                  "FPS": 60.12,
                  "Frame Count": 60
                },
                "Frame-On-Glass Interval Stats": {
                  "Min (ms)": 15.1,
                  "Average (ms)": 16.63,
                  "Max (ms)": 22.4,
                  "StdDev (ms)": 1.25,
                  "Count": 60,
                  "Total (ms)": 997.8
                }
              }
            }
          ]
        }
        """

        let sample = MetalPerfTraceMeter.parseSample(from: sampleJSON)
        #expect(sample != nil)
        #expect(sample?.frameCount == 60)
        #expect(abs((sample?.fps ?? 0) - 60.12) < 0.01)
        #expect(abs((sample?.avgMs ?? 0) - 16.63) < 0.01)
        #expect(abs((sample?.stdDevMs ?? 0) - 1.25) < 0.01)
        #expect(abs((sample?.maxMs ?? 0) - 22.4) < 0.01)
        #expect(abs((sample?.minMs ?? 0) - 15.1) < 0.01)
    }

    // MARK: - 1% Low 算法验证

    @Test func onePercentLowReflectsSmoothFramerate() {
        // 平稳 60 FPS: 5 秒平稳采样, 帧间隔平均 16.66ms, 标准差 0.8ms, 最大帧时间 18.5ms
        let samples = (0..<5).map { i in
            MetalPerfTraceMeter.SecondSample(
                timestamp: Double(i),
                fps: 60.0,
                frameCount: 60,
                avgMs: 16.66,
                stdDevMs: 0.8,
                maxMs: 18.5,
                minMs: 15.0,
                totalMs: 1000.0
            )
        }

        let stats = MetalPerfTraceMeter.computeFPSStats(from: samples)
        #expect(stats != nil)
        #expect(abs((stats?.averageFPS ?? 0) - 60.0) < 0.5)
        #expect(abs((stats?.currentFPS ?? 0) - 60.0) < 0.5)
        #expect((stats?.onePercentLow ?? 0) >= 52.0 && (stats?.onePercentLow ?? 0) <= 60.0)
    }

    @Test func onePercentLowDropsOnSevereStutter() {
        // 9 秒平稳 60 FPS + 1 秒偶发 100ms 严重掉帧
        var samples = (0..<9).map { i in
            MetalPerfTraceMeter.SecondSample(
                timestamp: Double(i),
                fps: 60.0,
                frameCount: 60,
                avgMs: 16.66,
                stdDevMs: 0.8,
                maxMs: 18.5,
                minMs: 15.0,
                totalMs: 1000.0
            )
        }
        samples.append(
            MetalPerfTraceMeter.SecondSample(
                timestamp: 9.0,
                fps: 50.0,
                frameCount: 50,
                avgMs: 20.0,
                stdDevMs: 15.0,
                maxMs: 100.0,
                minMs: 15.0,
                totalMs: 1000.0
            )
        )

        let stats = MetalPerfTraceMeter.computeFPSStats(from: samples)
        #expect(stats != nil)
        #expect((stats?.averageFPS ?? 0) > 55.0) // 平均帧率仍受大多数平稳秒维持
        #expect((stats?.onePercentLow ?? 0) < 35.0) // 1% Low 灵敏反映偶发卡顿掉帧
    }

    @Test func onePercentLowHandlesHighRefreshRate120FPS() {
        // 120 FPS 高刷场景: 帧间隔平均 8.33ms, 最大 9.5ms
        let samples = (0..<10).map { i in
            MetalPerfTraceMeter.SecondSample(
                timestamp: Double(i),
                fps: 120.0,
                frameCount: 120,
                avgMs: 8.33,
                stdDevMs: 0.4,
                maxMs: 9.5,
                minMs: 7.5,
                totalMs: 1000.0
            )
        }

        let stats = MetalPerfTraceMeter.computeFPSStats(from: samples)
        #expect(stats != nil)
        #expect(abs((stats?.averageFPS ?? 0) - 120.0) < 0.5)
        #expect((stats?.onePercentLow ?? 0) > 105.0 && (stats?.onePercentLow ?? 0) <= 120.0)
    }

    @MainActor
    @Test func frameMeterIsIdempotentForSameTarget() {
        let meter = GameHUDFrameMeter()
        let currentApp = NSRunningApplication.current
        meter.start(target: currentApp)
        // 再次传入相同 app: 不应重启或崩溃
        meter.start(target: currentApp)
        meter.stop()
    }

    // MARK: - GameHUDViewContract 尺寸契约

    @Test func viewContractExpandsForFPSAndOnePercentLow() {
        let baseIDs: Set<GameHUDMetricID> = [.cpuUsage, .memoryUsed]
        let baseSize = GameHUDViewContract.size(for: baseIDs, fpsStats: nil)

        // 仅开启 FPS
        let withFPSIDs: Set<GameHUDMetricID> = [.fps, .cpuUsage, .memoryUsed]
        let fpsStats = GameHUDFPSStats(currentFPS: 60, averageFPS: 60, onePercentLow: 55)
        let withFPSSize = GameHUDViewContract.size(for: withFPSIDs, fpsStats: fpsStats)
        #expect(withFPSSize.height > baseSize.height)

        // 同时开启 FPS 与 1% Low
        let withBothIDs: Set<GameHUDMetricID> = [.fps, .onePercentLow, .cpuUsage, .memoryUsed]
        let withBothSize = GameHUDViewContract.size(for: withBothIDs, fpsStats: fpsStats)
        #expect(withBothSize.height > withFPSSize.height)
    }

    @Test func viewContractHeightIsStableRegardlessOfDataAvailability() {
        let ids: Set<GameHUDMetricID> = [.fps, .averageFPS, .onePercentLow, .cpuUsage]
        let sizeWithoutStats = GameHUDViewContract.size(for: ids, fpsStats: nil)
        let stats = GameHUDFPSStats(currentFPS: 60.0, averageFPS: 59.8, onePercentLow: 51.2)
        let sizeWithStats = GameHUDViewContract.size(for: ids, fpsStats: stats)
        #expect(sizeWithoutStats == sizeWithStats, "面板高度应一次性确定，无论数据是否就绪，不发生二次拉伸")
    }

    // MARK: - Catalog 契约测试

    @Test func catalogContainsFPSAndOnePercentLowInDirect() {
        let entries = GameHUDMetricCatalog.availableEntries()
        #expect(entries.contains(where: { $0.id == .fps }))
        #expect(entries.contains(where: { $0.id == .averageFPS }))
        #expect(entries.contains(where: { $0.id == .onePercentLow }))
        #expect(entries.contains(where: { $0.id == .frameTime }))
        #expect(entries.contains(where: { $0.id == .fanSpeed }))
        #expect(entries.contains(where: { $0.id == .gpuPower }))
        #expect(entries.contains(where: { $0.id == .cpuPower }))

        let defaults = GameHUDMetricCatalog.defaultEnabledIDs()
        #expect(defaults.contains(.fps))
        #expect(defaults.contains(.averageFPS))
        #expect(defaults.contains(.onePercentLow))
        #expect(defaults.contains(.frameTime))
    }

    // MARK: - 本地化完整性测试

    @Test func localizationHasFPSAndOnePercentLowKeys() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let xcstringsURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HagimiMonitor/Localizable.xcstrings")

        let data = try Data(contentsOf: xcstringsURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = json?["strings"] as? [String: Any]

        let requiredKeys = [
            "gamehud.view.fps",
            "gamehud.view.average-fps",
            "gamehud.view.one-percent-low",
            "gamehud.view.frame-time",
            "gamehud.view.fps-unit %lld",
            "gamehud.view.fps-unit-decimal %@",
            "gamehud.metric.fps",
            "gamehud.metric.average-fps",
            "gamehud.metric.one-percent-low",
            "gamehud.metric.frame-time",
            "gamehud.metric.fan-speed",
            "gamehud.metric.cpu-power",
            "gamehud.metric.gpu-power"
        ]

        for key in requiredKeys {
            let item = strings?[key] as? [String: Any]
            #expect(item != nil, "Missing key in xcstrings: \(key)")
            let localizations = item?["localizations"] as? [String: Any]
            for lang in ["en", "zh-Hans"] {
                let unit = (localizations?[lang] as? [String: Any])?["stringUnit"] as? [String: Any]
                let val = unit?["value"] as? String
                #expect(val != nil && !val!.isEmpty, "Missing translation for \(key) in \(lang)")
            }
        }
    }

    @Test func probeRealHardwareCapabilities() {
        let smc = SMCReader()
        #expect(smc != nil, "SMCReader should be present on real hardware")
    }

    @Test func quickToolsDecoupledFromGameHUD() throws {
        // 1. 小工具枚举仅包含键盘锁定、防休眠、不息屏
        let kinds = QuickToolKind.allCases
        #expect(kinds.count == 3)
        #expect(kinds.contains(.keyboardLock))
        #expect(kinds.contains(.systemAwake))
        #expect(kinds.contains(.displayAwake))

        // 2. 检查 "gamehud.settings.master-enabled" 本地化
        let testFileURL = URL(fileURLWithPath: #filePath)
        let xcstringsURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HagimiMonitor/Localizable.xcstrings")

        let data = try Data(contentsOf: xcstringsURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = json?["strings"] as? [String: Any]
        let item = strings?["gamehud.settings.master-enabled"] as? [String: Any]
        #expect(item != nil)
        let loc = item?["localizations"] as? [String: Any]
        let zhVal = ((loc?["zh-Hans"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        let enVal = ((loc?["en"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        #expect(zhVal == "游戏监测")
        #expect(enVal == "Game Monitoring")

        // 3. MonitorSettings 默认开启游戏监测
        let tempDefaults = UserDefaults(suiteName: "test.hagimi.gamehud.defaults.\(UUID().uuidString)")!
        let settings = MonitorSettings(defaults: tempDefaults)
        #expect(settings.gameHUDMasterEnabled == true)
    }

    // MARK: - P0 修复验证: 迁移与 Generation 计数

    @Test func cleanInstallMarksV2MigratedAndDoesNotRestoreRemovedMetricsOnReboot() {
        let suite = "test.hagimi.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        // 1. 全新安装首次启动
        let settings1 = MonitorSettings(defaults: defaults)
        #expect(defaults.bool(forKey: "settings.gameHUD.newMetricsV2Migrated") == true)
        #expect(settings1.gameHUDEnabledMetricIDs.contains(.averageFPS))
        #expect(settings1.gameHUDEnabledMetricIDs.contains(.frameTime))

        // 2. 用户主动取消勾选 averageFPS 和 frameTime
        settings1.setGameHUDMetric(.averageFPS, enabled: false)
        settings1.setGameHUDMetric(.frameTime, enabled: false)
        #expect(!settings1.gameHUDEnabledMetricIDs.contains(.averageFPS))
        #expect(!settings1.gameHUDEnabledMetricIDs.contains(.frameTime))

        // 3. 模拟应用重启，重新读取偏好
        let settings2 = MonitorSettings(defaults: defaults)
        #expect(!settings2.gameHUDEnabledMetricIDs.contains(.averageFPS), "重启后不应再次强制塞入 averageFPS")
        #expect(!settings2.gameHUDEnabledMetricIDs.contains(.frameTime), "重启后不应再次强制塞入 frameTime")
    }

    @Test func legacyV1StoreMigratesAverageFPSOnceAndRespectsUserRemoval() {
        let suite = "test.hagimi.migration.v1.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        // 模拟旧版存储: 仅存有 fps 和 cpuUsage，未跑过 V2 迁移
        defaults.set(["fps", "cpuUsage"], forKey: "settings.gameHUD.enabledMetrics")
        defaults.set(true, forKey: "settings.gameHUD.fpsMigrated")

        // 首次加载: 触发 V2 迁移，补充 averageFPS 与新指标
        let settings1 = MonitorSettings(defaults: defaults)
        #expect(settings1.gameHUDEnabledMetricIDs.contains(.averageFPS))
        #expect(settings1.gameHUDEnabledMetricIDs.contains(.frameTime))

        // 用户随后取消勾选 averageFPS
        settings1.setGameHUDMetric(.averageFPS, enabled: false)
        #expect(!settings1.gameHUDEnabledMetricIDs.contains(.averageFPS))

        // 再次重启
        let settings2 = MonitorSettings(defaults: defaults)
        #expect(!settings2.gameHUDEnabledMetricIDs.contains(.averageFPS), "已完成迁移的存量配置重启时不应重复回填 averageFPS")
    }

    @MainActor
    @Test func frameMeterGenerationIncrementsMonotonically() {
        let meter = GameHUDFrameMeter()
        let currentApp = NSRunningApplication.current

        #expect(meter.currentGeneration == 0)

        meter.start(target: currentApp)
        #expect(meter.currentGeneration == 1)

        meter.stop()
        #expect(meter.currentGeneration == 0)

        // 再次启动: generation 应递增为 2，而不是恒等于 1
        meter.start(target: currentApp)
        #expect(meter.currentGeneration == 2)

        meter.stop()
        meter.start(target: currentApp)
        #expect(meter.currentGeneration == 3)
        meter.stop()
    }

    // MARK: - P2 / P3 规范与健壮性测试

    @Test func snapshotEqualityComparesReadingsOnlyAndIgnoresDate() {
        let readingA = GameHUDReading(metricID: "fps", kind: .gpu, value: "60 FPS", percent: nil)
        let snapshot1 = GameHUDSnapshot(readings: [readingA], date: Date(timeIntervalSince1970: 1000))
        let snapshot2 = GameHUDSnapshot(readings: [readingA], date: Date(timeIntervalSince1970: 2000))
        #expect(snapshot1 == snapshot2, "时间戳不同但读数相同的快照应判定为相等，确保 publishIfChanged 抑制无效重绘")

        let readingB = GameHUDReading(metricID: "fps", kind: .gpu, value: "59 FPS", percent: nil)
        let snapshot3 = GameHUDSnapshot(readings: [readingB], date: Date(timeIntervalSince1970: 1000))
        #expect(snapshot1 != snapshot3, "读数不同时应判定为不相等")
    }

    @Test func quickToolTintHexUnification() {
        #expect(MonitorPalette.quickToolTintHex == 0xA855F7)
        let palette = MonitorPalette(preference: .vibrant, colorScheme: .dark)
        #expect(palette.quickToolTint == Color(hex: MonitorPalette.quickToolTintHex))
    }

    @MainActor
    @Test func snapshotProviderSubscriberSyncAccounting() {
        let store = MonitorStore()
        let provider = GameHUDSnapshotProvider(store: store)
        #expect(provider.activeSubscribers == 0)

        var cancellable: AnyCancellable? = provider.snapshotPublisher
            .sink { _ in }

        // 必须同步增加，无异步延迟
        #expect(provider.activeSubscribers == 1)

        cancellable?.cancel()
        cancellable = nil
        // 取消后必须同步归零
        #expect(provider.activeSubscribers == 0)
    }

    @Test func isLikelyGameIdentifiesSteamAndEpicPaths() {
        let steamGameURL = URL(fileURLWithPath: "/Users/test/Library/Application Support/Steam/steamapps/common/Hades/Hades.app")
        #expect(GameHUDGameScanner.isLikelyGame(appURL: steamGameURL, bundleID: "com.SupergiantGames.Hades") == true)

        let epicGameURL = URL(fileURLWithPath: "/Users/test/Library/Application Support/Epic Games/Celeste/Celeste.app")
        #expect(GameHUDGameScanner.isLikelyGame(appURL: epicGameURL, bundleID: "com.MattMakesGames.Celeste") == true)

        let safariURL = URL(fileURLWithPath: "/Applications/Safari.app")
        #expect(GameHUDGameScanner.isLikelyGame(appURL: safariURL, bundleID: "com.apple.Safari") == false)

        let nilURL: URL? = nil
        #expect(GameHUDGameScanner.isLikelyGame(appURL: nilURL, bundleID: "some.random.app") == false)
    }

    @MainActor
    @Test func metalTraceMeterStopCleansUpAllState() {
        let meter = MetalPerfTraceMeter()
        meter.stop()
        #expect(meter.currentPID == nil)
        #expect(meter.hasReceivedValidSample == false)
        #expect(meter.stats == nil)
    }
}

