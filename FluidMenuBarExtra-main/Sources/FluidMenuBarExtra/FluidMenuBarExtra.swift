//
//  FluidMenuBarExtra.swift
//  FluidMenuBarExtra
//
//  Created by Lukas Romsicki on 2022-12-17.
//  Copyright © 2022 Lukas Romsicki.
//

import SwiftUI

/// A class you use to create a menubar extra in SwiftUI.
///
/// This is by design similar to Apple's ``SwiftUI.MenuBarExtra`` provided in SwiftUI itself, but with additional functionality and better behaviour (Apple's `MenuBarExtra` doesn't follow macOS standards regarding how it responds to user interaction).
///
/// Typically you use this in your @main body where you spell out your app's various scenes (e.g. WindowGroups, Settings, etc).  e.g.:
///
/// ```swift
/// import SwiftUI
/// import FluidMenuBarExtra
///
/// @main
/// private struct DemoApp: App {
///     @AppStorage("showMenuBarExtra") var showMenuBarExtra = true
///
///     var body: some Scene {
///         FluidMenuBarExtra("Demo", systemImage: "chevron.down.circle", isInserted: $showMenuBarExtra) {
///             Text("Hello, world!")
///                 .padding(20)
///         }
///     }
/// }
/// ```
///
/// See also the bundled demo application for a more detailed example.
public struct FluidMenuBarExtra<Content: View>: Scene {
    private class State<Content: View>: ObservableObject {
        var statusItem: FluidMenuBarExtraStatusItem? = nil
    }

    @StateObject private var state = State<Content>()
    @Binding private var isInserted: Bool

    private let title: String
    private let image: FluidMenuBarExtraStatusItem.Image
    private let animation: NSWindow.AnimationBehavior
    private let menu: NSMenu?
    private let alignment: PopUpAlignment
    private let screenClippingBehaviour: ScreenClippingBehaviour
    private let content: () -> Content

    /// - Parameters:
    ///   - title: If no image is provided (`.none`), this is the text shown instead.  If an image is provided, only the image is shown but this title is used as the accessibility title (e.g. for screen readers).
    ///   - image: An optional image to use as the icon for the menubar item, in the menubar.  If `.none`, ``title`` is shown instead.
    ///   - isInserted: An optional binding to a boolean that controls whether the menubar item is visible or not.  Typically this is tied to a Toggle in your app's settings, or similar.  Note that this has no effect on the visiblity of the pop-up window (e.g. changing this to false while the window is shown won't hide the window, even though the menubar item itself disappears).
    ///
    ///     Note that this binding is two-way - if the user removes the menubar item from the menubar, e.g. by command-dragging it out, the bound boolean will be set to false.
    ///   - animation: The animation style to use when showing the pop-up window.  By default no animation is used (which is the general default for menus across the board), as users typically don't want unnecessary delays to seeing the content.
    ///
    ///     The exact animation may vary across macOS versions.  In macOS 13, the animation styles are:
    ///       * `alertPanel`:  An energetic "pop"-in effect, with overshoot.  Most modal alerts in macOS present this way.  It is designed to grab the user's attention.
    ///       * `documentWindow`:  A "pop"-in effect.  Most (non-alert) windows in macOS appear this way.  It is designed to be smooth and relatively subtle.
    ///       * `none` / `utilityWindow`:  No animation; the window appears instantly.
    ///       * `default`:  At time of writing this is the same as `none`, but it should never be used as its meaning is implementation-dependent and may change without warning in future versions of FluidMenuBarExtra.
    ///   - menu: An optional menu to be shown if the user right-clicks the menubar item.  This is distinct from the pop-up window shown for left-clicks.  It is uncommon to use this functionality.
    ///   - alignment: Specifies how the pop-up window is aligned relative to the menubar item.
    ///   - screenClippingBehaviour: Specifies how the pop-up window's position is adjusted when it runs up against the edges of the screen.
    ///   - content: The contents of the pop-up window that is shown when the user clicks on the menubar item.
    private init(_ title: String,
                 image: FluidMenuBarExtraStatusItem.Image,
                 isInserted foo: Binding<Bool> = .constant(true),
                 animation: NSWindow.AnimationBehavior = .none,
                 menu: NSMenu? = nil,
                 alignment: PopUpAlignment = .left,
                 screenClippingBehaviour: ScreenClippingBehaviour = .reverseAlignment,
                 @ViewBuilder content: @escaping () -> Content) {
        self._isInserted = foo

        self.title = title
        self.image = image
        self.animation = animation
        self.menu = menu
        self.alignment = alignment
        self.screenClippingBehaviour = screenClippingBehaviour
        self.content = content

        if .default == animation {
            print("Warning: it is unwise to use the `default` window animation style with FluidMenuBarExtra, as its meaning may change in future versions of the package.  Use `none` instead.")
        }
    }

