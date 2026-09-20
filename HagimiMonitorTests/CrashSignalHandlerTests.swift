import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 子进程分支仅使用预先准备的 C 字符串指针和标量,调用 C 接口后立即退出,
/// 不在 fork 后构造 Foundation 对象或执行 Swift 字符串比较。
@_silgen_name("fork") private func _fork() -> pid_t

/// 崩溃处理器回归测试。Darwin 对 SIGILL、SIGTRAP 不执行 SA_RESETHAND
/// 自动复位,不论信号来自指令异常还是 raise。若处理器再次 raise 却没有
/// 恢复 SIG_DFL,待处理信号会在解除屏蔽后再次调用处理器,形成重入循环。
/// 在子进程中安装处理器并触发信号,从父进程观察终止状态及日志次数。
struct CrashSignalHandlerTests {
    /// fork 子进程:装处理器 → 触发 trap → 父进程限时观察其以原始信号终止。
    /// 若回归为无限重入,子进程 3 秒后仍存活,本测试失败;
    /// 若处理器误用 _exit 普通退出,terminationSignal != SIGTRAP,同样失败。
    @Test("trap 后处理器以 SIGTRAP 终止进程,不陷入无限重入")
    func trapTerminatesProcessAfterHandling() throws {
        let result = try crashChild(triggerAbort: false)
        #expect(result.terminated, "trap 后子进程必须终止,不允许无限重入循环")
        #expect(result.terminationSignal == SIGTRAP,
                "进程必须以 SIGTRAP 信号终止(保留 crash report 语义),实际信号 \(result.terminationSignal)")
        #expect(result.logLines == 1, "崩溃日志恰好记录一次,重入循环会写出成千上万行")
    }

    /// 异步信号路径(abort):处理器同样恢复默认处置后以 SIGABRT 终止。
    @Test("abort 后处理器以 SIGABRT 终止进程")
    func abortTerminatesProcessAfterHandling() throws {
        let result = try crashChild(triggerAbort: true)
        #expect(result.terminated, "abort 后子进程必须终止")
        #expect(result.terminationSignal == SIGABRT,
                "进程必须以 SIGABRT 信号终止,实际信号 \(result.terminationSignal)")
        #expect(result.logLines == 1, "崩溃日志恰好记录一次")
    }

    // MARK: - 辅助

    private struct CrashChildResult {
        let terminated: Bool
        let terminationSignal: Int32
        let logLines: Int
    }

    /// 每个子进程独立安装处理器和日志路径,不修改测试宿主的全局配置。
    /// 父进程限时等待信号终止,并统计日志次数以检测处理器重入。
    private func crashChild(triggerAbort: Bool) throws -> CrashChildResult {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hagimi-crash-handler-tests-\(UUID().uuidString).log")
        try Data().write(to: logURL)
        defer { try? FileManager.default.removeItem(at: logURL) }

        // 在 fork 前准备路径缓冲区,子进程继承其副本;子进程不会离开闭包,
        // 因此无需在 fork 后执行字符串桥接或释放 Swift 捕获值。
        let pid = logURL.path.withCString { path in
            let childPID = _fork()
            if childPID == 0 {
                HagimiInstallCrashSignalHandlers(path)
                if triggerAbort {
                    abort()
                } else {
                    // 验证显式发送 SIGTRAP 后的复位与重新投递,不模拟硬件故障指令。
                    raise(SIGTRAP)
                }
                _exit(0)
            }
            return childPID
        }
        guard pid > 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EAGAIN)
        }

        var status: Int32 = 0
        var waitedPid = waitpid(pid, &status, WNOHANG)
        let deadline = Date().addingTimeInterval(3)
        while waitedPid == 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            waitedPid = waitpid(pid, &status, WNOHANG)
        }
        let terminated = waitedPid == pid
        // Swift 无法直接调用 WIFSIGNALED/WTERMSIG C 宏,用位运算解码:
        // WIFEXITED = (status & 0x7f) == 0; WIFSIGNALED = (status & 0x7f) 在 (0, 0x7f) 区间;
        // WTERMSIG = status & 0x7f。
        let terminationSignal: Int32 = {
            guard terminated else { return 0 }
            let low7 = status & 0x7f
            return (low7 > 0 && low7 < 0x7f) ? low7 : -1
        }()
        if !terminated {
            // 无限重入的子进程只能击杀收尸,防止泄漏到测试机。
            kill(pid, SIGKILL)
            waitpid(pid, &status, 0)
        }

        let logLines = (try? String(contentsOf: logURL, encoding: .utf8))?
            .split(separator: "\n").count ?? 0
        return CrashChildResult(
            terminated: terminated,
            terminationSignal: terminationSignal,
            logLines: logLines
        )
    }
}
