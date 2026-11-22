import SwiftUI

struct Trace: View {
    let samples: [Double]
    let color: Color
    var filled = true
    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }
            let points = samples.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) / CGFloat(samples.count - 1) * (size.width - 5) + 2,
                        y: (1 - v / 100) * (size.height - 5) + 2)
            }
            var stroke = Path()
            stroke.addLines(points)
            if filled {
                var area = stroke
                area.addLine(to: CGPoint(x: points.last!.x, y: size.height))
                area.addLine(to: CGPoint(x: 2, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.44),color.opacity(0.025)]), startPoint: .zero, endPoint: CGPoint(x: 0,y: size.height)))
            }
            context.stroke(stroke, with: .color(color), lineWidth: filled ? 1.8 : 1.3)
            if filled, let last = points.last {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 2.4,y: last.y - 2.4,width: 4.8,height: 4.8)), with: .color(color))
            }
        }.accessibilityHidden(true)
    }
}

struct Datum: Identifiable {
    let label: String
    let value: String
    let minimum: CGFloat
    var id: String { label }
    let stackedMinimum: CGFloat?
    init(_ label: String, _ value: String, _ minimum: CGFloat = 111, stackedMinimum: CGFloat? = nil) {
        self.stackedMinimum = stackedMinimum
        self.label = label; self.value = value; self.minimum = minimum
    }
}

struct DataGrid: View {
    let fields: [Datum]
    let width: CGFloat
    let ink: Ink
    private var rows: [[Datum]] {
        var rows = [[Datum]](), i = 0
        while i < fields.count {
            if i + 1 < fields.count && (fields[i].stackedMinimum ?? fields[i].minimum) + (fields[i+1].stackedMinimum ?? fields[i+1].minimum) + 16 <= width {
                rows.append([fields[i], fields[i+1]]); i += 2
            } else { rows.append([fields[i]]); i += 1 }
        }
        return rows
    }
    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.first?.id) { row in
                Rectangle().fill(ink.line).frame(height: 0.5)
                HStack(spacing: 16) {
                    ForEach(row) { field in
                        let stacked = row.count == 2 && row.map(\.minimum).reduce(0,+) + 16 > width
                        let layout = stacked ? AnyLayout(VStackLayout(alignment:.leading,spacing:2)) : AnyLayout(HStackLayout(spacing:4))
                        layout {
                            Text(field.label).foregroundStyle(.secondary)
                            if !stacked { Spacer(minLength: 2) }
                            Text(field.value).fontWeight(.medium).monospacedDigit()
                        }.frame(minWidth: stacked ? (field.stackedMinimum ?? field.minimum) : field.minimum,
                                maxWidth: .infinity, alignment:.leading)
                    }
                }.font(.system(size: 11)).padding(.vertical, 5)
            }
        }
    }
}

struct CoreLane: View {
    @ObservedObject var model: Studio
    let range: Range<Int>
    let name: String
    let tint: Color
    @State private var hovered: Int?
    var body: some View {
        let samples = range.map { model.core($0, at: model.second) }
        HStack(spacing: 8) {
            Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(width: 35, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(range, id: \.self) { index in
                    let v = model.core(index, at: model.second)
                    ZStack {
                        Circle().strokeBorder(model.ink.track, lineWidth: 3)
                        if v > 0 {
                            Circle().inset(by: 1.5).trim(from: 0,to: v / 100)
                                .stroke(tint, style: StrokeStyle(lineWidth: 3,lineCap: .round)).rotationEffect(.degrees(-90))
                        }
                    }.frame(width: 17,height: 17).contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hovered = index } else if hovered == index { hovered = nil }
                    }.accessibilityLabel("核心 \(index + 1)，\(Int(v))%")
                }
            }
            Spacer(minLength: 0)
            if let i = hovered {
                Text("#\(i+1) · \(Int(model.core(i, at:model.second)))%").foregroundStyle(tint)
            } else {
                Text("\(Int((samples.reduce(0,+) / Double(samples.count)).rounded()))%")
            }
        }.font(.system(size: 11,weight: .semibold)).monospacedDigit()
    }
}

