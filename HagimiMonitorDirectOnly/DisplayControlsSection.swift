import AppKit
import Combine
import CoreGraphics
import SwiftUI

struct DisplayControlsSection: View {
    @ObservedObject var settings: MonitorSettings
    @StateObject private var controller = DisplayControlController()
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    private let tint = Color(hex: 0xFF7EB6)
    private let expansionAnimation = Animation.smooth(duration: 0.22)

    var body: some View {
        let theme = DisplayControlTheme(colorScheme: colorScheme)
        let visibleDisplays = controller.displays
                .filter { settings.showBuiltInDisplays || !$0.isBuiltIn }
                .sorted { $0.isBuiltIn && !$1.isBuiltIn }
        let hasControls = settings.displayBrightnessControlEnabled
            || settings.displayVolumeControlEnabled
            || settings.displayContrastControlEnabled

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
                    .frame(width: 18)

                Text("显示器:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(summary(for: visibleDisplays, hasControls: hasControls))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.valueText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.captionText)
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
                    theme: theme
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
                .transition(.detailDisclosure)
            }
        }
        .onAppear {
            controller.refreshAsync()
        }
        .animation(expansionAnimation, value: isExpanded)
        .glassEffect(.regular.tint(theme.glassTint(for: tint)), in: .rect(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func detailContent(
        visibleDisplays: [ControlledDisplay],
        hasControls: Bool,
        theme: DisplayControlTheme
    ) -> some View {
        if !hasControls {
            DisplayEmptyState(text: "设置中未启用控制项", theme: theme, tint: tint)
        } else if visibleDisplays.isEmpty {
            DisplayEmptyState(text: settings.showBuiltInDisplays ? "未发现显示器" : "未发现外接显示器", theme: theme, tint: tint)
        } else {
            VStack(spacing: 8) {
                Rectangle()
                    .fill(theme.separator(for: tint))
                    .frame(height: 1)
                    .padding(.leading, 28)

                ForEach(Array(visibleDisplays.enumerated()), id: \.element.id) { index, display in
                    if index > 0 {
                        Rectangle()
                            .fill(theme.separator(for: tint).opacity(0.72))
                            .frame(height: 1)
                            .padding(.leading, 28)
                    }

                    DisplayControlGroup(
                        display: display,
                        settings: settings,
                        controller: controller,
                        theme: theme,
                        tint: tint
                    )
                }
            }
        }
    }

    private func summary(for displays: [ControlledDisplay], hasControls: Bool) -> String {
        guard hasControls else {
            return "已关闭"
        }

        let externalCount = displays.filter { !$0.isBuiltIn }.count
        if externalCount > 0 {
            return "\(displays.count) 台 · 外接 \(externalCount)"
        }
        return "\(displays.count) 台"
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
    let theme: DisplayControlTheme
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(display.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(display.name)

                    Spacer(minLength: 8)

                    Text(display.isBuiltIn ? "内置" : "外接")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(tint.opacity(theme.isDark ? 0.18 : 0.10))
                        }
                }

                VStack(spacing: 7) {
                    if settings.displayBrightnessControlEnabled {
                        DisplayControlSlider(
                            label: "亮度",
                            systemImage: "sun.max",
                            value: binding(for: .brightness),
                            isEnabled: display.supports(.brightness),
                            theme: theme,
                            tint: tint
                        )
                    }

                    if settings.displayVolumeControlEnabled {
                        DisplayControlSlider(
                            label: "音量",
                            systemImage: "speaker.wave.2",
                            value: binding(for: .volume),
                            isEnabled: display.supports(.volume),
                            theme: theme,
                            tint: tint
                        )
                    }

                    if settings.displayContrastControlEnabled {
                        DisplayControlSlider(
                            label: "对比度",
                            systemImage: "circle.lefthalf.filled",
                            value: binding(for: .contrast),
                            isEnabled: display.supports(.contrast),
                            theme: theme,
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
    let theme: DisplayControlTheme
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isEnabled ? tint : theme.captionText)
                .frame(width: 14)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isEnabled ? theme.secondaryText : theme.captionText)
                .frame(width: 34, alignment: .leading)

            Slider(value: $value, in: 0...100, step: 1)
                .tint(tint)
                .controlSize(.small)
                .disabled(!isEnabled)

            Text("\(Int(value.rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isEnabled ? theme.secondaryText : theme.captionText)
                .frame(width: 34, alignment: .trailing)
        }
        .opacity(isEnabled ? 1 : 0.48)
    }
}

private struct DisplayEmptyState: View {
    let text: String
    let theme: DisplayControlTheme
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(theme.separator(for: tint))
                .frame(height: 1)
                .padding(.leading, 28)

            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.captionText)
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
    private let worker = DisplayControlWorker()
    private var fallbackValues: [CGDirectDisplayID: [DisplayControlKind: Double]] = [:]

    func refreshAsync() {
        worker.refresh(service: service) { detectedDisplays in
            DispatchQueue.main.async {
                self.displays = detectedDisplays
                for display in detectedDisplays {
                    self.seedFallbackValues(for: display)
                }
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
            return
        }
        guard display.supports(control) else {
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
        } else if isCurrentResult {
            markControlUnsupported(result.key.control, displayID: result.key.displayID)
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
    private let queue = DispatchQueue(label: "hagimi.ddc", qos: .userInitiated)
    private var pendingWrites: [ControlKey: Double] = [:]
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

                let success = service.setValue(latestValue, for: key.control, display: display)
                completion(DisplayWriteResult(key: key, value: latestValue, success: success))
            }
            self.debounceTimers[key] = timer
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: timer)
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

private nonisolated struct ControlKey: Hashable {
    let displayID: CGDirectDisplayID
    let control: DisplayControlKind
}

private final class DisplayControlService {
    private let displayServices = DisplayServicesBridge()
    private let ddc = DisplayDDCBridge()
    private let defaults = UserDefaults.standard

    func displays() -> [ControlledDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else {
            return []
        }

        let displayIDs = Array(ids.prefix(Int(count)))
        ddc.refresh(displayIDs: displayIDs)

        return displayIDs.map { id in
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let name = displayName(for: id, isBuiltIn: isBuiltIn)
            let storageID = displayStorageID(for: id, name: name, isBuiltIn: isBuiltIn)
            let appleBrightness = isBuiltIn ? displayServices.getBrightness(displayID: id) : nil
            let hasDDCService = !isBuiltIn && ddc.hasService(for: id)
            let ddcBrightness = isBuiltIn ? nil : ddc.read(.brightness, displayID: id)
            let ddcVolume = isBuiltIn ? nil : ddc.read(.volume, displayID: id)
            let ddcContrast = isBuiltIn ? nil : ddc.read(.contrast, displayID: id)
            let storedBrightness = storedValue(for: .brightness, displayStorageID: storageID)
            let storedVolume = storedValue(for: .volume, displayStorageID: storageID)
            let storedContrast = storedValue(for: .contrast, displayStorageID: storageID)

            return ControlledDisplay(
                id: id,
                storageID: storageID,
                name: name,
                isBuiltIn: isBuiltIn,
                supportsBrightness: isBuiltIn ? appleBrightness != nil : (ddcBrightness != nil || storedBrightness != nil || hasDDCService),
                supportsVolume: !isBuiltIn && (ddcVolume != nil || storedVolume != nil),
                supportsContrast: !isBuiltIn && (ddcContrast != nil || storedContrast != nil),
                brightness: appleBrightness.map { Double($0 * 100) }
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
        guard display.supports(control) else {
            return false
        }

        if display.isBuiltIn {
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
            return "内置显示器"
        }

        let model = CGDisplayModelNumber(id)
        return model == 0 ? "外接显示器" : "外接显示器 \(model)"
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

private struct DisplayControlTheme {
    let colorScheme: ColorScheme

    var isDark: Bool {
        colorScheme == .dark
    }

    var primaryText: Color {
        isDark ? Color.white.opacity(0.94) : Color.primary
    }

    var valueText: Color {
        isDark ? Color.white.opacity(0.82) : Color.secondary
    }

    var secondaryText: Color {
        isDark ? Color.white.opacity(0.72) : Color.secondary
    }

    var captionText: Color {
        isDark ? Color.white.opacity(0.52) : Color.black.opacity(0.36)
    }

    func glassTint(for tint: Color) -> Color {
        tint.opacity(isDark ? 0.16 : 0.08)
    }

    func separator(for tint: Color) -> Color {
        tint.opacity(isDark ? 0.28 : 0.18)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
