import AppKit
import Combine
import SwiftUI

private struct PanelReorderControllerKey: EnvironmentKey {
    static let defaultValue: PanelReorderController? = nil
}

private struct PanelReorderSettingsKey: EnvironmentKey {
    static let defaultValue: MonitorSettings? = nil
}

extension EnvironmentValues {
    var panelReorderController: PanelReorderController? {
        get { self[PanelReorderControllerKey.self] }
        set { self[PanelReorderControllerKey.self] = newValue }
    }

    var panelReorderSettings: MonitorSettings? {
        get { self[PanelReorderSettingsKey.self] }
        set { self[PanelReorderSettingsKey.self] = newValue }
    }
}

private struct PanelReorderItemKey: Hashable {
    let scope: PanelOrderScope
    let id: String
}

private struct PanelReorderFrame {
    let rect: CGRect
    let span: Int
}

enum PanelNeighborDirection: CaseIterable, Hashable {
    case up, down, left, right

    var title: String {
        switch self {
        case .up: String(localized: "panel.reorder.move-up")
        case .down: String(localized: "panel.reorder.move-down")
        case .left: String(localized: "panel.reorder.move-left")
        case .right: String(localized: "panel.reorder.move-right")
        }
    }
}

private final class PanelReorderWeakView {
    weak var value: NSView?
    init(_ value: NSView) { self.value = value }
}

/// 锚点只用于抓取已在窗口中完成布局的源卡片，不参与命中或绘制。
private struct PanelReorderCaptureAnchor: NSViewRepresentable {
    let onAttach: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        DispatchQueue.main.async { onAttach(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onAttach(nsView) }
    }
}

@MainActor
final class PanelReorderPointer: ObservableObject {
    @Published var location: CGPoint = .zero
}

@MainActor
final class PanelReorderController: ObservableObject {
    struct Session {
        let scope: PanelOrderScope
        let id: String
        let title: String
        let preview: NSImage?
        let fallbackContent: AnyView?
        let sourceFrame: CGRect
        let grabOffset: CGPoint
        var before: String?
        var valid = false
        var slots: [(id: String, frame: CGRect, span: Int)]
    }

    @Published private(set) var session: Session?
    @Published private(set) var layoutRevision = 0
    let pointer = PanelReorderPointer()
    var canBegin: () -> Bool = { true }
    private var frames: [PanelReorderItemKey: PanelReorderFrame] = [:]
    private var titles: [PanelReorderItemKey: String] = [:]
    private var captureViews: [PanelReorderItemKey: PanelReorderWeakView] = [:]
    private var layoutRevisionPending = false

    func registerCapture(scope: PanelOrderScope, id: String, view: NSView) {
        let key = PanelReorderItemKey(scope: scope, id: id)
        guard captureViews[key]?.value !== view else { return }
        captureViews[key] = PanelReorderWeakView(view)
    }

    func snapshot(scope: PanelOrderScope, id: String) -> NSImage? {
        let key = PanelReorderItemKey(scope: scope, id: id)
        guard let view = captureViews[key]?.value,
              let windowContent = view.window?.contentView else { return nil }
        // 保留源视图的精确边界；取整会多抓到卡片外的窗口底色，浮起时形成亮边。
        let rect = view.convert(view.bounds, to: windowContent)
        guard rect.width > 0, rect.height > 0,
              let bitmap = windowContent.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        windowContent.cacheDisplay(in: rect, to: bitmap)
        let image = NSImage(size: rect.size)
        image.addRepresentation(bitmap)
        return image
    }

    func register(scope: PanelOrderScope, id: String, title: String, span: Int = 2, frame: CGRect) {
        let key = PanelReorderItemKey(scope: scope, id: id)
        let isNew = frames[key] == nil
        frames[key] = PanelReorderFrame(rect: frame, span: span)
        titles[key] = title
        if isNew { scheduleLayoutRevision() }
    }

