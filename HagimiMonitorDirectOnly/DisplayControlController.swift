import AppKit
import Combine
import CoreGraphics
import OSLog
import SwiftUI

/// 直连渠道显示器控制的数据层:控制器(乐观盲写编排/轮询/抓握保护)、
/// 串行写入 worker、显示器模型与检测服务。UI 层在共享的
/// DisplaySection(两渠道单一实现),经 `#if DISPLAY_CONTROL` 引用本文件。

@MainActor
final class DisplayControlController: ObservableObject {
    @Published private(set) var displays: [ControlledDisplay] = []
    @Published private var pendingValues: [CGDirectDisplayID: [DisplayControlKind: Double]] = [:]

    private let service = DisplayControlService()
    private let worker = DisplayControlWorker.shared
    private let changeObserver = DisplayChangeObserver()
    private let audioOutputObserver = AudioOutputChangeObserver()
    private lazy var mediaKeyController = MediaKeyController()
    private var settingsObservation: AnyCancellable?
    private var keyboardLockObservation: AnyCancellable?
    private var fallbackValues: [CGDirectDisplayID: [DisplayControlKind: Double]] = [:]

    /// 抓握保护:记录用户最近一次设定的值与时刻。保护窗口内 `value(for:)` 优先返回
    /// 用户设定值,避免轮询回读(显示器四舍五入/延迟上报)把滑块瞬间弹回造成视觉跳变。
    private var recentlySetValues: [CGDirectDisplayID: [DisplayControlKind: (value: Double, at: Date)]] = [:]
    private static let gripWindow: TimeInterval = 4

    /// 门禁抑制窗口内被跳过的写入(最近一次目标值)。窗口结束后由
    /// `replaySuppressedWrites` 补发,否则用户设定值只停留在 UI 层,
    /// 显示器永远停在旧值。
    private var suppressedWrites: [ControlKey: Double] = [:]

    /// 面板打开且详情展开期间的轮询定时器。系统设置/其他 app 改亮度音量不会
    /// 产生任何通知,DDC 又是只能主动读取的哑协议,唯一能发现外部变化的办法就是
    /// 这段时间内持续轮询;收起或面板隐藏后停掉,避免空转占用 DDC 总线。
    private var pollTimerCancellable: AnyCancellable?
    private static let pollInterval: TimeInterval = 5

    init() {
        changeObserver.start { [weak self] in
            self?.refreshAsync()
        }
        // 默认音频输出设备变化(切 AirPods/内建扬声器/外接屏喇叭等)时,
        // 重新评估音量键接管策略。轻量刷新,不做全量 DDC 重扫。
        audioOutputObserver.start { [weak self] in
            self?.mediaKeyController.refresh()
        }
    }

    func attach(settings: MonitorSettings) {
        mediaKeyController.attach(controller: self, settings: settings)

        let merged = Publishers.Merge3(
            settings.$mediaKeyBrightnessEnabled.map { _ in () },
            settings.$mediaKeyVolumeEnabled.map { _ in () },
            settings.$mediaKeyShowOSD.map { _ in () }
        )
        .merge(with: mediaKeyController.permission.$isTrusted.map { _ in () })

        settingsObservation = merged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.mediaKeyController.refresh()
            }

