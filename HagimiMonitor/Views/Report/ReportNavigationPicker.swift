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
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Picker(title, selection: $selection, content: content)
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.regular)
        }
    }
}
