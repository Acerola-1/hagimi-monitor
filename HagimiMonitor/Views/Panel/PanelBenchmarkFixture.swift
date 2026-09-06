import AppKit

/// 原生动画对照的真实输入夹具。仅显式指定文件时读写，普通采样不经过该路径。
struct PanelBenchmarkInputs {
    let modules: [MonitorModule]
    let cpu: [TopCPUProcess]
    let gpu: [TopGPUProcess]
    let memory: [TopMemoryProcess]

    @MainActor
    static func loadOrCapture(store: MonitorStore, path: String) throws -> Self {
        let url = URL(fileURLWithPath: path)
        let fixture: Fixture
        if FileManager.default.fileExists(atPath: path) {
            fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        } else {
            fixture = Fixture(capturedAt: Date(), modules: store.modules.filter { [.cpu, .gpu, .memory].contains($0.kind) }.map(Module.init),
                cpu: store.topCPUProcesses.map { ProcessValue(pid: $0.pid, name: $0.name, usage: $0.cpuUsage, icon: $0.icon?.tiffRepresentation, translated: $0.translated) },
                gpu: store.topGPUProcesses.map { ProcessValue(pid: $0.pid, name: $0.name, usage: $0.gpuUsage, icon: $0.icon?.tiffRepresentation, api: $0.api) },
                memory: store.topMemoryProcesses.map { ProcessValue(pid: $0.pid, name: $0.name, memory: $0.memoryUsage, icon: $0.icon?.tiffRepresentation) })
            try JSONEncoder().encode(fixture).write(to: url, options: .atomic)
        }
        return Self(modules: fixture.modules.compactMap(\.value),
            cpu: fixture.cpu.map { TopCPUProcess(pid: $0.pid, name: $0.name, cpuUsage: $0.usage ?? 0, icon: $0.image, translated: $0.translated ?? false) },
            gpu: fixture.gpu.map { TopGPUProcess(pid: $0.pid, name: $0.name, gpuUsage: $0.usage ?? 0, api: $0.api ?? "", icon: $0.image) },
            memory: fixture.memory.map { TopMemoryProcess(pid: $0.pid, name: $0.name, memoryUsage: $0.memory ?? 0, icon: $0.image) })
    }

    private struct Fixture: Codable {
        let capturedAt: Date
        let modules: [Module]
        let cpu: [ProcessValue]
        let gpu: [ProcessValue]
        let memory: [ProcessValue]
    }

    private struct ProcessValue: Codable {
        let pid: Int32
        let name: String
        var usage: Double? = nil
        var memory: UInt64? = nil
        var icon: Data? = nil
        var translated: Bool? = nil
        var api: String? = nil
        var image: NSImage? { icon.flatMap(NSImage.init(data:)) }
    }

    private struct Metric: Codable {
        let name: String
        let value: String
        let number: Double?
        let unit: String?
    }

    private struct Core: Codable {
        let index: Int
        let usage: Double
        let performance: Bool
    }

    private struct Module: Codable {
        let kind: String
        let context: String?
        let reading: Double
        let summary: String
        let metrics: [Metric]
        let samples: [Double]
        let pressure: Int?
        let pressureValue: Double?
        let pressureSamples: [Double]
        let cores: [Core]?
        let performanceUsage: Double?
        let efficiencyUsage: Double?
        let placeholder: Bool

        init(_ source: MonitorModule) {
            kind = source.kind.rawValue
            context = source.context
            reading = source.value
            summary = source.summary
            metrics = source.metrics.map { Metric(name: $0.name, value: $0.value, number: $0.numericValue, unit: $0.unit) }
            samples = source.samples
            pressure = source.pressure?.rawValue
            pressureValue = source.pressureValue
            pressureSamples = source.pressureSamples
            cores = source.cpuCoreDetail?.cores.map { Core(index: $0.index, usage: $0.usage, performance: $0.isPerformance) }
            performanceUsage = source.cpuCoreDetail?.performanceUsage
            efficiencyUsage = source.cpuCoreDetail?.efficiencyUsage
            placeholder = source.isPlaceholder
        }

        var value: MonitorModule? {
            guard let kind = MonitorKind(rawValue: kind) else { return nil }
            let cpu = cores.flatMap { cores -> CPUCoreDetail? in
                guard let performanceUsage else { return nil }
                return CPUCoreDetail(cores: cores.map { CPUCoreLoad(index: $0.index, usage: $0.usage, isPerformance: $0.performance) },
                    performanceUsage: performanceUsage, efficiencyUsage: efficiencyUsage)
            }
            return MonitorModule(kind: kind, context: context, value: reading, summary: summary,
                metrics: metrics.map { MonitorMetric(name: $0.name, value: $0.value, numericValue: $0.number, unit: $0.unit) },
                samples: samples, pressure: pressure.flatMap(MemoryPressureLevel.init(rawValue:)),
                pressureValue: pressureValue, pressureSamples: pressureSamples, cpuCoreDetail: cpu, isPlaceholder: placeholder)
        }
    }
}
