//
//  FluidMenuBarExtraStatusItem.swift
//  FluidMenuBarExtra
//
//  Created by Lukas Romsicki on 2022-12-17.
//  Copyright © 2022 Lukas Romsicki.
//

import AppKit
import SwiftUI

/// An individual element displayed in the system menu bar that displays a window
/// when triggered.
final class FluidMenuBarExtraStatusItem: NSObject, NSWindowDelegate {
    let window: NSWindow
    var menu: NSMenu?
    @objc private let statusItem: NSStatusItem
    private var statusItemVisibilityObservation: NSKeyValueObservation? = nil

    private var localEventMonitor: EventMonitor?
    private var globalEventMonitor: EventMonitor?

    var alignment: PopUpAlignment
    var screenClippingBehaviour: ScreenClippingBehaviour {
        didSet {
            setWindowFrame(animate: true)
        }
    }

    @Binding private var isInserted: Bool

    enum Image {
        case named(String)
        case systemNamed(String)
        case direct(NSImage)
        case none

        func asNSImage(accessibilityDescription: String) -> NSImage? {
            switch self {
            case .named(let name):
                return NSImage(named: name)
            case .systemNamed(let name):
                return NSImage(systemSymbolName: name,
                               accessibilityDescription: accessibilityDescription)
            case .direct(let image):
                return image
            case .none:
                return nil
            }
        }
    }

    init<Content: View>(title: String,
                        image: Image = .none,
                        isInserted foo: Binding<Bool> = .constant(true),
                        window: FluidMenuBarExtraWindow<Content>,
                        menu: NSMenu? = nil,
                        alignment: PopUpAlignment = .left,
                        screenClippingBehaviour: ScreenClippingBehaviour = .reverseAlignment) {
        self._isInserted = foo
        self.window = window
        self.menu = menu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.behavior = .removalAllowed
        statusItem.isVisible = foo.wrappedValue
        statusItem.button?.setAccessibilityTitle(title)

        if let image = image.asNSImage(accessibilityDescription: title) {
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = title
        }

        self.alignment = alignment
        self.screenClippingBehaviour = screenClippingBehaviour
        
        super.init()

        assert(nil == window.statusItem)
        window.statusItem = self

        statusItemVisibilityObservation = observe(\.statusItem.isVisible, options: .new) {
            [weak self] _, change in
            guard let newValue = change.newValue else { return }
            self?.isInserted = newValue
        }

        localEventMonitor = LocalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self,
               let button = self.statusItem.button,
               event.window == button.window
            {
                switch (event.type, self.menu, event.modifierFlags.contains(.control)) {
                case (.leftMouseDown, _, false):
                    fallthrough
                case (_, nil, _):
                    if !event.modifierFlags.contains(.command) {
                        self.didPressStatusBarButton(button)
                        return nil
                    }

                case (_, let menu?, true):
                    fallthrough
                case (.rightMouseDown, let menu?, _):
                    menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.maxY + 5), in: button)
                    return nil

                default:
                    break
                }
            }

            return event
        }

        globalEventMonitor = GlobalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let window = self?.window, window.isKeyWindow {
                // Resign key window status if a external non-activating event is triggered,
                // such as other system status bar menus.
                window.resignKey()
            }
        }

        window.delegate = self
        localEventMonitor?.start()
    }

    deinit {
        statusItemVisibilityObservation?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func didPressStatusBarButton(_ sender: NSStatusBarButton) {
        if window.isVisible {
            dismissWindow()
            return
        }

        setWindowFrame()

        // Tells the system to persist the menu bar in full screen mode.
        DistributedNotificationCenter.default().post(name: .beginMenuTracking, object: nil)
        window.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool {
        get {
            statusItem.isVisible
        }
        set {
            statusItem.isVisible = newValue
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        globalEventMonitor?.start()
        setButtonHighlighted(to: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        globalEventMonitor?.stop()
        dismissWindow()
    }
    
    func showWindow() {
        guard !window.isVisible,
              let button = statusItem.button
        else { return }
        
        didPressStatusBarButton(button)
    }
    
    func dismissWindow() {
        // Tells the system to cancel persisting the menu bar in full screen mode.
        DistributedNotificationCenter.default().post(name: .endMenuTracking, object: nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            window.animator().alphaValue = 0

        } completionHandler: { [weak self] in
            self?.window.orderOut(nil)
            self?.window.alphaValue = 1
            self?.setButtonHighlighted(to: false)
        }
    }

    private func setButtonHighlighted(to highlight: Bool) {
        statusItem.button?.highlight(highlight)
    }

    func setWindowFrame(size: CGSize? = nil,
                        animate: Bool = false) {
        guard let statusItemWindow = statusItem.button?.window else {
            // If we don't know where the status item is, just place the window in the center.
            if let size {
                window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true, animate: false)
            }

            window.center()
            return
        }

        let statusItemFrame = statusItemWindow.frame
        var newFrame = CGRect(origin: statusItemFrame.origin, size: size ?? window.frame.size)

        newFrame.origin.y -= newFrame.height

        switch alignment {
        case .left:
            // Note: Offset by window border size to align with highlighted button.
            newFrame.origin.x -= Metrics.windowBorderSize
        case .centre:
            newFrame.origin.x += (statusItemFrame.width / 2) - (newFrame.width / 2)
        case .right:
            // Note: Offset by window border size to align with highlighted button.
            newFrame.origin.x += statusItemFrame.width - newFrame.width + Metrics.windowBorderSize
        }

        if let screen = statusItemWindow.screen {
            if newFrame.maxX > screen.visibleFrame.maxX {
                switch (alignment, screenClippingBehaviour) {
                case (.left, .reverseAlignment):
                    newFrame.origin.x = statusItemFrame.maxX - newFrame.width + Metrics.windowBorderSize
                default:
                    newFrame.origin.x = screen.visibleFrame.maxX - newFrame.width - Metrics.windowBorderSize
                }
            }

            if newFrame.minX < screen.visibleFrame.minX {
                switch (alignment, screenClippingBehaviour) {
                case (.right, .reverseAlignment):
                    newFrame.origin.x = statusItemFrame.minX - Metrics.windowBorderSize

                    if newFrame.maxX > screen.visibleFrame.maxX {
                        fallthrough
                    }
                default:
                    newFrame.origin.x = screen.visibleFrame.minX + Metrics.windowBorderSize
                }
            }
        }

        guard newFrame != window.frame else {
            return
        }

        window.setFrame(newFrame, display: true, animate: animate)
    }
}

private extension Notification.Name {
    static let beginMenuTracking = Notification.Name("com.apple.HIToolbox.beginMenuTrackingNotification")
    static let endMenuTracking = Notification.Name("com.apple.HIToolbox.endMenuTrackingNotification")
}

private enum Metrics {
    static let windowBorderSize: CGFloat = 2
}