    func unregister(scope: PanelOrderScope, id: String) {
        let key = PanelReorderItemKey(scope: scope, id: id)
        let wasRegistered = frames.removeValue(forKey: key) != nil
        titles.removeValue(forKey: key)
        captureViews.removeValue(forKey: key)
        if wasRegistered { scheduleLayoutRevision() }
        if session?.scope == scope && session?.id == id { cancel() }
    }

    private func scheduleLayoutRevision() {
        guard !layoutRevisionPending else { return }
        layoutRevisionPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutRevisionPending = false
            self.layoutRevision &+= 1
        }
    }

    func registeredFrame(scope: PanelOrderScope, id: String) -> CGRect? {
        frames[PanelReorderItemKey(scope: scope, id: id)]?.rect
    }

    func begin(scope: PanelOrderScope, id: String, location: CGPoint,
               settings: MonitorSettings, preview: NSImage? = nil,
               fallbackContent: AnyView? = nil) {
        guard session == nil, canBegin(),
              let source = frames[PanelReorderItemKey(scope: scope, id: id)]?.rect else { return }
        let slots = visibleSlots(scope: scope, settings: settings)
        guard slots.count > 1, slots.contains(where: { $0.id == id }) else { return }
        // 钉住面板可能仅被 orderFrontRegardless 显示；开始拖动时取得键盘焦点，
        // 让 SwiftUI 的 Esc 取消动作在拖动期间收到事件。
        captureViews[PanelReorderItemKey(scope: scope, id: id)]?.value?.window?.makeKey()
        pointer.location = location
        session = Session(scope: scope, id: id,
                          title: titles[PanelReorderItemKey(scope: scope, id: id)] ?? id,
                          preview: preview,
                          fallbackContent: fallbackContent,
                          sourceFrame: source,
                          grabOffset: CGPoint(x: location.x - source.minX, y: location.y - source.minY),
                          slots: slots)
        update(location: location)
    }

    func update(location: CGPoint) {
        pointer.location = location
        _ = refreshSession(at: location)
    }

    /// 滚动可在指针静止时改变所有卡片的屏幕位置；每次使用落点前都按最新布局重算。
    @discardableResult
    private func refreshSession(at location: CGPoint) -> Session? {
        guard var current = session else { return nil }
        let previousBefore = current.before
        let previousValid = current.valid
        let scope = current.scope
        current.slots = current.slots.map { slot in
            let latest = frames[PanelReorderItemKey(scope: scope, id: slot.id)]
            return (slot.id, latest?.rect ?? slot.frame, latest?.span ?? slot.span)
        }
        // 只接收同一作用域的实际卡片；展开区和固定组件即使位于两项之间也无效。
        current.valid = current.slots.contains {
            $0.frame.insetBy(dx: -12, dy: -12).contains(location)
        }
        if current.valid {
            let others = current.slots.filter { $0.id != current.id }
            let isModuleScope = current.scope == .modules
            current.before = others.first { slot in
                if location.y < slot.frame.minY { return true }
                if location.y > slot.frame.maxY { return false }
                if !isModuleScope && slot.span == 1 {
                    return location.x < slot.frame.midX
                }
                return location.y < slot.frame.midY
            }?.id
        } else {
            current.before = nil
        }
        if current.before != previousBefore || current.valid != previousValid {
            session = current
        }
        return current
    }

    func finish(settings: MonitorSettings) {
        guard let current = refreshSession(at: pointer.location) else { return }
        if current.valid {
            let visible = current.slots.map(\.id)
            _ = settings.movePanelItem(current.id, in: current.scope,
                                       before: current.before, visible: visible)
        }
        session = nil
    }

    func cancel() { session = nil }

    func projected(_ ids: [String], scope: PanelOrderScope) -> [String] {
        guard let session, session.scope == scope, session.valid,
              ids.contains(session.id),
              let moved = PanelOrderList.moved(ids, id: session.id,
                                               before: session.before, visible: ids) else { return ids }
        return moved
    }

    func isSource(scope: PanelOrderScope, id: String) -> Bool {
        session?.scope == scope && session?.id == id
    }

    func edgeScrollTarget(towardBottom: Bool, viewport: CGRect) -> String? {
        guard let session = refreshSession(at: pointer.location) else { return nil }
        let slots = session.slots.sorted { $0.frame.minY < $1.frame.minY }
        let id = towardBottom
            ? slots.first(where: { $0.frame.maxY > viewport.maxY + 8 })?.id
            : slots.last(where: { $0.frame.minY < viewport.minY - 8 })?.id
        guard let id else { return nil }
        return "panel-order.\(session.scope.storageKey).\(id)"
    }

    func availableDirections(_ id: String, scope: PanelOrderScope,
                             settings: MonitorSettings) -> [PanelNeighborDirection] {
        let slots = visibleSlots(scope: scope, settings: settings)
        return PanelNeighborDirection.allCases.filter {
            insertionTarget(id, direction: $0, slots: slots) != nil
        }
    }

    func move(_ id: String, scope: PanelOrderScope, direction: PanelNeighborDirection,
              settings: MonitorSettings) {
        let slots = visibleSlots(scope: scope, settings: settings)
        guard let before = insertionTarget(id, direction: direction, slots: slots) else { return }
        _ = settings.movePanelItem(id, in: scope, before: before, visible: slots.map(\.id))
    }

    /// 按静态跨度还原屏幕上的行；横向交换同排半格，纵向跨过相邻一行的对应格。
    private func insertionTarget(
        _ id: String, direction: PanelNeighborDirection,
        slots: [(id: String, frame: CGRect, span: Int)]
    ) -> String?? {
        guard let sourceIndex = slots.firstIndex(where: { $0.id == id }) else { return nil }
        let rows = MetricGridPacking.rows(for: slots.map(\.span))
        guard let rowIndex = rows.firstIndex(where: { $0.contains(sourceIndex) }) else { return nil }
        let row = rows[rowIndex]
        let column = row.firstIndex(of: sourceIndex) ?? 0
        let sourceIsHalf = slots[sourceIndex].span == 1

        switch direction {
        case .left:
            guard sourceIsHalf, row.count == 2, column == 1 else { return nil }
            return .some(slots[row[0]].id)
        case .right:
            guard sourceIsHalf, row.count == 2, column == 0 else { return nil }
            return .some(idAfter(row[1], in: slots))
        case .up:
            guard rowIndex > 0 else { return nil }
            let previous = rows[rowIndex - 1]
            let target = sourceIsHalf && column == 1 && previous.count == 2
                ? previous[1] : previous[0]
            return .some(slots[target].id)
        case .down:
            guard rowIndex + 1 < rows.count else { return nil }
            let next = rows[rowIndex + 1]
            let target = sourceIsHalf && column == 0 && next.count == 2
                ? next[0] : next[next.count - 1]
            return .some(idAfter(target, in: slots))
        }
    }

    private func idAfter(_ index: Int,
                         in slots: [(id: String, frame: CGRect, span: Int)]) -> String? {
        slots.indices.contains(index + 1) ? slots[index + 1].id : nil
    }

    private func visibleSlots(scope: PanelOrderScope, settings: MonitorSettings) -> [(id: String, frame: CGRect, span: Int)] {
        let available = frames.keys.filter { $0.scope == scope }.map(\.id)
        return settings.orderedPanelIDs(for: scope, available: available).compactMap { id in
            guard let frame = frames[PanelReorderItemKey(scope: scope, id: id)],
                  frame.rect.width > 0, frame.rect.height > 0 else { return nil }
            return (id, frame.rect, frame.span)
        }
    }
}

