#ifndef CrashSignalHandler_h
#define CrashSignalHandler_h

/// Installs the fatal-signal handlers after copying `logPath` into fixed C storage.
/// The installed handler uses async-signal-safe POSIX calls only, restores the
/// default disposition itself (Darwin does not honor SA_RESETHAND for SIGILL
/// or SIGTRAP), so subsequent delivery terminates instead of reentering it.
void HagimiInstallCrashSignalHandlers(const char *logPath);

#endif /* CrashSignalHandler_h */
