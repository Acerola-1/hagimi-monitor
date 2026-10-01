import AppKit

/// 显式 Bench 下有限次数地操作自有宿主，核对可见租约和采样；正式启动没有循环任务。
@MainActor enum PanelLifecycleFixture {
    static func run(app: AppDelegate) async {
        let store = app.store
        var failures = 0
        func check(_ stage: String, menu: Bool, pinned: Bool) {
            let valid = app.fluidPanelController.isVisible == menu
                && app.pinnedPanelController.isVisible == pinned
                && store.isPanelVisible == (menu || pinned)
            if !valid { failures += 1 }
            NSLog("[panel-lifecycle] stage=%@ menu=%d pinned=%d store-visible=%d valid=%d sample=%@ statistics=%d",
                stage, app.fluidPanelController.isVisible ? 1 : 0,
                app.pinnedPanelController.isVisible ? 1 : 0, store.isPanelVisible ? 1 : 0,
                valid ? 1 : 0, String(describing: store.modules.first?.samples.last),
                store.settings.statisticsEnabled ? 1 : 0)
        }
        try? await Task.sleep(for: .seconds(2))
        app.fluidPanelController.dismissPanelForSettings()
        app.pinnedPanelController.hide()
        for cycle in 0..<6 {
            guard !Task.isCancelled else { return }
            app.fluidPanelController.presentBenchmarkHost()
            try? await Task.sleep(for: .seconds(2))
            check("\(cycle)-menu", menu: true, pinned: false)
            app.pinnedPanelController.show()
            try? await Task.sleep(for: .seconds(2))
            check("\(cycle)-both", menu: true, pinned: true)
            app.fluidPanelController.dismissPanelForSettings()
            try? await Task.sleep(for: .seconds(1))
            check("\(cycle)-pinned", menu: false, pinned: true)
            app.pinnedPanelController.hide()
            try? await Task.sleep(for: .seconds(2))
            check("\(cycle)-hidden", menu: false, pinned: false)
        }
        NSLog("[panel-lifecycle] complete failures=%d", failures)
    }
}