struct PanelReorderGhost: View {
    let session: PanelReorderController.Session
    @ObservedObject var pointer: PanelReorderPointer
    let theme: MonitorPanelTheme

    private var cornerRadius: CGFloat {
        session.scope == .modules ? MonitorConstants.rowCornerRadius : 7
    }

    private var accent: Color {
        if let kind = session.scope.moduleKind
            ?? (session.scope == .modules ? MonitorKind(rawValue: session.id) : nil) {
            theme.moduleTint(for: kind)
        } else {
            theme.palette.displayTint
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            Group {
                if let preview = session.preview {
                    Image(nsImage: preview)
                        .resizable()
                        .frame(width: session.sourceFrame.width, height: session.sourceFrame.height)
                } else if let fallbackContent = session.fallbackContent {
                    fallbackContent
                        .frame(width: session.sourceFrame.width, height: session.sourceFrame.height)
                } else {
                    Text(session.title)
                        .monitorPanelMetricLabelFont()
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 10)
                        .frame(width: session.sourceFrame.width, height: session.sourceFrame.height,
                               alignment: .leading)
                }
            }
            .background {
                if session.preview == nil {
                    Group {
                        if session.scope == .modules && session.id == PanelOrderCatalog.displayID {
                            theme.palette.displayGlassFill
                        } else if let kind = session.scope.moduleKind
                            ?? (session.scope == .modules ? MonitorKind(rawValue: session.id) : nil) {
                            theme.rowGlassFill(for: kind)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.38), lineWidth: 1)
            }
            .compositingGroup()
            .overlay(alignment: .bottomLeading) {
                if !session.valid {
                    Text(String(localized: "panel.reorder.invalid-drop"))
                        .monitorPanelCaptionFont(.caption2)
                        .foregroundStyle(theme.primaryText)
                        .padding(5)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .offset(y: 21)
                }
            }
            .shadow(color: .black.opacity(0.32), radius: 14, y: 7)
            .scaleEffect(1.035)
            .position(x: pointer.location.x - session.grabOffset.x
                          + session.sourceFrame.width / 2 - origin.x,
                      y: pointer.location.y - session.grabOffset.y
                          + session.sourceFrame.height / 2 - origin.y)
        }
        .allowsHitTesting(false)
    }
}