    /// - Parameters:
    ///   - title: The text shown in the menubar, for this menubar extra.
    ///   - isInserted: An optional binding to a boolean that controls whether the menubar item is visible or not.  Typically this is tied to a Toggle in your app's settings, or similar.  Note that this has no effect on the visiblity of the pop-up window (e.g. changing this to false while the window is shown won't hide the window, even though the menubar item itself disappears).
    ///
    ///     Note that this binding is two-way - if the user removes the menubar item from the menubar, e.g. by command-dragging it out, the bound boolean will be set to false.
    ///   - animation: The animation style to use when showing the pop-up window.  By default no animation is used (which is the general default for menus across the board), as users typically don't want unnecessary delays to seeing the content.
    ///
    ///     The exact animation may vary across macOS versions.  In macOS 13, the animation styles are:
    ///       * `alertPanel`:  An energetic "pop"-in effect, with overshoot.  Most modal alerts in macOS present this way.  It is designed to grab the user's attention.
    ///       * `documentWindow`:  A "pop"-in effect.  Most (non-alert) windows in macOS appear this way.  It is designed to be smooth and relatively subtle.
    ///       * `none` / `utilityWindow`:  No animation; the window appears instantly.
    ///       * `default`:  At time of writing this is the same as `none`, but it should never be used as its meaning is implementation-dependent and may change without warning in future versions of FluidMenuBarExtra.
    ///   - menu: An optional menu to be shown if the user right-clicks the menubar item.  This is distinct from the pop-up window shown for left-clicks.  It is uncommon to use this functionality.
    ///   - alignment: Specifies how the pop-up window is aligned relative to the menubar item.
    ///   - screenClippingBehaviour: Specifies how the pop-up window's position is adjusted when it runs up against the edges of the screen.
    ///   - content: The contents of the pop-up window that is shown when the user clicks on the menubar item.
    public init(_ title: String,
                isInserted: Binding<Bool> = .constant(true),
                animation: NSWindow.AnimationBehavior = .none,
                menu: NSMenu? = nil,
                alignment: PopUpAlignment = .left,
                screenClippingBehaviour: ScreenClippingBehaviour = .reverseAlignment,
                @ViewBuilder content: @escaping () -> Content) {
        self.init(title,
                  image: .none,
                  isInserted: isInserted,
                  animation: animation,
                  menu: menu,
                  alignment: alignment,
                  screenClippingBehaviour: screenClippingBehaviour,
                  content: content)
    }

    /// - Parameters:
    ///   - title: This is not shown in the menubar directly (only `image` is) but this is used as the accessibility title (e.g. for screen readers).
    ///   - image: The name of the image (a la ``NSImage(named:)``) to use as the icon for the menubar item, in the menubar.
    ///   - isInserted: An optional binding to a boolean that controls whether the menubar item is visible or not.  Typically this is tied to a Toggle in your app's settings, or similar.  Note that this has no effect on the visiblity of the pop-up window (e.g. changing this to false while the window is shown won't hide the window, even though the menubar item itself disappears).
    ///
    ///     Note that this binding is two-way - if the user removes the menubar item from the menubar, e.g. by command-dragging it out, the bound boolean will be set to false.
    ///   - animation: The animation style to use when showing the pop-up window.  By default no animation is used (which is the general default for menus across the board), as users typically don't want unnecessary delays to seeing the content.
    ///
    ///     The exact animation may vary across macOS versions.  In macOS 13, the animation styles are:
    ///       * `alertPanel`:  An energetic "pop"-in effect, with overshoot.  Most modal alerts in macOS present this way.  It is designed to grab the user's attention.
    ///       * `documentWindow`:  A "pop"-in effect.  Most (non-alert) windows in macOS appear this way.  It is designed to be smooth and relatively subtle.
    ///       * `none` / `utilityWindow`:  No animation; the window appears instantly.
    ///       * `default`:  At time of writing this is the same as `none`, but it should never be used as its meaning is implementation-dependent and may change without warning in future versions of FluidMenuBarExtra.
    ///   - menu: An optional menu to be shown if the user right-clicks the menubar item.  This is distinct from the pop-up window shown for left-clicks.  It is uncommon to use this functionality.
    ///   - alignment: Specifies how the pop-up window is aligned relative to the menubar item.
    ///   - screenClippingBehaviour: Specifies how the pop-up window's position is adjusted when it runs up against the edges of the screen.
    ///   - content: The contents of the pop-up window that is shown when the user clicks on the menubar item.
    public init(_ title: String,
                image: String,
                isInserted: Binding<Bool> = .constant(true),
                animation: NSWindow.AnimationBehavior = .none,
                menu: NSMenu? = nil,
                alignment: PopUpAlignment = .left,
                screenClippingBehaviour: ScreenClippingBehaviour = .reverseAlignment,
                @ViewBuilder content: @escaping () -> Content) {
        self.init(title,
                  image: .named(image),
                  isInserted: isInserted,
                  animation: animation,
                  menu: menu,
                  alignment: alignment,
                  screenClippingBehaviour: screenClippingBehaviour,
                  content: content)
    }

