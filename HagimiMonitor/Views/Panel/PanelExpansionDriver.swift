import Combine
import SwiftUI

/// 每个面板持有独立运动会话；几何登记和尺寸提交由原生宿主统一负责。
@MainActor
final class PanelExpansionDriver: ObservableObject {
    let motion = SingleHostMotionCoordinator(
        registry: PanelDimensionRegistry(
            initialEnvironment:
                GeometryEnvironmentToken(
                    width: MonitorConstants.panelIdealWidth,
                    localeIdentifier: Locale.current.identifier, dynamicTypeSize: "default",
                    backingScale: 2, structureSignature: "")))

    func animate(targets: [String: CGFloat], scrollToTop: Bool = false) {
        motion.nativeLayer.retarget(targets, scrollToTop: scrollToTop)
    }

    func setInstantly(targets: [String: CGFloat]) {
        motion.setInstantly(targets: targets)
    }

    func setInstantly(_ key: String, _ value: CGFloat) {
        setInstantly(targets: [key: value])
    }

    func animate(_ key: String, _ target: CGFloat) {
        animate(targets: [key: target])
    }
}
