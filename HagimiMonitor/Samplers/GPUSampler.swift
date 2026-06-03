import Darwin
import Foundation
import IOKit
import OSLog

final class GPUSampler: MonitorSampler {
    var kind: MonitorKind { .gpu }

    func sample(previous: MonitorModule?) -> MonitorModule {
        guard let reading = gpuReading() else {
            AppLogger.sampler.error("gpuReading() returned nil, GPU data unavailable")
            return placeholderModule(.gpu, summary: "无法读取")
        }

        let utilization = min(100, max(0, reading.utilization))
        var metrics = [
            MonitorMetric(name: "GPU内存", value: reading.usedMemory.map(bytes) ?? "--"),
            MonitorMetric(name: "已分配", value: reading.allocatedMemory.map(bytes) ?? "--")
        ]

        if let renderUtilization = reading.renderUtilization {
            metrics.append(MonitorMetric(name: "渲染", value: percent(renderUtilization)))
        }

        if let tilerUtilization = reading.tilerUtilization {
            metrics.append(MonitorMetric(name: "分块", value: percent(tilerUtilization)))
        }

        return MonitorModule(
            kind: .gpu,
            value: utilization,
            summary: percent(utilization),
            metrics: metrics,
            samples: seedSamples(utilization)
        )
    }

    private func gpuReading() -> GPUReading? {
        let accelerators = acceleratorServices()
        guard !accelerators.isEmpty else {
            AppLogger.sampler.error("No IOAccelerator services found")
            return nil
        }
        defer {
            accelerators.forEach { IOObjectRelease($0) }
        }

        var best: GPUReading?
        for accelerator in accelerators {
            guard let stats = registryDictionaryValue(accelerator, "PerformanceStatistics") else {
                AppLogger.sampler.error("Failed to read PerformanceStatistics from IOAccelerator service")
                continue
            }

            let utilization = doubleValue(stats["Device Utilization %"])
                ?? doubleValue(stats["GPU Activity(%)"])
                ?? 0
            let render = doubleValue(stats["Renderer Utilization %"])
            let tiler = doubleValue(stats["Tiler Utilization %"])
            let temperature = doubleValue(stats["Temperature(C)"])
            let usedMemory = doubleValue(stats["In use system memory"])
            let allocatedMemory = doubleValue(stats["Alloc system memory"])
            let model = registryStringValue(accelerator, "model")
                ?? registryStringValue(accelerator, "IOClass")
                ?? "GPU"

            let reading = GPUReading(
                model: model,
                utilization: utilization,
                renderUtilization: render,
                tilerUtilization: tiler,
                temperature: temperature,
                usedMemory: usedMemory,
                allocatedMemory: allocatedMemory
            )

            if best == nil || reading.utilization > (best?.utilization ?? 0) {
                best = reading
            }
        }

        return best
    }

    private func acceleratorServices() -> [io_service_t] {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
        guard result == KERN_SUCCESS else {
            AppLogger.sampler.error("IOServiceGetMatchingServices for IOAccelerator failed with result: \(result)")
            return []
        }
        defer { IOObjectRelease(iterator) }

        var services: [io_service_t] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else {
                break
            }
            services.append(service)
        }
        return services
    }
}

private struct GPUReading {
    let model: String
    let utilization: Double
    let renderUtilization: Double?
    let tilerUtilization: Double?
    let temperature: Double?
    let usedMemory: Double?
    let allocatedMemory: Double?
}
