import Foundation
import OSLog

struct SystemMonitorSnapshot {
    var modules: [MonitorModule]
}

final class SystemMonitorSampler {
    private let samplers: [MonitorKind: MonitorSampler] = [
        .cpu: CPUSampler(),
        .gpu: GPUSampler(),
        .memory: MemorySampler(),
        .storage: StorageSampler(),
        .network: NetworkSampler(),
        .battery: BatterySampler()
    ]

    func sample(previousModules: [MonitorModule]) -> Result<SystemMonitorSnapshot, SamplingError> {
        sample(kinds: MonitorKind.allCases, previousModules: previousModules)
    }

    func sample(kinds: some Sequence<MonitorKind>, previousModules: [MonitorModule]) -> Result<SystemMonitorSnapshot, SamplingError> {
        autoreleasepool {
            var modulesByKind = Dictionary(uniqueKeysWithValues: previousModules.map { ($0.kind, $0) })
            var errors: [SamplingError] = []

            for kind in kinds {
                guard let sampler = samplers[kind] else {
                    AppLogger.sampler.error("No sampler registered for kind: \(kind.rawValue, privacy: .public)")
                    errors.append(samplingError(for: kind))
                    continue
                }
                let previous = modulesByKind[kind]
                let module = sampler.sample(previous: previous)

                if let previous {
                    var updated = module
                    updated.samples = Array((previous.samples + [module.value]).suffix(MonitorConstants.sparklineMaxPoints))
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
                AppLogger.sampler.error("Partial sampling failure: \(errors.map(\.description).joined(separator: ", "), privacy: .public)")
                return .success(SystemMonitorSnapshot(modules: modules))
            }
        }
    }

    func sampleAsync(
        kinds: Set<MonitorKind>,
        previousModules: [MonitorModule],
        on queue: DispatchQueue,
        completion: @escaping (Result<SystemMonitorSnapshot, SamplingError>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.sample(kinds: kinds, previousModules: previousModules)
            DispatchQueue.main.async {
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
        }
    }
}