struct PanelEdgeScrollObserver: View {
    @ObservedObject var pointer: PanelReorderPointer
    let controller: PanelReorderController
    let viewport: CGRect
    let proxy: ScrollViewProxy
    @State private var scrollTask: Task<Void, Never>?

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: pointer.location.y) { _, y in
                scrollTask?.cancel()
                scrollTask = nil
                guard let session = controller.session, viewport.height > 0,
                      y > viewport.maxY - 28 || y < viewport.minY + 28 else { return }
                let start = CGPoint(x: session.sourceFrame.minX + session.grabOffset.x,
                                    y: session.sourceFrame.minY + session.grabOffset.y)
                guard hypot(pointer.location.x - start.x, pointer.location.y - start.y) > 8 else { return }
                let towardBottom = y > viewport.maxY - 28
                scrollTask = Task { @MainActor in
                    while !Task.isCancelled, controller.session != nil {
                        guard let id = controller.edgeScrollTarget(towardBottom: towardBottom,
                                                                   viewport: viewport) else { break }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(id, anchor: towardBottom ? .bottom : .top)
                        }
                        try? await Task.sleep(for: .milliseconds(210))
                    }
                }
            }
            .onDisappear { scrollTask?.cancel() }
    }
}

private struct PanelReorderTrackedContent<Content: View>: View {
    @ObservedObject var controller: PanelReorderController
    let scope: PanelOrderScope
    let id: String
    let content: Content

    var body: some View {
        content.opacity(controller.isSource(scope: scope, id: id) ? 0.34 : 1)
    }
}

