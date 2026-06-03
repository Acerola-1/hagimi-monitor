import Foundation

enum SamplingError: Error, CustomStringConvertible {
    case cpuUnavailable
    case gpuUnavailable
    case memoryUnavailable
    case storageUnavailable
    case networkUnavailable
    case batteryUnavailable
    case ioKitError(underlying: Error)

    var description: String {
        switch self {
        case .cpuUnavailable: return "CPU sampling unavailable"
        case .gpuUnavailable: return "GPU sampling unavailable"
        case .memoryUnavailable: return "Memory sampling unavailable"
        case .storageUnavailable: return "Storage sampling unavailable"
        case .networkUnavailable: return "Network sampling unavailable"
        case .batteryUnavailable: return "Battery sampling unavailable"
        case .ioKitError(let error): return "IOKit error: \(error.localizedDescription)"
        }
    }
}