        // 锁定状态变化时重评估媒体键接管:锁定期间停用媒体键 tap(避免
        // 重建插队绕过键盘锁),解锁后恢复。dropFirst:订阅时的初始值已由
        // 上方 attach 的 refresh 覆盖。
        keyboardLockObservation = QuickToolsStore.shared.$keyboardLocked
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.mediaKeyController.refresh()
            }
    }

    func setPolling(active: Bool) {
        guard active else {
            pollTimerCancellable?.cancel()
            pollTimerCancellable = nil
            return
        }
        guard pollTimerCancellable == nil else { return }
        pollTimerCancellable = Timer.publish(every: Self.pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshAsync()
            }
    }

    func refreshAsync() {
        let previousIDs = Set(displays.map { $0.id })
        worker.refresh(service: service) { detectedDisplays in
            DispatchQueue.main.async {
                AppLogger.ui.info("Display refresh completed, found \(detectedDisplays.count) displays")
                let detectedIDs = Set(detectedDisplays.map { $0.id })
                // 已移除的显示器:清理 worker 去重状态,避免同 ID 重新接入时
                // lastWrittenValues 残留导致首次写入被误跳过。
                // 同时重置 gamma 调光,避免对已断开的显示器残留 gamma 压暗。
                for removedID in previousIDs.subtracting(detectedIDs) {
                    self.worker.clearLastValues(displayID: removedID)
                    self.recentlySetValues[removedID] = nil
                    self.suppressedWrites = self.suppressedWrites.filter { $0.key.displayID != removedID }
                    GammaDimmingController.shared.reset(displayID: removedID)
                }
                self.displays = detectedDisplays
                for display in detectedDisplays {
                    self.seedFallbackValues(for: display)
                }
                // 抑制窗口已结束(change handler 在窗口结束后触发):补发被跳过的写入。
                self.replaySuppressedWrites()
                self.mediaKeyController.refresh()
            }
        }
    }

    func value(for control: DisplayControlKind, displayID: CGDirectDisplayID) -> Double {
        if let pendingValue = pendingValues[displayID]?[control] {
            return pendingValue
        }

        // 抓握保护窗口内优先返回用户设定值,防止轮询回读把滑块弹回。
        if let recent = recentlySetValues[displayID]?[control],
           Date().timeIntervalSince(recent.at) < Self.gripWindow {
            return recent.value
        }

        if let display = displays.first(where: { $0.id == displayID }) {
            return display.value(for: control)
        }

        return fallbackValues[displayID]?[control] ?? control.defaultValue
    }

    func setValueAsync(_ value: Double, for control: DisplayControlKind, displayID: CGDirectDisplayID) {
        let clampedValue = min(100, max(0, value))
        guard let display = displays.first(where: { $0.id == displayID }) else {
            AppLogger.ui.error("Display not found for setValue: \(displayID)")
            return
        }
        guard display.supports(control) else {
            AppLogger.ui.error("Display \(displayID) does not support control: \(control.storageKey, privacy: .public)")
            return
        }

        let key = ControlKey(displayID: displayID, control: control)
        pendingValues[displayID, default: [:]][control] = clampedValue
        recentlySetValues[displayID, default: [:]][control] = (clampedValue, Date())
        worker.setValue(clampedValue, for: key, display: display, service: service) { [weak self] result in
            Task { @MainActor in
                self?.handleWriteResult(result)
            }
        }
    }

    private func seedFallbackValues(for display: ControlledDisplay) {
        fallbackValues[display.id] = [
            .brightness: display.brightness,
            .volume: display.volume,
            .contrast: display.contrast
        ]
    }

    private func updateLocalValue(_ value: Double, for control: DisplayControlKind, displayID: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == displayID }) else {
            return
        }

        displays[index].setValue(value, for: control)
    }

    private func handleWriteResult(_ result: DisplayWriteResult) {
        let currentPendingValue = pendingValues[result.key.displayID]?[result.key.control]
        let isCurrentResult = currentPendingValue.map { abs($0 - result.value) < 0.001 } ?? false

        switch result.outcome {
        case .written, .skipped:
            // 乐观盲写模型:报文上总线(.written)或门禁抑制跳过(.skipped)都视为
            // 生效,对齐本地真值并刷新抓握窗口。不做写后回读,不可读的显示器不报错。
            // 差异只在持久化与重放:skipped 未真正落地,记录待窗口结束补发;written 已生效,清除待重放。
            if result.outcome == .skipped {
                suppressedWrites[result.key] = result.value
            } else {
                suppressedWrites[result.key] = nil
            }
            updateLocalValue(result.value, for: result.key.control, displayID: result.key.displayID)
            fallbackValues[result.key.displayID, default: [:]][result.key.control] = result.value
            recentlySetValues[result.key.displayID, default: [:]][result.key.control] = (result.value, Date())
            AppLogger.ui.debug("Write \(String(describing: result.outcome), privacy: .public) for display \(result.key.displayID), control: \(result.key.control.storageKey, privacy: .public)")
        case .busError:
            // 瞬时总线错误:绝不冒泡给用户、绝不翻转能力、绝不禁用控制,只做日志。
            // 滑块保持用户设定值,下次写入(或门禁解除后)自然重试。
            AppLogger.ui.error("Write bus error for display \(result.key.displayID), control: \(result.key.control.storageKey, privacy: .public)")
        }

        guard isCurrentResult else {
            return
        }

        pendingValues[result.key.displayID]?[result.key.control] = nil
        if pendingValues[result.key.displayID]?.isEmpty == true {
            pendingValues[result.key.displayID] = nil
        }
    }

    /// 补发门禁抑制窗口内被跳过的写入。由 `refreshAsync` 在窗口结束(change handler 触发)后调用;
    /// 只重放最近一次目标值,显示器已移除或不支持的控制直接丢弃。重放走正常 debounce 写路径。
    private func replaySuppressedWrites() {
        let pending = suppressedWrites
        guard !pending.isEmpty else { return }
        suppressedWrites.removeAll()
        for (key, value) in pending {
            guard let display = displays.first(where: { $0.id == key.displayID }),
                  display.supports(key.control) else {
                continue
            }
            AppLogger.ui.debug("Replaying suppressed write for display \(key.displayID), control: \(key.control.storageKey, privacy: .public)")
            setValueAsync(value, for: key.control, displayID: key.displayID)
        }
    }
}