private struct PanelReorderItemModifier: ViewModifier {
    let scope: PanelOrderScope
    let id: String
    let title: String
    let span: Int
    @Environment(\.panelReorderController) private var controller
    @Environment(\.panelReorderSettings) private var settings
    @Environment(\.displayScale) private var displayScale
    @State private var menuLayoutRevision = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if let controller, let settings {
            interactive(content: content, controller: controller, settings: settings)
        } else {
            content
        }
    }

    private func interactive(content: Content, controller: PanelReorderController,
                             settings: MonitorSettings) -> some View {
        let _ = menuLayoutRevision
        return PanelReorderTrackedContent(controller: controller, scope: scope, id: id, content: content)
            .id("panel-order.\(scope.storageKey).\(id)")
            .background {
                PanelReorderCaptureAnchor { view in
                    controller.registerCapture(scope: scope, id: id, view: view)
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                controller.register(scope: scope, id: id, title: title, span: span, frame: frame)
            }
            .onDisappear { controller.unregister(scope: scope, id: id) }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4, maximumDistance: 10)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { phase in
                        guard case .second(true, let drag) = phase else { return }
                        if let drag {
                            if !controller.isSource(scope: scope, id: id) {
                                beginDrag(content: content, location: drag.startLocation,
                                          controller: controller, settings: settings)
                            }
                            if controller.isSource(scope: scope, id: id) {
                                controller.update(location: drag.location)
                            }
                        } else if !controller.isSource(scope: scope, id: id),
                                  let frame = controller.registeredFrame(scope: scope, id: id) {
                            beginDrag(content: content,
                                      location: CGPoint(x: frame.midX, y: frame.midY),
                                      controller: controller, settings: settings)
                        }
                    }
                    .onEnded { phase in
                        guard controller.isSource(scope: scope, id: id) else { return }
                        if case .second(true, let drag) = phase, let drag {
                            controller.update(location: drag.location)
                        }
                        controller.finish(settings: settings)
                    }
            )
            .contextMenu {
                moveCommands(controller: controller, settings: settings)
                if controller.availableDirections(id, scope: scope, settings: settings).isEmpty {
                    Button(String(localized: "panel.reorder.no-moves")) {}
                        .disabled(true)
                }
            }
            .accessibilityActions {
                moveCommands(controller: controller, settings: settings)
            }
            .onReceive(controller.$layoutRevision) { _ in
                menuLayoutRevision &+= 1
            }
            .onReceive(settings.$panelOrders) { _ in
                menuLayoutRevision &+= 1
            }
            .help(String(localized: "panel.reorder.long-press-hint"))
    }

    @ViewBuilder
    private func moveCommands(controller: PanelReorderController,
                              settings: MonitorSettings) -> some View {
        let available = controller.availableDirections(id, scope: scope, settings: settings)
        if available.contains(.up) {
            Button(PanelNeighborDirection.up.title) {
                controller.move(id, scope: scope, direction: .up, settings: settings)
            }
        }
        if available.contains(.down) {
            Button(PanelNeighborDirection.down.title) {
                controller.move(id, scope: scope, direction: .down, settings: settings)
            }
        }
        if available.contains(.left) {
            Button(PanelNeighborDirection.left.title) {
                controller.move(id, scope: scope, direction: .left, settings: settings)
            }
        }
        if available.contains(.right) {
            Button(PanelNeighborDirection.right.title) {
                controller.move(id, scope: scope, direction: .right, settings: settings)
            }
        }
    }

    private func beginDrag(content: Content, location: CGPoint,
                           controller: PanelReorderController, settings: MonitorSettings) {
        guard controller.session == nil,
              let frame = controller.registeredFrame(scope: scope, id: id) else { return }
        var snapshot = controller.snapshot(scope: scope, id: id)
        if snapshot == nil {
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: frame.width, height: frame.height)
            renderer.scale = displayScale
            snapshot = renderer.nsImage
        }
        controller.begin(scope: scope, id: id,
                         location: location, settings: settings,
                         preview: snapshot,
                         fallbackContent: AnyView(content))
    }
}

extension View {
    func panelReorderItem(scope: PanelOrderScope, id: String, title: String, span: Int = 2) -> some View {
        modifier(PanelReorderItemModifier(scope: scope, id: id, title: title, span: span))
    }
}
