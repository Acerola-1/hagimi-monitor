import Testing
@testable import HagimiMonitorDirect
import CoreGraphics
import Foundation

/// 测试用 fake 传输:记录到达底层的读写,可控应答与阻塞(挂起)。
/// 阻塞的调用不回调,由测试手动 `releaseBlockedCalls()` 释放,模拟内核挂起。
final class FakeDDCTransport: DDCTransport, @unchecked Sendable {
    struct WriteRecord: Equatable {
        let service: DDCServiceHandle
        let vcpCode: UInt8
        let value: UInt16
    }

    private let lock = NSLock()
    private(set) var writes: [WriteRecord] = []
    private(set) var reads: [(service: DDCServiceHandle, vcpCode: UInt8)] = []
    /// 每个 vcp 码的读应答;无条目 = 无应答(nil)。
    var readReplies: [UInt8: DDCTransportReply] = [:]
    /// 写是否成功。
    var writeSucceeds = true
    /// 读/写是否阻塞(不回调,模拟内核挂起)。
    var blockReads = false
    var blockWrites = false

    func read(service: DDCServiceHandle, vcpCode: UInt8, completion: @escaping @Sendable (DDCTransportReply?) -> Void) {
        lock.lock()
        reads.append((service, vcpCode))
        let blocked = blockReads
        lock.unlock()
        if blocked {
            lock.lock()
            readContinuations.append(completion)
            lock.unlock()
        } else {
            completion(readReplies[vcpCode])
        }
    }

    func write(service: DDCServiceHandle, vcpCode: UInt8, value: UInt16, completion: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        writes.append(WriteRecord(service: service, vcpCode: vcpCode, value: value))
        let blocked = blockWrites
        lock.unlock()
        if blocked {
            lock.lock()
            writeContinuations.append(completion)
            lock.unlock()
        } else {
            completion(writeSucceeds)
        }
    }

    private var readContinuations: [@Sendable (DDCTransportReply?) -> Void] = []
    private var writeContinuations: [@Sendable (Bool) -> Void] = []

    /// 释放挂起的调用(真实返回迟到场景)。
    func releaseBlockedCalls() {
        lock.lock()
        let reads = readContinuations
        readContinuations.removeAll()
        let writes = writeContinuations
        writeContinuations.removeAll()
        lock.unlock()
        for completion in reads { completion(nil) }
        for completion in writes { completion(true) }
    }

    func writeCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return writes.count
    }

    /// 清空记录(分段断言用)。
    func resetRecords() {
        lock.lock()
        writes.removeAll()
        reads.removeAll()
        lock.unlock()
    }

    func readCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return reads.count
    }

    func setReadReply(vcpCode: UInt8 = 0x10, current: UInt16, max: UInt16, resultCode: UInt8 = 0x00) {
        lock.lock()
        readReplies[vcpCode] = DDCTransportReply(resultCode: resultCode, current: current, max: max)
        lock.unlock()
    }
}
