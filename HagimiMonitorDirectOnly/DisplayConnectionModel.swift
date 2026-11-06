import CoreGraphics
import Foundation

/// 数字 display ID 只属于当前枚举，不写入持久身份。名称也不参与设备选择。
nonisolated struct DisplayConnectionIdentity: Codable, Hashable, Sendable {
    var uuid: String?
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32
    var isBuiltIn: Bool

    func matches(_ other: Self) -> Bool {
        guard vendor == other.vendor, model == other.model, isBuiltIn == other.isBuiltIn,
              vendor != 0 || model != 0 else { return false }
        if serial != 0, other.serial != 0, serial != other.serial { return false }
        if let uuid, let candidate = other.uuid { return uuid == candidate }
        if serial != 0, serial == other.serial { return true }
        // 内置面板是机器自身唯一的物理角色，仍需厂商/型号一致和全局唯一性校验。
        return isBuiltIn
    }
}

nonisolated struct DisplayConnectionBounds: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

nonisolated struct DisplayConnectionScreen: Equatable, Sendable {
    var id: CGDirectDisplayID
    var identity: DisplayConnectionIdentity
    var name: String
    var isPhysical: Bool
    var isOnline: Bool
    var hasDesktop: Bool
    var isVisible: Bool
    var mirrorTarget: CGDirectDisplayID?
    var bounds: DisplayConnectionBounds

    var isUsable: Bool { isPhysical && isOnline && hasDesktop && isVisible }
}

nonisolated enum DisplayConnectionObservation: String, Codable, Sendable {
    case connected, disabled, absent, unknown
    var title: String {
        let key = "display.connection.state." + rawValue
        return String(localized: String.LocalizationValue(key))
    }
}

nonisolated enum DisplayConnectionIssue: String, Codable, Error, Sendable {
    case unavailable, ambiguous, lastScreen, waiting, failed, unconfirmed, mirrorConflict, storage, interrupted

    var message: String {
        let key = "display.connection.issue." + rawValue
        return String(localized: String.LocalizationValue(key))
    }
}

nonisolated struct DisplayConnectionArchive: Codable, Equatable, Sendable {
    var info: DisplayInfo
    var capturedAt: Date
}

nonisolated struct DisplayConnectionMirrorMember: Codable, Equatable, Sendable {
    var identity: DisplayConnectionIdentity
    var target: DisplayConnectionIdentity?
    var bounds: DisplayConnectionBounds
}

nonisolated struct DisplayConnectionMirror: Codable, Equatable, Sendable {
    var original: [DisplayConnectionMirrorMember]
    var expected: [DisplayConnectionMirrorMember]?
}

nonisolated struct DisplayConnectionRecord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var identity: DisplayConnectionIdentity
    var name: String
    /// 兼容旧恢复日志；启动时清空，不能作为新的停用指令。
    var wantsDisabled = false
    var ownedDisabled = false
    var archive: DisplayConnectionArchive?
    var mirror: DisplayConnectionMirror?
    var brightness: Double?
    var volume: Double?
    var contrast: Double?
}

nonisolated struct DisplayConnectionState: Codable, Equatable, Sendable {
    var schema = 1
    var records: [DisplayConnectionRecord] = []
    var runActive = false
    var operationPending = false
    /// 仅为旧 schema 解码保留，当前没有自动停用流程。
    var automaticPaused = false
}

nonisolated struct DisplayConnectionEntry: Identifiable, Equatable, Sendable {
    var record: DisplayConnectionRecord
    var screen: DisplayConnectionScreen?
    var observation: DisplayConnectionObservation
    var isBusy = false
    var issue: DisplayConnectionIssue?
    var canDisable = false
    var id: UUID { record.id }
    var canWriteParameters: Bool { observation == .connected && !isBusy }

    /// 行头保留完整设备集合；停用屏沿用最后确认值，未知连接不冒充在线读数。
    func headerBrightness(in displays: [ControlledDisplay]) -> Double? {
        if observation == .disabled { return record.brightness }
        guard observation == .connected, let screen,
              let display = displays.first(where: {
                  $0.id == screen.id && $0.connectionIdentity?.matches(record.identity) == true
              }) else { return nil }
        return display.knownValue(for: .brightness)
    }
}

nonisolated enum DisplayConnectionPolicy {
    static func resolve(_ identity: DisplayConnectionIdentity, in screens: [DisplayConnectionScreen]) -> DisplayConnectionScreen? {
        let candidates = screens.filter { identity.matches($0.identity) }
        return candidates.count == 1 ? candidates[0] : nil
    }

    static func canDisable(_ target: DisplayConnectionScreen, in screens: [DisplayConnectionScreen]) -> Bool {
        target.isUsable && screens.contains { $0.id != target.id && $0.isUsable }
    }

    static func observation(_ record: DisplayConnectionRecord, in screens: [DisplayConnectionScreen]) -> DisplayConnectionObservation {
        guard let screen = resolve(record.identity, in: screens) else {
            return screens.contains { record.identity.matches($0.identity) } ? .unknown : .absent
        }
        if screen.isOnline && screen.hasDesktop { return .connected }
        return record.ownedDisabled ? .disabled : .unknown
    }

    static func mirrorGroup(for target: DisplayConnectionScreen, in screens: [DisplayConnectionScreen]) -> [DisplayConnectionMirrorMember] {
        let root = target.mirrorTarget ?? target.id
        let group = screens.filter { $0.id == root || $0.mirrorTarget == root }
        guard group.count > 1 else { return [] }
        return members(group, all: screens)
    }

    static func members(_ screens: [DisplayConnectionScreen], all: [DisplayConnectionScreen]) -> [DisplayConnectionMirrorMember] {
        screens.map { screen in
            DisplayConnectionMirrorMember(identity: screen.identity,
                target: screen.mirrorTarget.flatMap { id in all.first { $0.id == id }?.identity }, bounds: screen.bounds)
        }
    }

    static func mirrorsMatch(_ expected: [DisplayConnectionMirrorMember], current: [DisplayConnectionScreen], allowTranslation: Bool = false) -> Bool {
        var offsetX = 0.0, offsetY = 0.0
        if allowTranslation, let anchor = expected.first,
           let screen = resolve(anchor.identity, in: current) {
            offsetX = screen.bounds.x - anchor.bounds.x
            offsetY = screen.bounds.y - anchor.bounds.y
        }
        return expected.allSatisfy { member in
            guard let screen = resolve(member.identity, in: current), screen.isOnline else { return false }
            let target = screen.mirrorTarget.flatMap { id in current.first { $0.id == id }?.identity }
            return target == member.target && screen.bounds.width == member.bounds.width
                && screen.bounds.height == member.bounds.height
                && screen.bounds.x - offsetX == member.bounds.x && screen.bounds.y - offsetY == member.bounds.y
        }
    }
}
