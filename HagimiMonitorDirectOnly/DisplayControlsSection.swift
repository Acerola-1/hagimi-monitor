import AppKit
import Combine
import CoreGraphics
import OSLog
import SwiftUI

struct DisplayControlsSection: View {
    @ObservedObject var settings: MonitorSettings
    @StateObject private var controller = DisplayControlController()
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    private let expansionAnimation = Animation.smooth(duration: 0.22)

    var body: some View {
        let palette = MonitorPalette(
            preference: settings.colorSchemePreference,
            colorScheme: colorScheme
        )
        let tint = palette.displayTint
        let visibleDisplays = controller.displays
                .filter { settings.showBuiltInDisplays || !$0.isBuiltIn }
                .sorted { $0.isBuiltIn && !$1.isBuiltIn }
        let hasControls = settings.displayBrightnessControlEnabled
            || settings.displayVolumeControlEnabled
            || settings.displayContrastControlEnabled

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.callout.weight(.semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
                    .frame(width: 18)

                Text(String(localized: "kind.display") + ":")
                    .monitorPanelMetricLabelFont()
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)

                Text(summary(for: visibleDisplays, hasControls: hasControls))
                    .monitorPanelRoundedFont(weight: .semibold)
                    .foregroundStyle(palette.valueText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.captionText)
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(expansionAnimation, value: isExpanded)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(expansionAnimation) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                detailContent(
                    visibleDisplays: visibleDisplays,
                    hasControls: hasControls,
                    palette: palette,
                    tint: tint
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
                .transition(.detailDisclosure)
            }
        }
        .onAppear {
            controller.attach(settings: settings)
            controller.refreshAsync()
        }
        .animation(expansionAnimation, value: isExpanded)
        .glassEffect(.regular.tint(palette.displayGlassTint), in: .rect(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func detailContent(
        visibleDisplays: [ControlledDisplay],
        hasControls: Bool,
        palette: MonitorPalette,
        tint: Color
    ) -> some View {
        if !hasControls {
            DisplayEmptyState(text: String(localized: "display.no-controls"), palette: palette)
        } else if visibleDisplays.isEmpty {
            DisplayEmptyState(text: settings.showBuiltInDisplays ? String(localized: "display.no-displays") : String(localized: "display.no-external-displays"), palette: palette)
        } else {
            VStack(spacing: 8) {
                Rectangle()
                    .fill(palette.displaySeparator)
                    .frame(height: 1)
                    .padding(.leading, 28)

                ForEach(Array(visibleDisplays.enumerated()), id: \.element.id) { index, display in
                    if index > 0 {
                        Rectangle()
                            .fill(palette.displaySeparator.opacity(0.72))
                            .frame(height: 1)
                            .padding(.leading, 28)
                    }

                    DisplayControlGroup(
                        display: display,
                        settings: settings,
                        controller: controller,
                        palette: palette,
                        tint: tint
                    )
                }
            }
        }
    }

    private func summary(for displays: [ControlledDisplay], hasControls: Bool) -> String {
        guard hasControls else {
            return String(localized: "display.controls-disabled")
        }

        let externalCount = displays.filter { !$0.isBuiltIn }.count
        let unitCount = String(localized: "display.unit-count")
        let countPart = unitCount.isEmpty ? "\(displays.count)" : "\(displays.count) \(unitCount)"
        if externalCount > 0 {
            let unitExternal = String(localized: "display.unit-external")
            return "\(countPart) · \(unitExternal) \(externalCount)"
        }
        return countPart
    }
}

private extension AnyTransition {
    static var detailDisclosure: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .opacity
        )
    }
}

private struct DisplayControlGroup: View {
    let display: ControlledDisplay
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var controller: DisplayControlController
    let palette: MonitorPalette
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(display.name)
                        .monitorPanelCaptionFont(.footnote, weight: .semibold)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                        .help(display.name)

                    Spacer(minLength: 8)

