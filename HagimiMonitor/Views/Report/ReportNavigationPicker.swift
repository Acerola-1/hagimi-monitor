import AppKit
import SwiftUI

/// 同级内容导航使用系统标签控件，材质、拖动和键盘行为由系统提供。
struct ReportNavigationPicker<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 27.0, *) {
            Picker(title, selection: $selection, content: content)
                .pickerStyle(.tabs)
                .labelsHidden()
                .controlSize(.large)
                // 采用 .regular 材质而非 .interactive：避免鼠标按下时因系统弹性位移缩放导致控件在卡片内发生纵向高度跳动。
                .glassEffect(.regular, in: .capsule)
                .background(SegmentedControlLayoutSettler().allowsHitTesting(false))
        } else {
            Picker(title, selection: $selection, content: content)
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.regular)
        }
    }
}

/// 解决 macOS 27 上 SwiftUI tabs picker 初次加载时 NSSegmentedControl 文本度量晚于外层 glassEffect 布局导致的宽度未同步与重影问题。
private struct SegmentedControlLayoutSettler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettlerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SettlerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                // 仅在当前 Picker 的就近容器祖先（最多 2 层）内查找关联的 NSSegmentedControl，
                // 严禁无上限递归向上遍历至 window.contentView，防止误伤顶栏等同窗口其他选择器。
                var current: NSView? = self.superview
                var depth = 0
                while let p = current, depth < 3 {
                    if let seg = self.findSegmentedControl(in: p) {
                        seg.invalidateIntrinsicContentSize()
                        seg.sizeToFit()
                        seg.superview?.needsLayout = true
                        p.needsLayout = true
                        window.layoutIfNeeded()
                        break
                    }
                    current = p.superview
                    depth += 1
                }
            }
        }

        private func findSegmentedControl(in root: NSView) -> NSSegmentedControl? {
            if let seg = root as? NSSegmentedControl { return seg }
            for sub in root.subviews {
                if let found = findSegmentedControl(in: sub) { return found }
            }
            return nil
        }
    }
}

