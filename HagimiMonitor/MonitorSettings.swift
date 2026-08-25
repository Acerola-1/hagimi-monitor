import Combine
import Foundation
import ServiceManagement
import SwiftUI

enum AppThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            String(localized: "theme.system")
        case .light:
            String(localized: "theme.light")
        case .dark:
            String(localized: "theme.dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum MonitorColorSchemePreference: String, CaseIterable, Identifiable {
    case vibrant
    case balanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vibrant:
            String(localized: "color-scheme.vibrant")
        case .balanced:
            String(localized: "color-scheme.balanced")
        }
    }
}

/// 内存卡片头部主显示指标:压力等级(默认)或使用率。
/// 仅交换显示位置,不影响 severity / 负载环等由使用率驱动的逻辑。
/// case 顺序即设置页分段选择器的展示顺序。
enum MemoryPrimaryMetricPreference: String, CaseIterable, Identifiable {
    case pressure
    case usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pressure:
            String(localized: "memory-primary-metric.pressure")
        case .usage:
            String(localized: "memory-primary-metric.usage")
        }
    }
}

final class MonitorSettings: ObservableObject {
    @Published var launchAtLogin: Bool = false
    @Published var themePreference: AppThemePreference = .system
    @Published var colorSchemePreference: MonitorColorSchemePreference = .vibrant
    @Published var ringSource: HaloRingSource = .combined
    @Published var menuBarDisplayMode: MenuBarDisplayMode = .ring
    @Published private(set) var menuBarMetricKinds: [MenuBarMetricKind] = MenuBarMetricKind.defaultSelection
    @Published var menuBarMetricLayoutStyle: MenuBarMetricLayoutStyle = .icon
    @Published var showBuiltInDisplays: Bool = true
    @Published var displayModuleVisible: Bool = false
    @Published var displayControlsExpandedByDefault: Bool = false
    @Published var displayBrightnessControlEnabled: Bool = true
    @Published var displayVolumeControlEnabled: Bool = true
    @Published var displayContrastControlEnabled: Bool = false
    @Published var mediaKeyBrightnessEnabled: Bool = false
    @Published var mediaKeyVolumeEnabled: Bool = false
    @Published var mediaKeyShowOSD: Bool = true
    @Published var showMemoryProcesses: Bool = true
    /// 各类 TOP 列表默认包含系统进程:WindowServer 等系统进程常是占用大头,
    /// 隐藏后列表常显得空。
    @Published var memoryShowSystemProcesses: Bool = true
    @Published var memoryPrimaryMetric: MemoryPrimaryMetricPreference = .pressure
    @Published var showCPUProcesses: Bool = true
    @Published var cpuShowSystemProcesses: Bool = true
    @Published var showGPUProcesses: Bool = true
    @Published var gpuShowSystemProcesses: Bool = true
    @Published var showDiskProcesses: Bool = true
    @Published var diskShowSystemProcesses: Bool = true
    @Published var showNetworkProcesses: Bool = true
    @Published var networkShowSystemProcesses: Bool = true
    /// 功率流图开关(Beta):电源模块展开区的功率流可视化,默认开启,双渠道(含沙盒)均可用。
    @Published var batteryShowPowerFlow: Bool = true
    /// 小工具(快捷功能)入口是否在面板中显示。
    @Published var quickToolsVisible: Bool = true
    /// 在工具浮层中显示的工具集合。集合由 QuickToolKind 驱动,新增工具只补枚举
    /// case 与本地化,存储/迁移/设置页/浮层自动跟随,无需逐处改动。
    @Published private(set) var visibleQuickTools: Set<QuickToolKind> = []
    @Published private(set) var visibleKinds: Set<MonitorKind> = []
    /// 呼出面板时默认展开的模块集合(逐模块设置,非全局开关)。
    @Published private(set) var defaultExpandedKinds: Set<MonitorKind> = []
    @Published private(set) var enabledMetrics: [MonitorKind: Set<String>] = [:]