private final class DisplayControlWorker {
    static let shared = DisplayControlWorker()

    private let queue = DispatchQueue(label: "hagimi.ddc.global", qos: .userInitiated)
    private var pendingWrites: [ControlKey: Double] = [:]
    private var lastWrittenValues: [ControlKey: Double] = [:]
    private var debounceTimers: [ControlKey: DispatchWorkItem] = [:]
    private let debounceInterval: DispatchTimeInterval = .milliseconds(150)

    func refresh(service: DisplayControlService, completion: @escaping ([ControlledDisplay]) -> Void) {
        queue.async {
            completion(service.displays())
        }
    }

    func setValue(
        _ value: Double,
        for key: ControlKey,
        display: ControlledDisplay,
        service: DisplayControlService,
        completion: @escaping (DisplayWriteResult) -> Void
    ) {
        queue.async {
            self.pendingWrites[key] = value

            self.debounceTimers[key]?.cancel()
            let timer = DispatchWorkItem { [service, display, key, completion] in
                guard let latestValue = self.pendingWrites.removeValue(forKey: key) else {
                    return
                }
                self.debounceTimers.removeValue(forKey: key)

                if let last = self.lastWrittenValues[key], abs(last - latestValue) < 0.001 {
                    completion(DisplayWriteResult(key: key, value: latestValue, outcome: .written))
                    return
                }

                let outcome = service.setValue(latestValue, for: key.control, display: display)
                if outcome.didWrite {
                    self.lastWrittenValues[key] = latestValue
                }
                completion(DisplayWriteResult(key: key, value: latestValue, outcome: outcome))
            }
            self.debounceTimers[key] = timer
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: timer)
        }
    }

    func clearLastValues(displayID: CGDirectDisplayID) {
        queue.async {
            for key in self.lastWrittenValues.keys where key.displayID == displayID {
                self.lastWrittenValues.removeValue(forKey: key)
            }
            for key in self.pendingWrites.keys where key.displayID == displayID {
                self.pendingWrites.removeValue(forKey: key)
            }
            // 只取消该显示器的 debounce timer,避免误伤其它正在拖动的显示器。
            let keysToCancel = self.debounceTimers.keys.filter { $0.displayID == displayID }
            for key in keysToCancel {
                self.debounceTimers[key]?.cancel()
                self.debounceTimers.removeValue(forKey: key)
            }
        }
    }
}