    /// - Parameters:
    ///   - title: This is not shown in the menubar directly (only `image` is) but this is used as the accessibility title (e.g. for screen readers).
    ///   - image: The image to use as the icon for the menubar item, in the menubar.
    ///   - isInserted: An optional binding to a boolean that controls whether the menubar item is visible or not.  Typically this is tied to a Toggle in your app's settings, or similar.  Note that this has no effect on the visiblity of the pop-up window (e.g. changing this to false while the window is shown won't hide the window, even though the menubar item itself disappears).
    ///
    ///     Note that this binding is two-way - if the user removes the menubar item from the menubar, e.g. by command-dragging it out, the bound boolean will be set to false.
    ///   - animation: The animation style to use when showing the pop-up window.  By default no animation is used (which is the general default for menus across the board), as users typically don't want unnecessary delays to seeing the content.
    ///
    ///     The exact animation may vary across macOS versions.  In macOS 13, the animation styles are:
    ///       * `alertPanel`:  An energetic "pop"-in effect, with overshoot.  Most modal alerts in macOS present this way.  It is designed to grab the user's attention.
    ///       * `documentWindow`:  A "pop"-in effect.  Most (non-alert) windows in macOS appear this way.  It is designed to be smooth and relatively subtle.
    ///       * `none` / `utilityWindow`:  No animation; the window appears instantly.
    ///       * `default`:  At time of writing this is the same as `none`, but it should never be used as its meaning is implementation-dependent and may change without warning in future versions of FluidMenuBarExtra.
    ///   - menu: An optional menu to be shown if the user right-clicks the menubar item.  This is distinct from the pop-up window shown for left-clicks.  It is uncommon to use this functionality.
    ///   - alignment: Specifies how the pop-up window is aligned relative to the menubar item.
    ///   - screenClippingBehaviour: Specifies how the pop-up window's position is adjusted when it runs up against the edges of the screen.
    ///   - content: The contents of the pop-up window that is shown when the user clicks on the menubar item.
    public init(_ title: String,
                image: NSImage,
                isInserted: Binding<Bool> = .constant(true),
                animation: NSWindow.AnimationBehavior = .none,
                menu: NSMenu? = nil,
                alignment: PopUpAlignment = .left,
                screenClippingBehaviour: ScreenClippingBehaviour = .reverseAlignment,
                @ViewBuilder content: @escaping () -> Content) {
        self.init(title,
                  image: .direct(image),
                  isInserted: isInserted,
                  animation: animation,
                  menu: menu,
                  alignment: alignment,
                  screenClippingBehaviour: screenClippingBehaviour,
                  content: content)
    }

