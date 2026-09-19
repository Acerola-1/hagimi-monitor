#ifndef CrashSignalHandler_h
#define CrashSignalHandler_h

/// Installs the fatal-signal handlers after copying `logPath` into fixed C storage.
/// The installed handler uses async-signal-safe POSIX calls only.
void HagimiInstallCrashSignalHandlers(const char *logPath);

#endif /* CrashSignalHandler_h */