    /// 钉住面板窗口位置持久化。
    @Published var pinnedPanelOriginX: Double? = nil
    @Published var pinnedPanelOriginY: Double? = nil

    private let defaults: UserDefaults
    private var isUpdatingLaunchAtLogin = false
    private var cancellables = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let themeRawValue = defaults.string(forKey: Keys.themePreference) ?? AppThemePreference.system.rawValue
        themePreference = AppThemePreference(rawValue: themeRawValue) ?? .system

        let colorSchemeRawValue = defaults.string(forKey: Keys.colorSchemePreference) ?? MonitorColorSchemePreference.vibrant.rawValue
        colorSchemePreference = MonitorColorSchemePreference(rawValue: colorSchemeRawValue) ?? .vibrant

        ringSource = .combined

        let menuBarDisplayModeRawValue = defaults.string(forKey: Keys.menuBarDisplayMode) ?? MenuBarDisplayMode.ring.rawValue
        menuBarDisplayMode = MenuBarDisplayMode(rawValue: menuBarDisplayModeRawValue) ?? .ring
        // 旧键仅存「图标/文字」两态前缀样式,其历史存储值作为迁移兜底,避免升级后静默重置为默认值。
        let legacyPrefixStyleRawValue = defaults.string(forKey: Keys.legacyMenuBarMetricPrefixStyle)
        let layoutStyleRawValue = defaults.string(forKey: Keys.menuBarMetricLayoutStyle) ?? legacyPrefixStyleRawValue ?? MenuBarMetricLayoutStyle.icon.rawValue
        menuBarMetricLayoutStyle = MenuBarMetricLayoutStyle(rawValue: layoutStyleRawValue) ?? .icon
        menuBarMetricKinds = MonitorSettings.validatedMenuBarMetrics(
            defaults.array(forKey: Keys.menuBarMetricKinds) as? [String]
        )

        showBuiltInDisplays = defaults.object(forKey: Keys.showBuiltInDisplays) as? Bool ?? true
        // 默认值分渠道:Direct 的控制区是 Beta 选择性能力,默认关;
        // App Store 的信息行默认展示。两渠道 Bundle ID 不同,UserDefaults 独立。
        #if DISPLAY_CONTROL
        displayModuleVisible = defaults.object(forKey: Keys.displayModuleVisible) as? Bool ?? false
        #else
        displayModuleVisible = defaults.object(forKey: Keys.displayModuleVisible) as? Bool ?? true
        #endif
        displayControlsExpandedByDefault = defaults.object(forKey: Keys.displayControlsExpandedByDefault) as? Bool ?? false
        displayBrightnessControlEnabled = defaults.object(forKey: Keys.displayBrightnessControlEnabled) as? Bool ?? true
        displayVolumeControlEnabled = defaults.object(forKey: Keys.displayVolumeControlEnabled) as? Bool ?? true
        displayContrastControlEnabled = defaults.object(forKey: Keys.displayContrastControlEnabled) as? Bool ?? false
        showMemoryProcesses = defaults.object(forKey: Keys.showMemoryProcesses) as? Bool ?? true
        memoryShowSystemProcesses = defaults.object(forKey: Keys.memoryShowSystemProcesses) as? Bool ?? true
        let memoryPrimaryMetricRawValue = defaults.string(forKey: Keys.memoryPrimaryMetric) ?? MemoryPrimaryMetricPreference.pressure.rawValue
        memoryPrimaryMetric = MemoryPrimaryMetricPreference(rawValue: memoryPrimaryMetricRawValue) ?? .pressure
        showCPUProcesses = defaults.object(forKey: Keys.showCPUProcesses) as? Bool ?? true
        cpuShowSystemProcesses = defaults.object(forKey: Keys.cpuShowSystemProcesses) as? Bool ?? true
        showGPUProcesses = defaults.object(forKey: Keys.showGPUProcesses) as? Bool ?? true
        gpuShowSystemProcesses = defaults.object(forKey: Keys.gpuShowSystemProcesses) as? Bool ?? true
        showDiskProcesses = defaults.object(forKey: Keys.showDiskProcesses) as? Bool ?? true
        diskShowSystemProcesses = defaults.object(forKey: Keys.diskShowSystemProcesses) as? Bool ?? true
        showNetworkProcesses = defaults.object(forKey: Keys.showNetworkProcesses) as? Bool ?? true
        networkShowSystemProcesses = defaults.object(forKey: Keys.networkShowSystemProcesses) as? Bool ?? true
        batteryShowPowerFlow = defaults.object(forKey: Keys.batteryShowPowerFlow) as? Bool ?? true
        quickToolsVisible = defaults.object(forKey: Keys.quickToolsVisible) as? Bool ?? true
        if let storedTools = defaults.array(forKey: Keys.visibleQuickTools) as? [String] {
            let stored = Set(storedTools.compactMap { key in
                QuickToolKind.allCases.first { $0.storageKey == key }
            })
            // 一次性迁移:各版本新增的工具 case 不在老存量里,升级后会被当成
            // 「用户已隐藏」。按引入版本登记(见 introducedByVersion),只补
            // 新工具,不复活用户手动关掉的老工具;之后手动开关正常读写。
            if !defaults.bool(forKey: Keys.quickToolsMigrated) {
                let introducedByVersion: [QuickToolKind] = []
                let merged = stored.union(introducedByVersion)
                if merged != stored {
                    visibleQuickTools = merged
                    defaults.set(merged.map(\.storageKey), forKey: Keys.visibleQuickTools)
                }
                defaults.set(true, forKey: Keys.quickToolsMigrated)
            } else {
                visibleQuickTools = stored
            }
        } else {
            visibleQuickTools = Set(QuickToolKind.allCases)
        }