    /// - Parameters:
    ///   - title: This is not shown in the menubar directly (only `image` is) but this is used as the accessibility title (e.g. for screen readers).
    ///   - image: The name of the system symbol image (a la SF Symbols) to use as the icon for the menubar item, in the menubar.
    ///   - isInserted: An optional binding to a boolean that controls whether the menubar item is visible or not.  Typically this is tied to a Toggle in your app's settings, or similar.  Note that this has no effect on the visiblity of the pop-up window (e.g. changing this to false while the window is shown won't hide the window, even though the menubar item itself disappears).
    ///
    ///     Note that this binding is two-way - if the user removes the menubar item from the menubar, e.g. by command-dragging it out, the bound boolean will be set to false.
    ///   - animation: The animation style to use when showing the pop-up window.  By default no animation is used (which is the general default for menus across the board), as users typically don't want unnecessary delays to seeing the content.
    ///
    ///     The exact animation may vary across macOS versions.  In macOS 13, the animation styles are:
    ///       * `alertPanel`:  An energetic "pop"-in effect, with overshoot.  Most modal alerts in macOS present this way.  It is designed to grab the user's attention.
    ///       * `documentWindow`:  A "pop"-in effect.  Most (non-alert) windows in macOS appear this way.  It is designed to be smooth and relatively subtle.
    ///       * `none` / `utilityWindow`:  No animation; the window appears instantly.
    ///       * `default`:  At time of writing this is the same as `none`, but it should never be used as its meaning is implementation-dependent and may change without warning in future versions of FluidMenuBarExtra.
    ///   - menu: An optional menu to be shown if the user right-clicks the menubar item.  This is distinct from the pop-up window shown for left-clicks.  It is uncommon to use this functionality.
    ///   - alignment: Specifies how the pop-up window is aligned relative to the menubar item.
    ///   - screenClippingBehaviour: Specifies how the pop-up window's position is adjusted when it runs up against the edges of the screen.
    ///   - content: The contents of the pop-up window that is shown when the user clicks on the menubar item.
    public init(_ title: String,
                systemImage: String,
                isInserted: Binding<Bool> = .constant(true),
                animation: NSWindow.AnimationBehavior = .none,
                menu: NSMenu? = nil,
                alignment: PopUpAlignment = .left,
                screenClippingBehaviour: ScreenClippingBehaviour = .reverseAlignment,
                @ViewBuilder content: @escaping () -> Content) {
        self.init(title,
                  image: .systemNamed(systemImage),
                  isInserted: isInserted,
                  animation: animation,
                  menu: menu,
                  alignment: alignment,
                  screenClippingBehaviour: screenClippingBehaviour,
                  content: content)
    }
    
    public func showWindow() {
        state.statusItem?.showWindow()
    }
    
    public func closeWindow() {
        state.statusItem?.dismissWindow()
    }

    public var body: some Scene {
        if let statusItem = state.statusItem {
            statusItem.menu = menu
            statusItem.alignment = alignment
            statusItem.screenClippingBehaviour = screenClippingBehaviour
            statusItem.window.animationBehavior = animation
        } else {
            state.statusItem = FluidMenuBarExtraStatusItem(title: title,
                                                           image: image,
                                                           isInserted: $isInserted,
                                                           window: FluidMenuBarExtraWindow(title: title,
                                                                                           animation: animation,
                                                                                           content: content),
                                                           menu: menu,
                                                           alignment: alignment,
                                                           screenClippingBehaviour: screenClippingBehaviour)
        }

        return Settings {}.onChange(of: isInserted) { state.statusItem?.isVisible = $0 }
    }
}

/// Controls how the pop-up window is aligned relative to the menubar item.
public enum PopUpAlignment: Hashable {
    /// The pop-up window's left edge is aligned with the menubar item's left edge.
    case left

    /// The pop-up window is centred underneath the menubar item.
    case centre

    /// The pop-up window's right edge is aligned with the menubar item's right edge.
    case right
}

/// Controls how the pop-up window's position is adapted to space constraints from encountering the left or right edges of the screen.
public enum ScreenClippingBehaviour: Hashable {
    /// If there isn't enough space to use the normal alignment, switch to its reverse (e.g. ``FluidMenuBarExtraPopUpAlignment/right`` instead of ``FluidMenuBarExtraPopUpAlignment/left``).  If this still isn't sufficient to resolve the problem, the behaviour falls back to ``hugEdge``.
    case reverseAlignment

    /// Nudge the pop-up window in from the edge just enough to make it fully visible.  This may mean an otherwise unnatural alignment of the pop-up window and the menubar item, not corresponding to any of the ``FluidMenuBarExtraPopUpAlignment`` options.
    case hugEdge
}