private nonisolated struct DisplayWriteResult {
    let key: ControlKey
    let value: Double
    let outcome: DisplayWriteOutcome
}

/// 乐观盲写的三态语义,取代裸 Bool。核心是**不再做写后回读校验**,因此不存在
/// "写成功但没执行"的 verified/unverified 区分——那本身就是徒增总线负担的旧模型。
/// - written:报文已成功上总线(ACK)。乐观视为生效,对齐本地真值并持久化。
/// - skipped:门禁抑制(睡眠/唤醒/重配置窗口)跳过本次写入。UI 仍显示用户设定值,
///   但**不**写入去重缓存/持久化,待窗口结束后的下一次写入真正落地。
/// - busError:重试后报文仍无法上总线(极少数窗口外 hang / 无服务 / 明确不支持)。
///   瞬时总线错误**绝不**冒泡给用户、绝不翻转能力,只做日志。
nonisolated enum DisplayWriteOutcome {
    case written
    case skipped
    case busError

    /// 报文是否已被显示器 ACK(用于决定是否更新去重缓存/持久化)。
    /// 仅 `.written` 为真:`.skipped` 未真正落地,`.busError` 未上总线。
    var didWrite: Bool { self == .written }
}

struct ControlledDisplay: Identifiable {
    let id: CGDirectDisplayID
    /// 检测阶段一次性算出的显示器类型,缓存于模型中。避免每次写入都重新
    /// classify(会触发 CoreDisplay 字典创建 + 原生亮度探测)造成拖动时的重复开销。
    let kind: DisplayKind
    /// 调光模式:hardware = DDC/DisplayServices 硬件背光;gamma = 软件调光兜底。
    /// DDC 无服务或显示器明确不支持时自动降级到 gamma,确保用户始终有亮度控制可用。
    let dimmingMode: DimmingMode
    let storageID: String
    let name: String
    let isBuiltIn: Bool
    var supportsBrightness: Bool
    var supportsVolume: Bool
    var supportsContrast: Bool
    var brightness: Double
    var volume: Double
    var contrast: Double

    func supports(_ control: DisplayControlKind) -> Bool {
        switch control {
        case .brightness:
            supportsBrightness
        case .volume:
            supportsVolume
        case .contrast:
            supportsContrast
        }
    }

    func value(for control: DisplayControlKind) -> Double {
        switch control {
        case .brightness:
            brightness
        case .volume:
            volume
        case .contrast:
            contrast
        }
    }

    mutating func setValue(_ value: Double, for control: DisplayControlKind) {
        switch control {
        case .brightness:
            brightness = value
        case .volume:
            volume = value
        case .contrast:
            contrast = value
        }
    }
}

nonisolated enum DisplayControlKind: Hashable {
    case brightness
    case volume
    case contrast

    var defaultValue: Double {
        switch self {
        case .brightness:
            50
        case .volume:
            40
        case .contrast:
            75
        }
    }

    var storageKey: String {
        switch self {
        case .brightness:
            "brightness"
        case .volume:
            "volume"
        case .contrast:
            "contrast"
        }
    }
}

private final class DisplayControlService {
    private let displayServices = DisplayServicesBridge()
    private let ddc = DisplayDDCBridge()
    private let classifier = DisplayClassifier()
    private let defaults = UserDefaults.standard

