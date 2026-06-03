import SwiftUI

struct KittyCatView: View {
    let module: MonitorModule
    let size: CGFloat
    var compact = false

    @State private var motion = false

    var body: some View {
        ZStack {
            aura

            tail
                .rotationEffect(.degrees(tailAngle), anchor: .bottomLeading)
                .offset(x: size * 0.25, y: size * 0.18)

            torso
                .scaleEffect(bodyScale, anchor: .bottom)
                .offset(y: bodyDrop)

            head
                .scaleEffect(headScale, anchor: .bottom)
                .rotationEffect(.degrees(headTilt))
                .offset(x: headOffset.x, y: headOffset.y)

            if showsSweat {
                sweat
                    .offset(x: size * 0.25, y: -size * 0.20)
            }

            if module.kind == .storage, module.severity == .critical, !compact {
                burp
                    .offset(x: size * 0.35, y: -size * 0.05)
            }
        }
        .frame(width: size, height: size)
        .drawingGroup()
        .onAppear {
            motion = true
        }
        .animation(.easeInOut(duration: animationDuration).repeatForever(autoreverses: true), value: motion)
    }

    private var aura: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        module.severity.tint.opacity(compact ? 0.26 : 0.20),
                        Color.white.opacity(0.02)
                    ],
                    center: .center,
                    startRadius: size * 0.08,
                    endRadius: size * 0.52
                )
            )
            .scaleEffect(motion && module.severity != .calm ? 1.08 : 0.96)
    }

    private var torso: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                .fill(catFill)
                .frame(width: size * 0.48, height: size * 0.36)
                .shadow(color: Color(red: 0.45, green: 0.20, blue: 0.08).opacity(0.14), radius: size * 0.035, y: size * 0.025)

            belly
                .offset(y: size * 0.08)

            paws
                .offset(y: size * 0.23)
        }
        .offset(y: size * 0.18)
    }

    private var belly: some View {
        Ellipse()
            .fill(Color.white.opacity(0.45))
            .frame(width: bellySize.width, height: bellySize.height)
    }

    private var paws: some View {
        HStack(spacing: size * 0.20) {
            Capsule()
                .fill(Color(red: 0.72, green: 0.42, blue: 0.28).opacity(0.22))
                .frame(width: size * 0.10, height: size * 0.04)
            Capsule()
                .fill(Color(red: 0.72, green: 0.42, blue: 0.28).opacity(0.22))
                .frame(width: size * 0.10, height: size * 0.04)
        }
    }

    private var head: some View {
        ZStack {
            ear
                .offset(x: -size * 0.18, y: -size * 0.19)
            ear
                .scaleEffect(x: -1, y: 1)
                .offset(x: size * 0.18, y: -size * 0.19)

            RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                .fill(catFill)
                .frame(width: size * 0.54, height: size * 0.42)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                        .stroke(Color.white.opacity(0.36), lineWidth: max(1, size * 0.012))
                )

            blush
                .offset(y: size * 0.04)

            eyes
                .offset(y: eyeOffset)

            mouth
                .offset(y: size * 0.105)
        }
        .offset(y: -size * 0.06)
    }

    private var ear: some View {
        SoftTriangle()
            .fill(catFill)
            .frame(width: size * 0.19, height: size * 0.18)
            .overlay(
                SoftTriangle()
                    .fill(Color(red: 0.98, green: 0.56, blue: 0.50).opacity(0.38))
                    .frame(width: size * 0.10, height: size * 0.09)
                    .offset(y: size * 0.035)
            )
    }

    private var eyes: some View {
        HStack(spacing: size * 0.14) {
            eye
            eye
        }
    }

    private var eye: some View {
        Capsule()
            .fill(Color(red: 0.13, green: 0.11, blue: 0.10).opacity(0.86))
            .frame(width: size * 0.045, height: eyeHeight)
    }

    private var blush: some View {
        HStack(spacing: size * 0.24) {
            Circle()
                .fill(Color(red: 0.96, green: 0.38, blue: 0.34).opacity(compact ? 0 : 0.20))
                .frame(width: size * 0.08, height: size * 0.035)
            Circle()
                .fill(Color(red: 0.96, green: 0.38, blue: 0.34).opacity(compact ? 0 : 0.20))
                .frame(width: size * 0.08, height: size * 0.035)
        }
    }

    private var mouth: some View {
        Group {
            if module.kind == .gpu, module.severity != .calm {
                Capsule()
                    .fill(Color.black.opacity(0.46))
                    .frame(width: size * 0.11, height: max(1, size * 0.014))
            } else {
                Path { path in
                    path.move(to: CGPoint(x: size * -0.045, y: 0))
                    path.addQuadCurve(to: CGPoint(x: 0, y: size * 0.025), control: CGPoint(x: size * -0.02, y: size * 0.03))
                    path.addQuadCurve(to: CGPoint(x: size * 0.045, y: 0), control: CGPoint(x: size * 0.02, y: size * 0.03))
                }
                .stroke(Color.black.opacity(0.46), style: StrokeStyle(lineWidth: max(1, size * 0.014), lineCap: .round))
                .frame(width: size * 0.13, height: size * 0.06)
            }
        }
    }

    private var tail: some View {
        Capsule(style: .continuous)
            .fill(catFill)
            .frame(width: size * 0.11, height: size * 0.38)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: max(1, size * 0.01))
            )
    }

    private var sweat: some View {
        VStack(spacing: size * 0.04) {
            Image(systemName: "drop.fill")
                .font(.system(size: size * 0.11, weight: .bold))
            if !compact {
                Image(systemName: "drop.fill")
                    .font(.system(size: size * 0.08, weight: .bold))
                    .offset(x: size * 0.06)
            }
        }
        .foregroundStyle(Color(red: 0.12, green: 0.50, blue: 0.94).opacity(motion ? 0.95 : 0.36))
        .offset(y: motion ? size * 0.02 : -size * 0.02)
    }

    private var burp: some View {
        Text("hic")
            .font(.system(size: size * 0.10, weight: .bold, design: .rounded))
            .foregroundStyle(module.severity.tint.opacity(motion ? 0.92 : 0.22))
            .scaleEffect(motion ? 1.10 : 0.88)
    }

    private var catFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.83, blue: 0.60),
                Color(red: 0.96, green: 0.61, blue: 0.38)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bodyScale: CGFloat {
        switch module.kind {
        case .storage:
            1 + module.value / 180
        case .gpu:
            motion ? 1.04 : 0.98
        default:
            1
        }
    }

    private var headScale: CGFloat {
        module.kind == .memory ? 1 + module.value / 230 : 1
    }

    private var bellySize: CGSize {
        if module.kind == .storage {
            return CGSize(width: size * (0.20 + module.value / 170), height: size * (0.13 + module.value / 520))
        }
        return CGSize(width: size * 0.25, height: size * 0.13)
    }

    private var headTilt: Double {
        switch module.kind {
        case .cpu where module.severity != .calm:
            motion ? -9 : 7
        case .gpu:
            motion ? -3 : 3
        default:
            motion && !compact ? 1.5 : -1
        }
    }

    private var headOffset: CGPoint {
        switch module.kind {
        case .cpu where module.severity != .calm:
            CGPoint(x: motion ? -size * 0.035 : size * 0.035, y: motion ? -size * 0.09 : -size * 0.03)
        case .gpu:
            CGPoint(x: motion ? size * 0.015 : -size * 0.015, y: -size * 0.02)
        default:
            CGPoint(x: 0, y: -size * 0.02)
        }
    }

    private var bodyDrop: CGFloat {
        module.kind == .battery && module.severity != .calm ? size * 0.06 : 0
    }

    private var tailAngle: Double {
        if module.kind == .battery && module.severity != .calm {
            return motion ? -10 : -2
        }
        if module.kind == .gpu {
            return motion ? 26 : 10		
        }
        return motion ? 18 : 5
    }

    private var eyeHeight: CGFloat {
        if module.kind == .battery && module.severity != .calm {
            return max(1, size * 0.020)
        }
        return size * 0.07		
    }

    private var eyeOffset: CGFloat {
        if module.kind == .battery && module.severity != .calm {
            return size * 0.005
        }
        return -size * 0.015
    }

    private var showsSweat: Bool {
        module.kind == .cpu && module.severity != .calm
    }

    private var animationDuration: Double {
        switch module.kind {
        case .cpu where module.severity != .calm:
            MonitorConstants.cpuAnimationDuration
        case .battery where module.severity != .calm:
            MonitorConstants.batteryAnimationDuration
        case .gpu:
            MonitorConstants.gpuAnimationDuration
        default:
            MonitorConstants.defaultAnimationDuration
        }
    }
}

private struct SoftTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.15))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.midY))
        return path
    }
}