        pinnedPanelOriginX = defaults.object(forKey: Keys.pinnedPanelOriginX) as? Double
        pinnedPanelOriginY = defaults.object(forKey: Keys.pinnedPanelOriginY) as? Double
        mediaKeyBrightnessEnabled = defaults.object(forKey: Keys.mediaKeyBrightnessEnabled) as? Bool ?? false
        mediaKeyVolumeEnabled = defaults.object(forKey: Keys.mediaKeyVolumeEnabled) as? Bool ?? false
        mediaKeyShowOSD = defaults.object(forKey: Keys.mediaKeyShowOSD) as? Bool ?? true

        if let storedKinds = defaults.array(forKey: Keys.visibleKinds) as? [String] {
            var kinds = storedKinds.compactMap(MonitorKind.init(rawValue:))
            // 一次性迁移:老用户的已存储列表是风扇可开关之前写入的,不含 fan;
            // 不补会被当成「用户已隐藏」,升级后风扇行凭空消失。
            // 补上后立即回写存储——迁移标记只挡一次,不回写的话下次启动
            // 会按旧列表(无 fan)加载,风扇行再次消失。
            if !defaults.bool(forKey: Keys.fanVisibilityMigrated) {
                if !kinds.contains(.fan) {
                    kinds.append(.fan)
                    defaults.set(kinds.map(\.rawValue), forKey: Keys.visibleKinds)
                }
                defaults.set(true, forKey: Keys.fanVisibilityMigrated)
            }
            if !defaults.bool(forKey: Keys.bluetoothVisibilityMigrated) {
                if !kinds.contains(.bluetooth) {
                    kinds.append(.bluetooth)
                    defaults.set(kinds.map(\.rawValue), forKey: Keys.visibleKinds)
                }
                defaults.set(true, forKey: Keys.bluetoothVisibilityMigrated)
            }
            visibleKinds = Set(kinds)
        } else {
            visibleKinds = Set(MonitorKind.userVisibleCases)
        }

        if let storedExpanded = defaults.array(forKey: Keys.defaultExpandedKinds) as? [String] {
            defaultExpandedKinds = Set(storedExpanded.compactMap(MonitorKind.init(rawValue:)))
        }