    func displays() -> [ControlledDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else {
            AppLogger.ui.error("CGGetOnlineDisplayList failed")
            return []
        }

        let displayIDs = Array(ids.prefix(Int(count)))
        AppLogger.ui.info("Detected \(displayIDs.count) online displays")
        ddc.refresh(displayIDs: displayIDs)

        let result = displayIDs.compactMap { id -> ControlledDisplay? in
            let kind = classifier.classify(displayID: id)

            if kind == .virtual || kind == .dummy || kind == .unsupported {
                return nil
            }

            let isBuiltIn = (kind == .builtIn)
            let useDisplayServices = (kind == .builtIn || kind == .appleNative)
            let name = displayName(for: id, isBuiltIn: isBuiltIn)
            let storageID = displayStorageID(for: id, name: name, isBuiltIn: isBuiltIn)

            let nativeBrightness = useDisplayServices ? displayServices.getBrightness(displayID: id) : nil
            let isDDC = (kind == .externalDDC)
            // 检测期探测:依据显示器应答的结果码判定能力(supported/unsupported/unknown),
            // 而非"读到才算支持"。unknown(只写型/暂时性丢包)保持乐观,仍显示、仍可写。
            let brightnessProbe = isDDC ? ddc.probe(.brightness, displayID: id) : nil
            let volumeProbe = isDDC ? ddc.probe(.volume, displayID: id) : nil
            let contrastProbe = isDDC ? ddc.probe(.contrast, displayID: id) : nil

            let storedBrightness = storedValue(for: .brightness, displayStorageID: storageID)
            let storedVolume = storedValue(for: .volume, displayStorageID: storageID)
            let storedContrast = storedValue(for: .contrast, displayStorageID: storageID)

            // 调光模式判定:DDC 有服务且未明确不支持 → hardware(乐观);
            // DDC 无服务或明确不支持 → gamma 软件调光兜底,确保用户始终有亮度控制。
            let useGammaDimming = isDDC && (!ddc.hasService(for: id) || brightnessProbe?.capability == .unsupported)
            let dimmingMode: DimmingMode = useGammaDimming ? .gamma : .hardware

            return ControlledDisplay(
                id: id,
                kind: kind,
                dimmingMode: dimmingMode,
                storageID: storageID,
                name: name,
                isBuiltIn: isBuiltIn,
                // gamma 模式下亮度始终可控(软件调光);hardware 模式仅当明确不支持才置灰。
                supportsBrightness: useGammaDimming
                    ? true
                    : (useDisplayServices
                        ? (nativeBrightness != nil)
                        : (brightnessProbe?.capability != .unsupported)),
                // gamma 模式只支持亮度,不支持音量/对比度。
                supportsVolume: useGammaDimming ? false : (isDDC && (volumeProbe?.capability != .unsupported)),
                supportsContrast: useGammaDimming ? false : (isDDC && (contrastProbe?.capability != .unsupported)),
                brightness: useGammaDimming
                    ? (storedBrightness ?? 100)
                    : (nativeBrightness.map { Double($0 * 100) }
                        ?? brightnessProbe?.value
                        ?? storedBrightness
                        ?? DisplayControlKind.brightness.defaultValue),
                volume: volumeProbe?.value
                    ?? storedVolume
                    ?? DisplayControlKind.volume.defaultValue,
                contrast: contrastProbe?.value
                    ?? storedContrast
                    ?? DisplayControlKind.contrast.defaultValue
            )
        }

        // dimmingMode 从 gamma 切回 hardware 时(如 DDC 服务恢复)清除残留的
        // gamma 调光,避免 reapplyAll 仍对该显示器叠加软件压暗(与硬件背光叠加过暗,
        // 且 hardware 写入路径不触碰 gamma 状态,用户调到 100% 也无法解除)。
        for display in result where display.dimmingMode == .hardware {
            GammaDimmingController.shared.reset(displayID: display.id)
        }
        // 先丢弃已断开显示器的调光残留,避免 reapplyAll 对离线显示器做无谓施加。
        GammaDimmingController.shared.resetDisconnected(onlineIDs: Set(result.map { $0.id }))

        // 睡眠/唤醒/显示器重配置后系统会重置 gamma 表,在每次检测结束时重新施加。
        GammaDimmingController.shared.reapplyAll()

        return result
    }

