import Combine
import Foundation

/// 面板隐藏态的观察侧门控。采样常驻后,面板隐藏期间 store 的 @Published 发布
/// 不停(数据始终新鲜),而卸窗不卸树的 hosting 订阅仍活跃——不拦截则每次发布
/// 都失效这棵不可见的视图树,主线程白付重算。门控只在开启时转发 store 的
/// 失效信号,隐藏期面板树完全冻结。
///
/// 开闸时自补发一次:store 一直活着,补发只为让 body 即刻以当前值重估,
/// 呼出首帧即最新数据,无需回放任何历史数据。
///
/// 开关由面板窗口控制器按显隐时序掌握,每个面板实例各持一个(菜单栏面板与
/// 钉住面板并存时互不牵动)。关闭必须晚于 store 的隐藏回调发布,保证
/// isPanelVisible 变 false 的最后一次转发送达视图、驱动隐藏复位。
final class PanelRefreshGate: ObservableObject {
    private var isOpen = false
    private var cancellable: AnyCancellable?

    init(store: MonitorStore) {
        cancellable = store.objectWillChange
            .sink { [weak self] _ in
                guard let self, self.isOpen else { return }
                self.objectWillChange.send()
            }
    }

    /// 开闸并补发一次,让面板树追平 store 当前值。幂等。
    func open() {
        guard !isOpen else { return }
        isOpen = true
        objectWillChange.send()
    }

    /// 关闸:后续 store 发布不再失效面板树。幂等。
    func close() {
        isOpen = false
    }
}
