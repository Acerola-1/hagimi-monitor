import AppKit
import ServiceManagement
import Testing
import KeyboardShortcuts
@testable import HagimiMonitorDirect

@MainActor
struct SettingsInteractionTests {
    enum LoginFailure: Error { case refused }

    @Test func openingGeneralSettingsPreservesBothLegacyMaterialValues() {
        for oldValue in [false, true] {
            let domain = "legacy-material-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain) }
            defaults.set(oldValue, forKey: "settings.liquidGlassEnabled")
            defaults.set(MonitorColorSchemePreference.balanced.rawValue, forKey: "settings.colorSchemePreference")
            let settings = MonitorSettings(defaults: defaults, loginItemStatus: { .notRegistered }, setLoginItemEnabled: { _ in })
            #expect(settings.liquidGlassEnabled == oldValue)
            #expect(defaults.bool(forKey: "settings.liquidGlassEnabled") == oldValue)
            settings.colorSchemePreference = .vibrant
            #expect(defaults.bool(forKey: "settings.liquidGlassEnabled") == oldValue)
            settings.colorSchemePreference = .balanced
            #expect(defaults.bool(forKey: "settings.liquidGlassEnabled") == oldValue)
        }
    }

    @Test func loginFailureRollsBackAndRetryClearsMessage() {
        let domain = "settings-interaction-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var status = SMAppService.Status.notRegistered
        var refuse = true
        let settings = MonitorSettings(defaults: defaults, loginItemStatus: { status },
            setLoginItemEnabled: { enabled in
                if refuse { throw LoginFailure.refused }
                status = enabled ? .enabled : .notRegistered
            })
        settings.launchAtLogin = true
        #expect(!settings.launchAtLogin)
        #expect(settings.launchAtLoginError != nil)
        refuse = false
        settings.launchAtLogin = true
        #expect(settings.launchAtLogin)
        #expect(settings.launchAtLoginError == nil)
        refuse = true
        settings.launchAtLogin = false
        #expect(settings.launchAtLogin)
        #expect(settings.launchAtLoginError != nil)
    }

    @Test func approvalRemainsDistinctFromEnabled() {
        let domain = "settings-interaction-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var status = SMAppService.Status.notRegistered
        let settings = MonitorSettings(defaults: defaults, loginItemStatus: { status },
            setLoginItemEnabled: { _ in status = .requiresApproval })
        settings.launchAtLogin = true
        #expect(settings.launchAtLoginNeedsApproval)
        #expect(!settings.launchAtLogin)
        #expect(settings.launchAtLoginError == nil)
    }

    @Test func standardQuitShortcutHasConflictMessage() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
            characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12))
        let shortcut = try #require(KeyboardShortcuts.Shortcut(event: event))
        #expect(QuickAccessShortcutConflict.message(for: shortcut, event: event) != nil)
    }
}
