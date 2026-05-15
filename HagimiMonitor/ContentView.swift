//
//  ContentView.swift
//  HagimiMonitor
//
//  Created by Acerola on 2026/5/11.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var store: MonitorStore

    var body: some View {
        MonitorPanelView(store: store)
            .padding(18)
    }
}
