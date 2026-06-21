import SwiftUI

struct ContentView: View {
    @ObservedObject var store: MonitorStore

    var body: some View {
        MonitorPanelView(store: store)
            .padding(18)
    }
}