        var loadedMetrics: [MonitorKind: Set<String>] = [:]
        for kind in MonitorKind.allCases {
            let key = Keys.enabledMetricsPrefix + kind.rawValue
            if let stored = defaults.array(forKey: key) as? [String] {
                let migrated = migrateMetrics(stored, for: kind)
                loadedMetrics[kind] = Set(migrated)
            }
        }
        // 一次性迁移:migrateMetrics 对存量只做交集,后来新增的默认开指标
        // (热压力/P-E 核/压缩内存/SMART/Wi-Fi 系列等)不在旧存量里,升级后
        // 会被当成「用户已关」。这里把各模块默认开的指标并回存量并立即回写;
        // 之后用户的手动开关走正常读写,不再被本迁移覆盖。
        if !defaults.bool(forKey: Keys.metricsDefaultOnMigrated) {
            for kind in MonitorKind.allCases where loadedMetrics[kind] != nil {
                // 用户明确关闭全部指标(存储为空数组)的模块是合法全关状态,
                // 不被默认补齐迁移复活。
                let stored = defaults.array(forKey: Keys.enabledMetricsPrefix + kind.rawValue) as? [String] ?? []
                guard !stored.isEmpty else { continue }
                var merged = loadedMetrics[kind] ?? []
                let defaultsForKind = defaultMetricIds(for: kind)
                merged.formUnion(defaultsForKind)
                if merged != loadedMetrics[kind] {
                    loadedMetrics[kind] = merged
                    defaults.set(Array(merged), forKey: Keys.enabledMetricsPrefix + kind.rawValue)
                }
            }
            defaults.set(true, forKey: Keys.metricsDefaultOnMigrated)
        }
        // 一次性迁移:电池模块新增的电压/电流/容量三项默认开指标不在存量
        // 列表里,升级后会被当成「用户已关」。只把这三项并入电池存量并回写,
        // 不重跑全量并回,避免复活用户手动关过的其他指标。
        if !defaults.bool(forKey: Keys.batteryElectricalMetricsMigrated) {
            if var merged = loadedMetrics[.battery], !merged.isEmpty {
                merged.formUnion(["voltage", "current", "capacity"])
                if merged != loadedMetrics[.battery] {
                    loadedMetrics[.battery] = merged
                    defaults.set(Array(merged), forKey: Keys.enabledMetricsPrefix + MonitorKind.battery.rawValue)
                }
            }
            defaults.set(true, forKey: Keys.batteryElectricalMetricsMigrated)
        }
        enabledMetrics = loadedMetrics

        launchAtLogin = SMAppService.mainApp.status == .enabled

