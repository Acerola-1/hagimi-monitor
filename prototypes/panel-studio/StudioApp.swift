import AppKit
import SwiftUI
import Combine

@main struct StudioApp: App {
    @StateObject private var model = Studio()
    var body: some Scene {
        Window("Hagimi · 主面板设计室",id:"studio") {
            StudioWindow(model:model)
        }.defaultSize(width:810,height:755)
        MenuBarExtra("Hagimi 面板原型",systemImage:"waveform.path.ecg.rectangle") {
            MenuPreview(model:model)
        }.menuBarExtraStyle(.window)
    }
}

struct MenuPreview: View {
    @ObservedObject var model: Studio
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing:0) {
            PanelFace(model:model).frame(height: min(660,(NSScreen.main?.visibleFrame.height ?? 800)-130))
            Button("打开设计室") { openWindow(id:"studio"); NSApp.activate(ignoringOtherApps:true) }.padding(8)
        }.environment(\.colorScheme,model.dark ? .dark : .light)
    }
}

struct StudioWindow: View {
    @ObservedObject var model: Studio
    var body: some View {
        HStack(spacing:0) {
            ScrollView { controls.frame(minHeight:565) }.scrollIndicators(.hidden).frame(width:184).padding(.horizontal,18).frame(maxHeight:.infinity,alignment:.top)
                .background(.regularMaterial)
            Divider()
            ZStack {
                LinearGradient(colors:model.dark ? [Color(rgb:0x23343C),Color(rgb:0x111C24)] : [Color(rgb:0xD8E4E4),Color(rgb:0xB8CACC)],startPoint:.topLeading,endPoint:.bottomTrailing)
                PanelFace(model:model)
                    .shadow(color:.black.opacity(model.dark ? 0.25 : 0.13),radius:14,y:6)
                    .padding(.vertical,15)
            }.frame(minWidth:500,maxWidth:.infinity)
        }.frame(minWidth:732,minHeight:540)
        .preferredColorScheme(model.dark ? .dark : .light)

    }
    private var controls: some View {
        VStack(alignment:.leading,spacing:18) {
            VStack(alignment:.leading,spacing:4) {
                Image(systemName:"waveform.path.ecg.rectangle.fill").font(.title).foregroundStyle(model.ink.accent)
                Text("面板设计室").font(.system(size:23,weight:.bold))
                Text("HagimiMonitor").font(.callout).foregroundStyle(.secondary)
            }.padding(.top,21)
            Divider()
            VStack(alignment:.leading,spacing:4) {
                label("配色")
                ForEach(Style.allCases,id:\.self) { style in
                    Button {
                        model.style = style
                    } label: {
                        HStack {
                            let ink = Ink(style:style,dark:model.dark)
                            HStack(spacing:-2) {
                                ForEach([Module.cpu,.gpu,.network],id:\.self) { mod in
                                    Circle().fill(ink.tint(mod)).frame(width:12,height:12)
                                }
                            }
                            Text(style.rawValue); Spacer()
                            if model.style == style { Image(systemName:"checkmark").fontWeight(.semibold) }
                        }.padding(.horizontal,8).frame(height:29).contentShape(Rectangle())
                        .background(RoundedRectangle(cornerRadius:6).fill(Color.primary.opacity(model.style == style ? 0.09 : 0)))
                    }.buttonStyle(.plain).accessibilityLabel(style.rawValue)
                }
            }
            VStack(alignment:.leading,spacing:6) {
                label("外观")
                Picker("外观",selection:$model.dark) {
                    Text("浅色").tag(false); Text("深色").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment:.leading,spacing:6) {
                label("面板宽度 · pt")
                Picker("宽度",selection:$model.width) {
                    ForEach([300,340,400,460],id:\.self) { Text(String($0)).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            Divider()
            VStack(alignment:.leading,spacing:6) {
                label("模拟负载")
                Picker("模拟负载",selection:$model.load) {
                    ForEach(Load.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                Toggle("持续采样",isOn:$model.playing).toggleStyle(.switch).controlSize(.small).padding(.top,5)
            }
            VStack(alignment:.leading,spacing:6) {
                label("设备组合")
                Picker("设备组合",selection:$model.rig) {
                    ForEach(Rig.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                Button("收起全部模块") { model.expanded.removeAll() }.controlSize(.small)
            }
            Spacer(minLength:4)
            Label("全部为模拟数据",systemImage:"testtube.2").font(.caption).foregroundStyle(.secondary).padding(.bottom,16)
        }
    }
    private func label(_ title:String) -> some View {
        Text(title).font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary)
    }
}
