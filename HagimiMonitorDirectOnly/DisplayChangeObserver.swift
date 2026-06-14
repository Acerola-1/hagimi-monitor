import AppKit
import CoreGraphics
import Foundation

@MainActor
final class DisplayChangeObserver {
    private var callback: (() -> Void)?
    private var debounceTimer: DispatchSourceTimer?
    private var registered = false

    func start(onChange: @escaping () -> Void) {
        callback = onChange
        if !registered {
            CGDisplayRegisterReconfigurationCallback(Self.cgCallback, Unmanaged.passUnretained(self).toOpaque())
            registered = true
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func stop() {
        if registered {
            CGDisplayRemoveReconfigurationCallback(Self.cgCallback, Unmanaged.passUnretained(self).toOpaque())
            registered = false
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        debounceTimer?.cancel()
        debounceTimer = nil
    }

    deinit {
        if registered {
            CGDisplayRemoveReconfigurationCallback(Self.cgCallback, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    @objc private func systemDidWake(_ note: Notification) {
        scheduleCallback(after: .milliseconds(800))
    }

    fileprivate func handleReconfigure() {
        scheduleCallback(after: .milliseconds(1000))
    }

    private func scheduleCallback(after delay: DispatchTimeInterval) {
        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.callback?()
        }
        debounceTimer = timer
        timer.resume()
    }

    private static let cgCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        if flags.contains(.addFlag) ||
           flags.contains(.removeFlag) {
            let observer = Unmanaged<DisplayChangeObserver>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                observer.handleReconfigure()
            }
        }
    }
}
