import SwiftUI

struct ProgressMeter: View {
    let value: Double
    let tint: Color
    let theme: MonitorPanelTheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.trackFill)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(1, max(0, value / 100)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: value)
    }
}
