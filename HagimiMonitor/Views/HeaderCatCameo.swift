import AppKit
import Combine
import SwiftUI

/// 自动管理 Timer 生命周期的包装器。
/// 安全不变式：在 deinit 时确保底层 Timer 在主线程安全完成 invalidate，避免内存泄漏与并发冲突。
nonisolated private final class ScheduledTimerBox: @unchecked Sendable {
    private var timer: Timer?

    init(_ timer: Timer) {
        self.timer = timer
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        let t = timer
        if let t {
            if Thread.isMainThread {
                t.invalidate()
            } else {
                DispatchQueue.main.async {
                    t.invalidate()
                }
            }
        }
    }
}

/// 面板 header 小猫「客串」彩蛋的状态机（致敬 RunCat）。
///
/// 每次面板由隐藏变为可见时，以 `spawnProbability` 概率让一只小猫在 header 空白区滑入、
/// 原地跑步（固定待机帧率）。点一下打开 RunCat 仓库并关掉面板。小猫在面板关闭前一直保持。
///
/// 模型由主线程持有；Timer 固定排在 `RunLoop.main`，回调直接在 MainActor 上推进状态。
final class HeaderCatCameoModel: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var frameIndex = 0

    private var frameTimerBox: ScheduledTimerBox?

    /// 每次面板打开时的客串触发概率。
    static let spawnProbability = 0.03

    /// RunCat 官方仓库。与开源声明里的同一条链接。
    static let repositoryURL = URL(string: "https://github.com/Kyome22/RunCatNeo")!

    /// 待机帧间隔（固定，不随负载变化）。
    private static let idleFrameInterval: TimeInterval = 0.18

    /// 面板由隐藏变为可见时调用：摧骰子决定这次是否客串。
    func panelDidAppear() {
        guard !isVisible else { return }
        guard Double.random(in: 0 ..< 1) < Self.spawnProbability else { return }
        spawn()
    }

    /// 面板隐藏时调用：清理客串状态。这是小猫唯一的退场时机。
    func panelDidDisappear() {
        retire()
    }

    /// 点一下打开 RunCat 仓库。面板由调用方随后关闭。
    func registerTap() {
        guard isVisible else { return }
        NSWorkspace.shared.open(Self.repositoryURL)
    }

    private func spawn() {
        frameIndex = 0
        isVisible = true
        startFrameTimer()
    }

    private func retire() {
        isVisible = false
        frameIndex = 0
        frameTimerBox?.invalidate()
        frameTimerBox = nil
    }

    private func startFrameTimer() {
        frameTimerBox?.invalidate()
        let timer = Timer(timeInterval: Self.idleFrameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.frameIndex = (self.frameIndex + 1) % MenuBarCatIcon.frameCount
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimerBox = ScheduledTimerBox(timer)
    }
}

/// header 里的小猫客串视图：一只按待机帧率原地跑步的模板小猫，点击热区即本体。
/// 用 `.highPriorityGesture` 抢在父级双击手势之前响应单击，避免落进 header 标题区的
/// 「双击展开」判定。
struct HeaderCatCameo: View {
    @ObservedObject var model: HeaderCatCameoModel
    let tint: Color
    /// 打开仓库后关闭菜单栏面板。
    let onOpenRepository: () -> Void

    var body: some View {
        if model.isVisible {
            Image(nsImage: MenuBarCatIcon.image(frame: model.frameIndex))
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 14)
                .foregroundStyle(tint)
                .contentShape(Rectangle())
                .help(String(localized: "cat-cameo.open"))
                .accessibilityLabel(String(localized: "cat-cameo.open"))
                .highPriorityGesture(
                    TapGesture().onEnded {
                        model.registerTap()
                        onOpenRepository()
                    }
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: model.isVisible)
        }
    }
}