                    Text(display.isBuiltIn ? String(localized: "display.built-in") : String(localized: "display.external"))
                        .monitorPanelRoundedFont(.caption2, weight: .semibold)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(palette.displayBadgeFill)
                        }
                }

                VStack(spacing: 7) {
                    if settings.displayBrightnessControlEnabled {
                        DisplayControlSlider(
                            label: String(localized: "settings.brightness"),
                            systemImage: "sun.max",
                            value: binding(for: .brightness),
                            isEnabled: display.supports(.brightness),
                            palette: palette,
                            tint: tint
                        )
                    }

                    if settings.displayVolumeControlEnabled {
                        DisplayControlSlider(
                            label: String(localized: "settings.volume"),
                            systemImage: "speaker.wave.2",
                            value: binding(for: .volume),
                            isEnabled: display.supports(.volume),
                            palette: palette,
                            tint: tint
                        )
                    }

                    if settings.displayContrastControlEnabled {
                        DisplayControlSlider(
                            label: String(localized: "settings.contrast"),
                            systemImage: "circle.lefthalf.filled",
                            value: binding(for: .contrast),
                            isEnabled: display.supports(.contrast),
                            palette: palette,
                            tint: tint
                        )
                    }
                }
            }
        }
        .padding(.leading, 28)
    }

    private func binding(for control: DisplayControlKind) -> Binding<Double> {
        Binding(
            get: { controller.value(for: control, displayID: display.id) },
            set: { controller.setValueAsync($0, for: control, displayID: display.id) }
        )
    }
}

private struct DisplayControlSlider: View {
    let label: String
    let systemImage: String
    @Binding var value: Double
    let isEnabled: Bool
    let palette: MonitorPalette
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isEnabled ? tint : palette.captionText)
                .frame(width: 14)

            Text(label)
                .monitorPanelCaptionFont(.caption2)
                .foregroundStyle(isEnabled ? palette.secondaryText : palette.captionText)
                .frame(width: 34, alignment: .leading)

            Slider(value: $value, in: 0...100, step: 1)
                .tint(tint)
                .controlSize(.small)
                .disabled(!isEnabled)

            Text("\(Int(value.rounded()))%")
                .monitorPanelRoundedFont(.caption2, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(isEnabled ? palette.secondaryText : palette.captionText)
                .frame(width: 34, alignment: .trailing)
        }
        .opacity(isEnabled ? 1 : 0.48)
    }
}

private struct DisplayEmptyState: View {
    let text: String
    let palette: MonitorPalette

    var body: some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(palette.displaySeparator)
                .frame(height: 1)
                .padding(.leading, 28)

            Text(text)
                .monitorPanelCaptionFont(.caption2)
                .foregroundStyle(palette.captionText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 28)
        }
    }
}

@MainActor
final class DisplayControlController: ObservableObject {
    @Published private(set) var displays: [ControlledDisplay] = []
    @Published private var pendingValues: [CGDirectDisplayID: [DisplayControlKind: Double]] = [:]

    private let service = DisplayControlService()
    private let worker = DisplayControlWorker.shared
    private let changeObserver = DisplayChangeObserver()
    private lazy var mediaKeyController = MediaKeyController()
    private var settingsObservation: AnyCancellable?
    private var fallbackValues: [CGDirectDisplayID: [DisplayControlKind: Double]] = [:]

    init() {
        changeObserver.start { [weak self] in
            self?.refreshAsync()
        }
    }

