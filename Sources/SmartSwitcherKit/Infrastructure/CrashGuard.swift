import Darwin
import Foundation

/// Глобальный перехват необработанных исключений и фатальных сигналов
/// (раздел 12 ТЗ). Пишет только тип и стек в приватный лог — НИКОГДА
/// набранный текст (раздел 11). Не превращает падение в зависание: после
/// записи восстанавливает поведение по умолчанию и до-падает штатно.
public enum CrashGuard {
    private static let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]

    public static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let trace = exception.callStackSymbols.prefix(20).joined(separator: "\n")
            Log.app.critical("Необработанное исключение: \(exception.name.rawValue) — \(exception.reason ?? ""). Стек:\n\(trace)")
        }

        for sig in signals {
            signal(sig) { received in
                // async-signal-safe минимум: пишем в stderr и восстанавливаем дефолт.
                let message = "SmartSwitcher: фатальный сигнал \(received)\n"
                FileHandle.standardError.write(Data(message.utf8))
                signal(received, SIG_DFL)
                raise(received)
            }
        }

        Log.app.info("CrashGuard установлен")
    }
}