struct PanelFace: View {
    @ObservedObject var model: Studio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var ink: Ink { model.ink }
    @State private var footer: String?
    private var inner: CGFloat { CGFloat(model.width) - 48 }
    private func trace(_ mod: Module, count: Int, filled: Bool) -> some View {
        Trace(samples: (model.second-count+1...model.second).map { model.level(mod, $0) }, color: ink.tint(mod), filled: filled)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "waveform.path.ecg.rectangle").foregroundStyle(ink.accent)
                Text("系统监控").font(.system(size: 15,weight: .bold))
                Spacer()
                Circle().fill(model.playing ? ink.e : ink.track).frame(width: 6,height: 6)
                Text(model.playing ? "模拟实时" : "模拟暂停").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal,14).padding(.vertical,11)
            Divider()
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Module.allCases) { mod in moduleRow(mod) }
                }.padding(7)
            }.scrollIndicators(.hidden)
            Divider()
            HStack {
                ForEach(["监视器","工具","设置"],id:\.self) { title in
                    Button {
                        footer = title
                    } label: {
                        Label(title,systemImage:title == "监视器" ? "waveform.path.ecg" : title == "工具" ? "wrench.and.screwdriver" : "gearshape")
                            .font(.caption).frame(maxWidth:.infinity).padding(.vertical,5)
                            .background(RoundedRectangle(cornerRadius:6).fill(ink.accent.opacity(0.08)))
                    }.buttonStyle(.plain).popover(isPresented:Binding(get:{footer == title},set:{ if !$0 { footer = nil } })) {
                        VStack(alignment:.leading,spacing:9) {
                            if title == "监视器" { Ranking(module:.cpu,model:model) }
                            else if title == "工具" {
                                Toggle("持续模拟采样",isOn:$model.playing)
                                Button("收起所有模块") { model.expanded.removeAll(); footer = nil }
                            } else {
                                Picker("主题",selection:$model.style) {
                                    ForEach(Style.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                                }
                                Toggle("深色外观",isOn:$model.dark)
                            }
                        }.frame(width:190).padding(12)
                    }
                }
            }.padding(7)
        }
        .frame(maxHeight:model.expanded.isEmpty ? 504 : .infinity)
        .frame(width: CGFloat(model.width))
        .background(.regularMaterial)
        .background(model.dark ? Color(rgb:0x192329) : Color(rgb:0xEEF3F4))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(ink.line))
        .environment(\.colorScheme,model.dark ? .dark : .light)
    }

    private func moduleRow(_ mod: Module) -> some View {
        let open = model.expanded.contains(mod)
        return VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { model.toggle(mod) }
            } label: {
                ModuleSummary(model:model,module:mod,open:open)
            }.buttonStyle(.plain).accessibilityLabel("\(mod.rawValue)，\(model.reading(mod))，\(open ? "收起" : "展开")")
            if open {
                VStack(alignment:.leading,spacing:8) {
                    if mod == .cpu { cpuContent } else if [.fan,.display,.bluetooth].contains(mod) { EquipmentDetail(model:model,module:mod) } else { DetailContent(model:model,module:mod,inner:inner) }
                }.padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
        .frame(maxWidth:.infinity)
        .background {
            let fill = model.style == .graphite ? Color.primary : ink.tint(mod)
            RoundedRectangle(cornerRadius:9).fill(LinearGradient(colors:[fill.opacity(model.style == .vivid ? 0.17 : 0.07),fill.opacity(open ? 0.035 : 0.02)],startPoint:.topLeading,endPoint:.bottomTrailing))
        }
        .overlay(alignment:.bottom) { if !open { Rectangle().fill(ink.line).frame(height:0.5).padding(.horizontal,9) } }
    }

    private var cpuContent: some View {
        let system = model.cpuValue / 3
        return VStack(alignment:.leading,spacing:8) {
            HStack(alignment:.bottom,spacing:12) {
                VStack(alignment:.leading,spacing:0) {
                    Text("总负载").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment:.firstTextBaseline,spacing:2) {
                        Text("\(model.cpuValue)").font(.system(size:40,weight:.semibold,design:.rounded)).monospacedDigit()
                        Text("%").foregroundStyle(ink.accent)
                    }
                }
                VStack(alignment:.trailing,spacing:2) {
                    trace(.cpu, count:60, filled:true).frame(height:34)
                    Text("近 60 秒").font(.system(size:9)).foregroundStyle(.secondary)
                }
            }
            Divider()
            CoreLane(model:model,range:0..<6,name:"性能核",tint:ink.p)
            CoreLane(model:model,range:6..<10,name:"能效核",tint:ink.e)
            DataGrid(fields:[Datum("系统","\(system)%"),Datum("用户","\(model.cpuValue-system)%"),Datum("空闲","\(100-model.cpuValue)%"),Datum("进程","412"),Datum("运行时间","8 天 13 小时",156,stackedMinimum:136),Datum("热压力","\(model.temp)°C · 正常",163,stackedMinimum:136)],width: inner,ink:ink)
            Ranking(module:.cpu,model:model)
        }
    }
}