    func attach(settings: MonitorSettings) {
        mediaKeyController.attach(controller: self, settings: settings)

        let merged = Publishers.Merge5(
            settings.$mediaKeyBrightnessEnabled.map { _ in () },
            settings.$mediaKeyVolumeEnabled.map { _ in () },
            settings.$mediaKeyShowOSD.map { _ in () },
            settings.$mediaKeyFineScaleBrightness.map { _ in () },
            settings.$mediaKeyFineScaleVolume.map { _ in () }
        )
        .merge(with: mediaKeyController.permission.$isTrusted.map { _ in () })

        settingsObservation = merged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.mediaKeyController.refresh()
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
                for removedID in previousIDs.subtracting(detectedIDs) {
                    self.worker.clearLastValues(displayID: removedID)
                }
                self.displays = detectedDisplays
                for display in detectedDisplays {
                    self.seedFallbackValues(for: display)
                }
                self.mediaKeyController.refresh()
            }
        }
    }

    func value(for control: DisplayControlKind, displayID: CGDirectDisplayID) -> Double {
        if let pendingValue = pendingValues[displayID]?[control] {
            return pendingValue
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

        if result.success {
            updateLocalValue(result.value, for: result.key.control, displayID: result.key.displayID)
            fallbackValues[result.key.displayID, default: [:]][result.key.control] = result.value
            AppLogger.ui.debug("Write succeeded for display \(result.key.displayID), control: \(result.key.control.storageKey, privacy: .public)")
        } else {
            AppLogger.ui.error("Write failed for display \(result.key.displayID), control: \(result.key.control.storageKey, privacy: .public)")
            if isCurrentResult {
                markControlUnsupported(result.key.control, displayID: result.key.displayID)
            }
        }

        guard isCurrentResult else {
            return
        }

        pendingValues[result.key.displayID]?[result.key.control] = nil
        if pendingValues[result.key.displayID]?.isEmpty == true {
            pendingValues[result.key.displayID] = nil
        }
    }

    private func markControlUnsupported(_ control: DisplayControlKind, displayID: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == displayID }) else {
            return
        }

        displays[index].setSupported(false, for: control)
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
                    completion(DisplayWriteResult(key: key, value: latestValue, success: true))
                    return
                }

                let success = service.setValue(latestValue, for: key.control, display: display)
                if success {
                    self.lastWrittenValues[key] = latestValue
                }
                completion(DisplayWriteResult(key: key, value: latestValue, success: success))
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
    let success: Bool
}

struct ControlledDisplay: Identifiable {
    let id: CGDirectDisplayID
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

    mutating func setSupported(_ isSupported: Bool, for control: DisplayControlKind) {
        switch control {
        case .brightness:
            supportsBrightness = isSupported
        case .volume:
            supportsVolume = isSupported
        case .contrast:
            supportsContrast = isSupported
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

        return displayIDs.compactMap { id -> ControlledDisplay? in
            let kind = classifier.classify(displayID: id)

            if kind == .virtual || kind == .dummy || kind == .unsupported {
                return nil
            }

            let isBuiltIn = (kind == .builtIn)
            let useDisplayServices = (kind == .builtIn || kind == .appleNative)
            let name = displayName(for: id, isBuiltIn: isBuiltIn)
            let storageID = displayStorageID(for: id, name: name, isBuiltIn: isBuiltIn)

            let nativeBrightness = useDisplayServices ? displayServices.getBrightness(displayID: id) : nil
            let hasDDCService = (kind == .externalDDC) && ddc.hasService(for: id)
            let ddcBrightness = (kind == .externalDDC) ? ddc.read(.brightness, displayID: id, fastFail: true) : nil
            let ddcVolume: Double? = nil
            let ddcContrast: Double? = nil

            let storedBrightness = storedValue(for: .brightness, displayStorageID: storageID)
            let storedVolume = storedValue(for: .volume, displayStorageID: storageID)
            let storedContrast = storedValue(for: .contrast, displayStorageID: storageID)

            return ControlledDisplay(
                id: id,
                storageID: storageID,
                name: name,
                isBuiltIn: isBuiltIn,
                supportsBrightness: useDisplayServices
                    ? (nativeBrightness != nil)
                    : (ddcBrightness != nil || storedBrightness != nil || hasDDCService),
                supportsVolume: !useDisplayServices && hasDDCService,
                supportsContrast: !useDisplayServices && hasDDCService,
                brightness: nativeBrightness.map { Double($0 * 100) }
                    ?? ddcBrightness
                    ?? storedBrightness
                    ?? DisplayControlKind.brightness.defaultValue,
                volume: ddcVolume
                    ?? storedVolume
                    ?? DisplayControlKind.volume.defaultValue,
                contrast: ddcContrast
                    ?? storedContrast
                    ?? DisplayControlKind.contrast.defaultValue
            )
        }
    }

    func setValue(_ value: Double, for control: DisplayControlKind, display: ControlledDisplay) -> Bool {
        guard display.supports(control) else { return false }

        let kind = classifier.classify(displayID: display.id)
        let useDisplayServices = (kind == .builtIn || kind == .appleNative)

        if useDisplayServices {
            switch control {
            case .brightness:
                return displayServices.setBrightness(displayID: display.id, value: Float(value / 100))
            case .volume, .contrast:
                return false
            }
        }

        let success = ddc.write(value, for: control, displayID: display.id)
        if success {
            saveStoredValue(value, for: control, displayStorageID: display.storageID)
        }
        return success
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
