import AppKit
import Combine
import SwiftUI

/// 面板 header 小猫「客串」彩蛋的状态机（致敬 RunCat）。
///
/// 每次面板由隐藏变为可见时，以 `spawnProbability` 概率让一只小猫在 header 空白区滑入、
/// 原地跑步（固定待机帧率）。点一下即弹 RunCat 致谢卡片。小猫不定时退场、
/// 也不因看完弹窗而退场——一直保持到面板关闭时（`panelDidDisappear`）才消失。
///
/// 不标 `@MainActor`：与 `MenuBarLoadAnimator` 一致，所有 Timer 都排在 `RunLoop.main`、
/// 在主线程推进 `@Published`，避免 Swift 并发隔离对 Timer 闭包的额外约束。
final class HeaderCatCameoModel: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var frameIndex = 0
    /// 致谢卡片是否展示。由视图层双向绑定（点击关闭按钮置回 false）。
    @Published var showThanks = false

    private var frameTimer: Timer?

    /// 每次面板打开时的客串触发概率（设计定稿值）。
    static let spawnProbability = 0.05

    /// 待机帧间隔（固定，不随负载变化）。
    private static let idleFrameInterval: TimeInterval = 0.18

    /// 面板由隐藏变为可见时调用：摧骰子决定这次是否客串。
    func panelDidAppear() {
        guard !isVisible else { return }
        guard Double.random(in: 0 ..< 1) < Self.spawnProbability else { return }
        spawn()
    }

    /// 面板隐藏时调用：清理客串状态并收起致谢卡片。——这是小猫唯一的退场时机。
    func panelDidDisappear() {
        retire()
        showThanks = false
    }

    /// 处理一次点击：点一下即弹 RunCat 致谢卡片，小猫仍保持可见、继续跑步，
    /// 直到面板关闭才消失。
    func registerTap() {
        guard isVisible else { return }
        showThanks = true
    }

    private func spawn() {
        frameIndex = 0
        isVisible = true
        startFrameTimer()
    }

    private func retire() {
        isVisible = false
        frameIndex = 0
        frameTimer?.invalidate()
        frameTimer = nil
    }

    private func startFrameTimer() {
        frameTimer?.invalidate()
        let timer = Timer(timeInterval: Self.idleFrameInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex = (self.frameIndex + 1) % MenuBarCatIcon.frameCount
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    deinit {
        frameTimer?.invalidate()
    }
}

/// header 里的小猫客串视图：一只按待机帧率原地跑步的模板小猫，点击热区即本体。
/// 用 `.highPriorityGesture` 抢在父级双击手势之前响应单击，避免落进 header 标题区的
/// 「双击展开」判定。
struct HeaderCatCameo: View {
    @ObservedObject var model: HeaderCatCameoModel
    let tint: Color

    var body: some View {
        if model.isVisible {
            Image(nsImage: MenuBarCatIcon.image(frame: model.frameIndex))
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 14)
                .foregroundStyle(tint)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture().onEnded {
                        model.registerTap()
                    }
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: model.isVisible)
        }
    }
}

/// 激活猫模式时弹出的致谢卡片。作为面板内容的居中 overlay 呈现（不用系统 `.sheet`/`.popover`，
/// 避免在自建无边框 `NSPanel` 里抢焦点导致面板被 resignKey 关闭）。
///
/// 风格对齐面板本体：小巧（定宽 210pt）、圆体小字号、细描边毛玻璃、轻阴影；
/// 按钮是自绘的小胶囊（`.plain` 样式），文字 `lineLimit(1) + fixedSize` 保证永不折行。
struct CatThanksCard: View {
    let onClose: () -> Void

    private let runCatURL = URL(string: "https://github.com/Kyome22/RunCatNeo")!

    var body: some View {
        ZStack {
            // 半透明遮罩：点击遮罩也可关闭。
            Color.black.opacity(0.22)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                Image(nsImage: MenuBarCatIcon.image(frame: 2))
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 22)
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(.bottom, 9)

                Text(String(localized: "cat-cameo.thanks.title"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.bottom, 5)

                Text(String(localized: "cat-cameo.thanks.body"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(runCatURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.pink)
                            Text(String(localized: "cat-cameo.thanks.support"))
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.primary.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.10), lineWidth: 0.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onClose) {
                        Text(String(localized: "cat-cameo.thanks.close"))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.primary.opacity(0.05)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            // 220pt：容得下英文局部化里 "Support RunCat" + "Got it" 两个胶囊不换行。
            .frame(width: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        .transition(.opacity)
    }
}