    func setValue(_ value: Double, for control: DisplayControlKind, display: ControlledDisplay) -> DisplayWriteOutcome {
        guard display.supports(control) else { return .busError }

        // Gamma 软件调光降级路径:DDC 不可用的显示器仍可调亮度(但仅亮度)。
        if display.dimmingMode == .gamma {
            guard control == .brightness else { return .busError }
            GammaDimmingController.shared.setDimming(percent: value, for: display.id)
            saveStoredValue(value, for: control, displayStorageID: display.storageID)
            return .written
        }

        // 使用检测阶段缓存的 kind,不再每次写入都重新分类(重复触发系统探测)。
        let useDisplayServices = (display.kind == .builtIn || display.kind == .appleNative)

        if useDisplayServices {
            switch control {
            case .brightness:
                return displayServices.setBrightness(displayID: display.id, value: Float(value / 100)) ? .written : .busError
            case .volume, .contrast:
                return .busError
            }
        }

        let outcome = ddc.write(value, for: control, displayID: display.id)
        if outcome.didWrite {
            saveStoredValue(value, for: control, displayStorageID: display.storageID)
        }
        return outcome
    }

    private func displayName(for id: CGDirectDisplayID, isBuiltIn: Bool) -> String {
        if let info = CoreDisplay_DisplayCreateInfoDictionary(id)?.takeRetainedValue() as? [String: Any],
           let localizedNames = info["DisplayProductName"] as? [String: String] {
            let name = localizedNames[Locale.current.identifier]
                ?? localizedNames["zh_CN"]
                ?? localizedNames["en_US"]
                ?? localizedNames.first?.value
            if let name {
                return name
            }
        }

        if isBuiltIn {
            return String(localized: "display.built-in-display")
        }

        let model = CGDisplayModelNumber(id)
        let externalDisplay = String(localized: "display.external-display")
        return model == 0 ? externalDisplay : "\(externalDisplay) \(model)"
    }

    private func displayStorageID(for id: CGDirectDisplayID, name: String, isBuiltIn: Bool) -> String {
        let vendor = CGDisplayVendorNumber(id)
        let model = CGDisplayModelNumber(id)
        let serial = CGDisplaySerialNumber(id)
        let role = isBuiltIn ? "builtIn" : "external"
        let sanitizedName = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(role).\(sanitizedName).\(vendor).\(model).\(serial)"
    }

    private func storedValue(for control: DisplayControlKind, displayStorageID: String) -> Double? {
        let key = storedValueKey(for: control, displayStorageID: displayStorageID)
        guard defaults.object(forKey: key) != nil else {
            return nil
        }
        return min(100, max(0, defaults.double(forKey: key)))
    }

    private func saveStoredValue(_ value: Double, for control: DisplayControlKind, displayStorageID: String) {
        // 静音(0)不覆盖持久化音量:跨会话解除静音需恢复到上次非零值,
        // 而非退化到兜底。亮度等 0 值是合法持久态,照常写入。
        if control == .volume, value <= 0 { return }
        defaults.set(min(100, max(0, value)), forKey: storedValueKey(for: control, displayStorageID: displayStorageID))
    }

    private func storedValueKey(for control: DisplayControlKind, displayStorageID: String) -> String {
        "displayControl.value.\(displayStorageID).\(control.storageKey)"
    }
}

private final class DisplayServicesBridge {
    func getBrightness(displayID: CGDirectDisplayID) -> Float? {
        var value: Float = -1
        let result = DisplayServicesGetBrightness(displayID, &value)
        guard result == 0, value >= 0 else {
            return nil
        }
        return min(1, max(0, value))
    }

    func setBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        let clampedValue = min(1, max(0, value))
        return DisplayServicesSetBrightness(displayID, clampedValue) == 0
    }
}
