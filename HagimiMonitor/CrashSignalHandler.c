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

    // SA_RESETHAND has already restored the default disposition. Re-raising
    // preserves the original crash semantics instead of returning to a trap.
    if (raise(signalNumber) != 0) {
        _exit(128 + signalNumber);
    }
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
    action.sa_flags = SA_RESETHAND;
    sigemptyset(&action.sa_mask);

    const int caughtSignals[] = {
        SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTERM, SIGTRAP
    };
    const size_t signalCount = sizeof(caughtSignals) / sizeof(caughtSignals[0]);
    for (size_t index = 0; index < signalCount; index += 1) {
        sigaction(caughtSignals[index], &action, NULL);
    }
}
