#include "CrashSignalHandler.h"

#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

static char crashLogPath[PATH_MAX];

static const char crashPrefix[] = "FATAL [crash] Caught signal: ";
static const char crashSuffix[] = "\n";
static const char unknownSignalName[] = "UNKNOWN";

static const char *signalName(int signalNumber, size_t *length) {
    switch (signalNumber) {
    case SIGABRT:
        *length = sizeof("SIGABRT") - 1;
        return "SIGABRT";
    case SIGSEGV:
        *length = sizeof("SIGSEGV") - 1;
        return "SIGSEGV";
    case SIGBUS:
        *length = sizeof("SIGBUS") - 1;
        return "SIGBUS";
    case SIGILL:
        *length = sizeof("SIGILL") - 1;
        return "SIGILL";
    case SIGFPE:
        *length = sizeof("SIGFPE") - 1;
        return "SIGFPE";
    case SIGTERM:
        *length = sizeof("SIGTERM") - 1;
        return "SIGTERM";
    case SIGTRAP:
        *length = sizeof("SIGTRAP") - 1;
        return "SIGTRAP";
    default:
        *length = sizeof(unknownSignalName) - 1;
        return unknownSignalName;
    }
}

static void writeBytes(int fileDescriptor, const char *bytes, size_t length) {
    while (length > 0) {
        ssize_t written = write(fileDescriptor, bytes, length);
        if (written <= 0) {
            return;
        }
        bytes += written;
        length -= (size_t)written;
    }
}

static void handleCrashSignal(int signalNumber) {
    if (crashLogPath[0] != '\0') {
        int fileDescriptor = open(crashLogPath, O_WRONLY | O_APPEND | O_CREAT, 0644);
        if (fileDescriptor >= 0) {
            size_t nameLength = 0;
            const char *name = signalName(signalNumber, &nameLength);
            writeBytes(fileDescriptor, crashPrefix, sizeof(crashPrefix) - 1);
            writeBytes(fileDescriptor, name, nameLength);
            writeBytes(fileDescriptor, crashSuffix, sizeof(crashSuffix) - 1);
            close(fileDescriptor);
        }
    }

    // Darwin 对 SIGILL、SIGTRAP 不执行 SA_RESETHAND 自动复位,
    // 与信号由指令异常还是 raise 产生无关,因此显式恢复默认处置。
    signal(signalNumber, SIG_DFL);
    // 当前信号在处理器执行期间被屏蔽,raise 将其置为待处理;
    // 返回并恢复原信号掩码后,按默认处置终止进程。
    // 同步异常若再次执行故障指令,也会按默认处置终止,不再重入本处理器。
    // 保留信号终止语义,不以 _exit 的普通退出码替代。
    raise(signalNumber);
}

void HagimiInstallCrashSignalHandlers(const char *logPath) {
    if (logPath == NULL) {
        return;
    }

    size_t pathLength = strnlen(logPath, sizeof(crashLogPath));
    if (pathLength >= sizeof(crashLogPath)) {
        return;
    }
    memcpy(crashLogPath, logPath, pathLength);
    crashLogPath[pathLength] = '\0';

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = handleCrashSignal;
    // 由处理器显式恢复默认处置,避免依赖对 SIGILL、SIGTRAP 无效的 SA_RESETHAND。
    sigemptyset(&action.sa_mask);

    const int caughtSignals[] = {
        SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTERM, SIGTRAP
    };
    const size_t signalCount = sizeof(caughtSignals) / sizeof(caughtSignals[0]);
    for (size_t index = 0; index < signalCount; index += 1) {
        sigaction(caughtSignals[index], &action, NULL);
    }
}
