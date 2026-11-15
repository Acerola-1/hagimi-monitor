import Foundation
import OSLog

struct SystemMonitorSnapshot: Sendable {
    var modules: [MonitorModule]
}

nonisolated final class SystemMonitorSampler: Sendable {
    private let cpuSampler: CPUSampler
    private let networkSampler: NetworkSampler
    private let samplers: [MonitorKind: MonitorSampler]
    #if DIRECT_DISTRIBUTION
    private let powerSampler: any IOReportPowerSampling
    init(powerSampler: any IOReportPowerSampling = IOReportPowerSampler.shared) {
        self.powerSampler = powerSampler
        let cpu = CPUSampler()
        let network = NetworkSampler()
        cpuSampler = cpu
        networkSampler = network
        samplers = [.cpu: cpu, .gpu: GPUSampler(), .memory: MemorySampler(),
                    .storage: StorageSampler(), .network: network, .battery: BatterySampler()]
    }
    #else

    init() {
        let cpu = CPUSampler()
        let network = NetworkSampler()
        cpuSampler = cpu
        networkSampler = network
        samplers = [
            .cpu: cpu,
            .gpu: GPUSampler(),
            .memory: MemorySampler(),
            .storage: StorageSampler(),
            .network: network,
            .battery: BatterySampler()
        ]
    }
    #endif

    /// 菜单栏含 CPU 温度,或任一面板可见时为 true。false 时 CPU 占用照常采样,只是不读温度键。
    func setTemperatureReadsEnabled(_ enabled: Bool) {
        cpuSampler.setTemperatureReadsEnabled(enabled)
    }

    /// 有面板可见且公网 IP 指标仍开启时为 true。
    func setPublicIPQueriesEnabled(_ enabled: Bool) {
        networkSampler.setPublicIPQueriesEnabled(enabled)
    }

    func sample(previousModules: [MonitorModule]) -> Result<SystemMonitorSnapshot, SamplingError> {
        sample(kinds: MonitorKind.samplerBackedCases, previousModules: previousModules)
    }

    func sample(kinds: some Sequence<MonitorKind>, previousModules: [MonitorModule]) -> Result<SystemMonitorSnapshot, SamplingError> {
        autoreleasepool {
            let requestedKinds = Array(kinds)
            #if DIRECT_DISTRIBUTION
            let power = requestedKinds.contains { [.gpu, .memory, .battery].contains($0) } ? powerSampler.sample() : nil
            #endif
            var modulesByKind = Dictionary(uniqueKeysWithValues: previousModules.map { ($0.kind, $0) })
            var errors: [SamplingError] = []

            for kind in requestedKinds {
                guard let sampler = samplers[kind] else {
                    let message = "No sampler registered for kind: \(kind.rawValue)"
                    AppLogger.sampler.error("\(message, privacy: .public)")
                    AppLogStore.shared.error(message, category: "sampler")
                    errors.append(samplingError(for: kind))
                    continue
                }
                let previous = modulesByKind[kind]
                let module: MonitorModule
                #if DIRECT_DISTRIBUTION
                if let consumer = sampler as? any IOReportPowerConsuming, let power {
                    module = consumer.sample(previous: previous, power: power)
                } else {
                    module = sampler.sample(previous: previous)
                }
                #else
                module = sampler.sample(previous: previous)
                #endif

                if let previous {
                    var updated = module
                    updated.samples = Self.historySamples(current: module, previous: previous)
                    if let pressureValue = module.pressureValue {
                        updated.pressureSamples = Array((previous.pressureSamples + [pressureValue]).suffix(MonitorConstants.sparklineMaxPoints))
                    }
                    modulesByKind[kind] = updated
                } else {
                    modulesByKind[kind] = module
                }
            }

            let modules = MonitorKind.allCases.map { kind in
                modulesByKind[kind] ?? MonitorModule.placeholder(kind: kind)
            }

            if errors.isEmpty {
                return .success(SystemMonitorSnapshot(modules: modules))
            } else if modulesByKind.isEmpty {
                return .failure(errors[0])
            } else {
                let message = "Partial sampling failure: \(errors.map(\.description).joined(separator: ", "))"
                AppLogger.sampler.error("\(message, privacy: .public)")
                AppLogStore.shared.error(message, category: "sampler")
                return .success(SystemMonitorSnapshot(modules: modules))
            }
        }
    }

    /// 电池未知区间不追加缓存电量，恢复时重新起线，避免伪造连续观测。
    static func historySamples(current: MonitorModule, previous: MonitorModule) -> [Double] {
        if current.kind == .battery {
            if current.isPlaceholder { return previous.samples }
            if previous.isPlaceholder { return [current.value] }
        }
        return Array((previous.samples + [current.value]).suffix(MonitorConstants.sparklineMaxPoints))
    }

    func sampleAsync(
        kinds: Set<MonitorKind>,
        previousModules: [MonitorModule],
        on queue: DispatchQueue,
        completion: @escaping @MainActor @Sendable (Result<SystemMonitorSnapshot, SamplingError>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.sample(kinds: kinds, previousModules: previousModules)
            Task { @MainActor in
                completion(result)
            }
        }
    }

    private func samplingError(for kind: MonitorKind) -> SamplingError {
        switch kind {
        case .cpu: return .cpuUnavailable
        case .gpu: return .gpuUnavailable
        case .memory: return .memoryUnavailable
        case .storage: return .storageUnavailable
        case .network: return .networkUnavailable
        case .battery: return .batteryUnavailable
        case .fan:
            // 风扇走独立 FanSampler 管线,不应进入 SystemMonitorSampler;
            // 兜底返回 batteryUnavailable(实际不会被触发)。
            return .batteryUnavailable
        case .bluetooth:
            // 蓝牙走独立 BluetoothBatterySampler 管线,同 fan。
            return .batteryUnavailable
        }
    }
}

#if DIRECT_DISTRIBUTION
nonisolated protocol IOReportPowerConsuming {
    func sample(previous: MonitorModule?, power: IOReportPowerSample) -> MonitorModule
}
extension BatterySampler: IOReportPowerConsuming {}
extension GPUSampler: IOReportPowerConsuming {}
extension MemorySampler: IOReportPowerConsuming {}
#endif
