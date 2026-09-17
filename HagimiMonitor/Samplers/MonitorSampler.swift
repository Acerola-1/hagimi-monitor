import Foundation

nonisolated protocol MonitorSampler: Sendable {
    var kind: MonitorKind { get }
    func sample(previous: MonitorModule?) -> MonitorModule
}