        setupBindings()
    }

    func isVisible(_ kind: MonitorKind) -> Bool {
        visibleKinds.contains(kind)
    }

    func setVisible(_ isVisible: Bool, for kind: MonitorKind) {
        if isVisible {
            visibleKinds.insert(kind)
        } else {
            visibleKinds.remove(kind)
        }
    }

    func isQuickToolVisible(_ kind: QuickToolKind) -> Bool {
        visibleQuickTools.contains(kind)
    }

    func setQuickToolVisible(_ isVisible: Bool, for kind: QuickToolKind) {
        if isVisible {
            visibleQuickTools.insert(kind)
        } else {
            visibleQuickTools.remove(kind)
            // 全部工具隐藏时「在面板中显示」自动关闭:留一个只有空浮层的
            // 工具入口没有意义,联动避免出现「按钮在、点开无内容」的状态。
            if visibleQuickTools.isEmpty {
                quickToolsVisible = false
            }
        }
    }

    func isExpandedByDefault(_ kind: MonitorKind) -> Bool {
        defaultExpandedKinds.contains(kind)
    }

    func setExpandedByDefault(_ isOn: Bool, for kind: MonitorKind) {
        if isOn {
            defaultExpandedKinds.insert(kind)
        } else {
            defaultExpandedKinds.remove(kind)
        }
    }

    func isMetricEnabled(_ id: String, for kind: MonitorKind) -> Bool {
        if let stored = enabledMetrics[kind] {
            return stored.contains(id)
        }
        return kind.availableMetrics.first(where: { $0.id == id })?.isDefault ?? false
    }

    func canEnableMetric(_ id: String, for kind: MonitorKind) -> Bool {
        return true
    }

    func setMetric(_ id: String, enabled: Bool, for kind: MonitorKind) {
        var current = enabledMetrics[kind] ?? defaultMetricIds(for: kind)
        if enabled {
            current.insert(id)
        } else {
            current.remove(id)
        }
        enabledMetrics[kind] = current
    }

    func resetMetrics(for kind: MonitorKind) {
        enabledMetrics[kind] = defaultMetricIds(for: kind)
    }

    func isMenuBarMetricSelected(_ kind: MenuBarMetricKind) -> Bool {
        menuBarMetricKinds.contains(kind)
    }

    func canSelectMenuBarMetric(_ kind: MenuBarMetricKind) -> Bool {
        isMenuBarMetricSelected(kind) || menuBarMetricKinds.count < MenuBarMetricKind.maximumSelectionCount
    }

    func setMenuBarMetric(_ kind: MenuBarMetricKind, selected: Bool) {
        var current = menuBarMetricKinds
        if selected {
            guard !current.contains(kind), current.count < MenuBarMetricKind.maximumSelectionCount else { return }
            current.append(kind)
        } else {
            current.removeAll { $0 == kind }
        }
        menuBarMetricKinds = current.isEmpty ? MenuBarMetricKind.defaultSelection : current
    }

    func moveMenuBarMetric(_ kind: MenuBarMetricKind, direction: Int) {
        guard let index = menuBarMetricKinds.firstIndex(of: kind) else { return }
        let target = index + direction
        guard menuBarMetricKinds.indices.contains(target) else { return }
        menuBarMetricKinds.swapAt(index, target)
    }

    /// 保存钉住面板窗口位置。
    func savePinnedPanelOrigin(_ origin: CGPoint) {
        pinnedPanelOriginX = origin.x
        pinnedPanelOriginY = origin.y
    }

    /// 读取钉住面板窗口位置,无历史值返回 nil。
    var pinnedPanelOrigin: CGPoint? {
        guard let x = pinnedPanelOriginX, let y = pinnedPanelOriginY else { return nil }
        return CGPoint(x: x, y: y)
    }

    private static func validatedMenuBarMetrics(_ rawValues: [String]?) -> [MenuBarMetricKind] {
        guard let rawValues else {
            return MenuBarMetricKind.defaultSelection
        }

        var result: [MenuBarMetricKind] = []
        for rawValue in rawValues {
            // 旧值里可能残留当前版本不可用的指标(如沙盒版的 CPU 温度);风扇指标
            // 保留(不按 hasFan 过滤),无风扇机迁到有风扇机时自动恢复。
            guard let kind = MenuBarMetricKind(rawValue: rawValue),
                  !result.contains(kind) else {
                continue
            }
            result.append(kind)
            if result.count == MenuBarMetricKind.maximumSelectionCount {
                break
            }
        }

        return result.isEmpty ? MenuBarMetricKind.defaultSelection : result
    }

    private func migrateMetrics(_ ids: [String], for kind: MonitorKind) -> [String] {
        // 旧 metric ID 为本地化名称(现为英文 key),映射需同时覆盖中文和英文旧 key,
        // 确保跨语言升级不丢失设置。
        let mapping: [String: String] = {
            switch kind {
            case .cpu:
                return [
                    // 中文旧 key
                    "系统": "system", "用户": "user", "闲置": "idle", "启动时间": "uptime", "温度": "temperature",
                    // 英文旧 key
                    "System": "system", "User": "user", "Idle": "idle", "Uptime": "uptime", "Temperature": "temperature",
                ]
            case .gpu:
                return [
                    "GPU内存": "gpu-memory", "已分配": "allocated", "渲染": "render", "分块": "tiler", "温度": "temperature",
                    "GPU Memory": "gpu-memory", "Allocated": "allocated", "Render": "render", "Tiler": "tiler", "Temperature": "temperature",
                ]
            case .memory:
                return [
                    "已用": "used", "压力": "pressure", "交换已用": "swap-used", "总量": "total",
                    "Used": "used", "Pressure": "pressure", "Swap Used": "swap-used", "Total": "total",
                ]
            case .storage:
                return [
                    "已用": "used", "可用": "free", "总量": "total",
                    "Used": "used", "Free": "free", "Total": "total",
                ]
            case .network:
                return [
                    "IP 地址": "ipv4", "上传": "upload", "下载": "download",
                    "IP Address": "ipv4", "Upload": "upload", "Download": "download",
                ]
            case .battery:
                return [
                    "充电功率": "charging-power", "健康度": "health", "循环数": "cycle-count", "温度": "temperature", "适配器": "adapter", "功耗": "power",
                    "Charging Power": "charging-power", "Health": "health", "Cycle Count": "cycle-count", "Temperature": "temperature", "Adapter": "adapter", "Power": "power",
                ]
            case .fan:
                // 风扇行无子指标,展开区由 FanList 直接渲染;此处无需迁移映射。
                return [:]
            case .bluetooth:
                // 蓝牙行无子指标,展开区由 BluetoothDeviceList 直接渲染;此处无需迁移映射。
                return [:]
            }
        }()

        var result = Set<String>()
        for id in ids {
            if let mapped = mapping[id] {
                result.insert(mapped)
            } else {
                result.insert(id)
            }
        }

        let availableIds = Set(kind.availableMetrics.map { $0.id })
        let filtered = result.intersection(availableIds)

        if filtered.isEmpty {
            // 用户主动关闭全部指标(存储为空数组)是合法持久态,保持为空;
            // 仅当存储非空但过滤后为空(历史失效指标)时才回退默认。
            guard !ids.isEmpty else { return [] }
            return Array(defaultMetricIds(for: kind))
        }

        return Array(filtered)
    }

    private func defaultMetricIds(for kind: MonitorKind) -> Set<String> {
        Set(kind.availableMetrics.filter { $0.isDefault }.map { $0.id })
    }

    private func setupBindings() {
        $launchAtLogin
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persistLaunchAtLogin(newValue)
            }
            .store(in: &cancellables)

        $themePreference
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.rawValue, forKey: Keys.themePreference)
            }
            .store(in: &cancellables)

        $colorSchemePreference
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.rawValue, forKey: Keys.colorSchemePreference)
            }
            .store(in: &cancellables)

        $ringSource
            .dropFirst()
            .sink { [weak self] _ in
                self?.persist(HaloRingSource.combined.rawValue, forKey: Keys.ringSource)
            }
            .store(in: &cancellables)

        $menuBarDisplayMode
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.rawValue, forKey: Keys.menuBarDisplayMode)
            }
            .store(in: &cancellables)

        $menuBarMetricKinds
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.map(\.rawValue), forKey: Keys.menuBarMetricKinds)
            }
            .store(in: &cancellables)

        $menuBarMetricLayoutStyle
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.rawValue, forKey: Keys.menuBarMetricLayoutStyle)
            }
            .store(in: &cancellables)

        $showBuiltInDisplays
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showBuiltInDisplays)
            }
            .store(in: &cancellables)

        $displayModuleVisible
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.displayModuleVisible)
            }
            .store(in: &cancellables)

        $displayControlsExpandedByDefault
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.displayControlsExpandedByDefault)
            }
            .store(in: &cancellables)

        $displayBrightnessControlEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.displayBrightnessControlEnabled)
            }
            .store(in: &cancellables)

        $displayVolumeControlEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.displayVolumeControlEnabled)
            }
            .store(in: &cancellables)

        $displayContrastControlEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.displayContrastControlEnabled)
            }
            .store(in: &cancellables)

        $mediaKeyBrightnessEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.mediaKeyBrightnessEnabled)
            }
            .store(in: &cancellables)

        $mediaKeyVolumeEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.mediaKeyVolumeEnabled)
            }
            .store(in: &cancellables)

        $mediaKeyShowOSD
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.mediaKeyShowOSD)
            }
            .store(in: &cancellables)

        $showMemoryProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showMemoryProcesses)
            }
            .store(in: &cancellables)

        $memoryShowSystemProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.memoryShowSystemProcesses)
            }
            .store(in: &cancellables)

        $memoryPrimaryMetric
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.rawValue, forKey: Keys.memoryPrimaryMetric)
            }
            .store(in: &cancellables)

        $showCPUProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showCPUProcesses)
            }
            .store(in: &cancellables)

        $cpuShowSystemProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.cpuShowSystemProcesses)
            }
            .store(in: &cancellables)

        $showGPUProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showGPUProcesses)
            }
            .store(in: &cancellables)

        $gpuShowSystemProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.gpuShowSystemProcesses)
            }
            .store(in: &cancellables)

        $showDiskProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showDiskProcesses)
            }
            .store(in: &cancellables)

        $diskShowSystemProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.diskShowSystemProcesses)
            }
            .store(in: &cancellables)

        $showNetworkProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showNetworkProcesses)
            }
            .store(in: &cancellables)

        $networkShowSystemProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.networkShowSystemProcesses)
            }
            .store(in: &cancellables)

        $batteryShowPowerFlow
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.batteryShowPowerFlow)
            }
            .store(in: &cancellables)

        $quickToolsVisible
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.quickToolsVisible)
            }
            .store(in: &cancellables)

        $visibleQuickTools
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.map(\.storageKey), forKey: Keys.visibleQuickTools)
            }
            .store(in: &cancellables)

        $visibleKinds
            .dropFirst()
            .sink { [weak self] newValue in
                let values = newValue.map(\.rawValue)
                self?.persist(values, forKey: Keys.visibleKinds)
            }
            .store(in: &cancellables)

        $defaultExpandedKinds
            .dropFirst()
            .sink { [weak self] newValue in
                let values = newValue.map(\.rawValue)
                self?.persist(values, forKey: Keys.defaultExpandedKinds)
            }
            .store(in: &cancellables)

        $enabledMetrics
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self else { return }
                for (kind, ids) in newValue {
                    let key = Keys.enabledMetricsPrefix + kind.rawValue
                    self.persist(Array(ids), forKey: key)
                }
            }
            .store(in: &cancellables)

        $pinnedPanelOriginX
            .dropFirst()
            .sink { [weak self] newValue in
                if let newValue {
                    self?.persist(newValue, forKey: Keys.pinnedPanelOriginX)
                } else {
                    self?.defaults.removeObject(forKey: Keys.pinnedPanelOriginX)
                }
            }
            .store(in: &cancellables)

        $pinnedPanelOriginY
            .dropFirst()
            .sink { [weak self] newValue in
                if let newValue {
                    self?.persist(newValue, forKey: Keys.pinnedPanelOriginY)
                } else {
                    self?.defaults.removeObject(forKey: Keys.pinnedPanelOriginY)
                }
            }
            .store(in: &cancellables)

    }

    private func persist<T>(_ value: T, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    private func persistLaunchAtLogin(_ newValue: Bool) {
        guard !isUpdatingLaunchAtLogin else { return }
        updateLaunchAtLogin(newValue)
    }

    private func updateLaunchAtLogin(_ newValue: Bool) {
        do {
            if newValue {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            isUpdatingLaunchAtLogin = true
            launchAtLogin.toggle()
            isUpdatingLaunchAtLogin = false
        }
    }
}

private enum Keys {
    static let themePreference = "settings.themePreference"
    static let colorSchemePreference = "settings.colorSchemePreference"
    static let ringSource = "settings.ringSource"
    static let menuBarDisplayMode = "settings.menuBar.displayMode"
    static let menuBarMetricKinds = "settings.menuBar.metricKinds"
    static let menuBarMetricLayoutStyle = "settings.menuBar.metricLayoutStyle"
    /// 遗留键名:仅用于读取迁移,不写入。
    static let legacyMenuBarMetricPrefixStyle = "settings.menuBar.metricPrefixStyle"
    static let defaultExpandedKinds = "settings.panel.defaultExpandedKinds"
    static let displayModuleVisible = "settings.display.moduleVisible"
    static let displayControlsExpandedByDefault = "settings.display.expandedByDefault"
    static let showBuiltInDisplays = "settings.display.showBuiltInDisplays"
    static let displayBrightnessControlEnabled = "settings.display.brightnessControlEnabled"
    static let displayVolumeControlEnabled = "settings.display.volumeControlEnabled"
    static let displayContrastControlEnabled = "settings.display.contrastControlEnabled"
    static let mediaKeyBrightnessEnabled = "settings.mediaKey.brightnessEnabled"
    static let mediaKeyVolumeEnabled = "settings.mediaKey.volumeEnabled"
    static let mediaKeyShowOSD = "settings.mediaKey.showOSD"
    static let showMemoryProcesses = "settings.memory.showProcesses"
    static let memoryShowSystemProcesses = "settings.memory.showSystemProcesses"
    static let memoryPrimaryMetric = "settings.memory.primaryMetric"
    static let showCPUProcesses = "settings.cpu.showProcesses"
    static let cpuShowSystemProcesses = "settings.cpu.showSystemProcesses"
    static let showGPUProcesses = "settings.gpu.showProcesses"
    static let gpuShowSystemProcesses = "settings.gpu.showSystemProcesses"
    static let showDiskProcesses = "settings.disk.showProcesses"
    static let diskShowSystemProcesses = "settings.disk.showSystemProcesses"
    static let showNetworkProcesses = "settings.network.showProcesses"
    static let networkShowSystemProcesses = "settings.network.showSystemProcesses"
    static let batteryShowPowerFlow = "settings.battery.showPowerFlow"
    static let quickToolsVisible = "settings.quickTools.visible"
    static let visibleQuickTools = "settings.quickTools.visibleKinds"
    /// 一次性迁移标记:小工具新增工具 case 时,把新工具并回老用户的已启用集合
    /// (语义同 fanVisibilityMigrated:缺省会补,用户手动关过的不复活)。
    static let quickToolsMigrated = "settings.quickToolsMigrated"
    static let visibleKinds = "settings.visibleKinds"
    /// 一次性迁移标记:风扇模块从「硬件自动门控」升级为「用户可开关」时,
    /// 给老用户的已存储可见列表补上 fan(否则会被当作「用户已隐藏」)。
    static let fanVisibilityMigrated = "settings.fanVisibilityMigrated"
    /// 一次性迁移标记:蓝牙模块新增时,给老用户的已存储可见列表补上 bluetooth,
    /// 语义同 fanVisibilityMigrated。
    static let bluetoothVisibilityMigrated = "settings.bluetoothVisibilityMigrated"
    static let metricsDefaultOnMigrated = "settings.metricsDefaultOnMigrated"
    /// 一次性迁移标记:电池模块新增电压/电流/容量默认开指标时,给存量用户
    /// 的电池指标列表补上这三项(语义同 metricsDefaultOnMigrated,但只限电池三项)。
    static let batteryElectricalMetricsMigrated = "settings.batteryElectricalMetricsMigrated"
    static let enabledMetricsPrefix = "settings.enabledMetrics."
    static let pinnedPanelOriginX = "settings.pinnedPanel.originX"
    static let pinnedPanelOriginY = "settings.pinnedPanel.originY"
}
