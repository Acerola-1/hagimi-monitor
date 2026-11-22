import AppKit
import Testing
@testable import HagimiMonitorDirect

@Suite("Menu bar status summary & appearance")
struct MenuBarStatusSummaryTests {

    @Test("Tooltip and accessibility value include rounded percentages, core level, and memory pressure")
    func formatsCombinedAndSubsystemBreakdown() {
        let normal = MenuBarStatusSummary(
            combinedLoad: 24.6,
            coreLevel: .normal,
            cpuUsage: 18.4,
            gpuUsage: 31.6,
            memoryPressure: .normal,
            showsAlert: false,
            showsHUDBadge: false
        )
        #expect(normal.roundedCombined == 25)
        #expect(normal.roundedCPU == 18)
        #expect(normal.roundedGPU == 32)
        #expect(normal.tooltipText.contains("25%"))
        #expect(normal.tooltipText.contains("18%"))
        #expect(normal.tooltipText.contains("32%"))
        #expect(normal.tooltipText.contains(String(localized: "menu-bar-ring.level.normal")))
        #expect(normal.tooltipText.contains(String(localized: "memory-pressure.normal")))
        #expect(normal.tooltipText.components(separatedBy: "\n").count == 2)
        #expect(normal.accessibilityValue.contains("25%"))
        #expect(normal.accessibilityValue.contains("18%"))
        #expect(normal.accessibilityValue.contains("32%"))

        let busy = MenuBarStatusSummary(
            combinedLoad: 64.0,
            coreLevel: .busy,
            cpuUsage: 68.0,
            gpuUsage: 42.0,
            memoryPressure: .warning,
            showsAlert: false,
            showsHUDBadge: false
        )
        #expect(busy.tooltipText.contains(String(localized: "menu-bar-ring.level.busy")))
        #expect(busy.tooltipText.contains(String(localized: "memory-pressure.warning")))
        #expect(busy.accessibilityValue.contains(String(localized: "menu-bar-ring.level.busy")))
        #expect(busy.accessibilityValue.contains(String(localized: "memory-pressure.warning")))
    }

    @Test("Out-of-range inputs are clamped and optional badge lines appear cleanly")
    func clampsValuesAndAppendsActiveBadges() {
        let stressed = MenuBarStatusSummary(
            combinedLoad: 140.0,
            coreLevel: .stressed,
            cpuUsage: -5.0,
            gpuUsage: .nan,
            memoryPressure: .critical,
            showsAlert: true,
            showsHUDBadge: true
        )
        #expect(stressed.roundedCombined == 100)
        #expect(stressed.roundedCPU == 0)
        #expect(stressed.roundedGPU == 0)

        let lines = stressed.tooltipText.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].contains("100%"))
        #expect(lines[0].contains(String(localized: "menu-bar-ring.level.stressed")))
        #expect(lines[1].contains(String(localized: "memory-pressure.critical")))
        #expect(lines[2].contains(String(localized: "menu-bar-ring.tooltip.alert")))
        #expect(lines[2].contains(String(localized: "menu-bar-ring.tooltip.hud")))
        #expect(stressed.accessibilityValue.contains(String(localized: "menu-bar-ring.tooltip.alert")))
        #expect(stressed.accessibilityValue.contains(String(localized: "menu-bar-ring.tooltip.hud")))

        let unknownMemory = MenuBarStatusSummary(
            combinedLoad: 10,
            coreLevel: .normal,
            cpuUsage: 10,
            gpuUsage: 5,
            memoryPressure: .unknown,
            showsAlert: true,
            showsHUDBadge: false
        )
        #expect(unknownMemory.tooltipText.contains(String(localized: "memory-pressure.unknown")))
        #expect(unknownMemory.tooltipText.contains(String(localized: "menu-bar-ring.tooltip.alert")))
        #expect(!unknownMemory.tooltipText.contains(String(localized: "menu-bar-ring.tooltip.hud")))
    }

    @Test("NSAppearance classifies standard and high-contrast light/dark appearances")
    func appearanceClassificationCoversStandardAndHighContrast() throws {
        let aqua = try #require(NSAppearance(named: .aqua))
        let vibrantLight = try #require(NSAppearance(named: .vibrantLight))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))
        let vibrantDark = try #require(NSAppearance(named: .vibrantDark))

        #expect(!aqua.isDark)
        #expect(!vibrantLight.isDark)
        #expect(darkAqua.isDark)
        #expect(vibrantDark.isDark)

        // NSAppearance(named:) 会把高对比度名字退化为常规外观，故高对比度名称直接校验纯判定函数。
        let cases: [(NSAppearance.Name, dark: Bool, highContrast: Bool)] = [
            (.aqua, false, false),
            (.vibrantLight, false, false),
            (.darkAqua, true, false),
            (.vibrantDark, true, false),
            (.accessibilityHighContrastAqua, false, true),
            (.accessibilityHighContrastVibrantLight, false, true),
            (.accessibilityHighContrastDarkAqua, true, true),
            (.accessibilityHighContrastVibrantDark, true, true)
        ]

        for entry in cases {
            #expect(NSAppearance.isDark(appearanceName: entry.0) == entry.dark)
            #expect(NSAppearance.isHighContrast(appearanceName: entry.0) == entry.highContrast)
        }
        #expect(!NSAppearance.isDark(appearanceName: nil))
        #expect(!NSAppearance.isHighContrast(appearanceName: nil))
    }
}
