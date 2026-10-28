import os

/// Приватный лог (раздел 11 ТЗ): фиксируются только решения и метаданные,
/// набранный пользователем текст в лог не пишется НИКОГДА.
public enum Log {
    public static let app = Logger(subsystem: "com.smartswitcher.app", category: "app")
    public static let engine = Logger(subsystem: "com.smartswitcher.app", category: "engine")
    public static let brain = Logger(subsystem: "com.smartswitcher.app", category: "brain")
}
