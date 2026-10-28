import Darwin
import Foundation

/// Глобальный перехват необработанных исключений и фатальных сигналов
/// (раздел 12 ТЗ). Пишет только тип и стек в приватный лог — НИКОГДА
/// набранный текст (раздел 11). Не превращает падение в зависание: после
/// записи восстанавливает поведение по умолчанию и до-падает штатно, чтобы
/// системный ReportCrash получил отчёт.
public enum CrashGuard {
    private static let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]

    /// Сообщение подготовлено заранее: в обработчике сигнала нельзя
    /// выделять память, интерполировать строки и вызывать Foundation —
    /// допустимы только async-signal-safe функции (`write`, `signal`, `raise`).
    private static let message: [UInt8] = Array("SmartSwitcher: фатальный сигнал, см. отчёт ReportCrash\n".utf8)
    /// Пишется один раз в `install()` до установки обработчиков, дальше только читается.
    nonisolated(unsafe) private static var messageBuffer: UnsafeMutablePointer<UInt8>?

    public static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let trace = exception.callStackSymbols.prefix(20).joined(separator: "\n")
            Log.app.critical("Необработанное исключение: \(exception.name.rawValue) — \(exception.reason ?? ""). Стек:\n\(trace)")
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: message.count)
        buffer.initialize(from: message, count: message.count)
        messageBuffer = buffer

        for sig in signals {
            signal(sig) { received in
                if let buffer = CrashGuard.messageBuffer {
                    _ = write(STDERR_FILENO, buffer, CrashGuard.message.count)
                }
                signal(received, SIG_DFL)
                raise(received)
            }
        }

        Log.app.info("CrashGuard установлен")
    }
}
