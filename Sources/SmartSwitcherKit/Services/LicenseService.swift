import Combine
import CryptoKit
import Foundation

/// Лицензирование (раздел 22 ТЗ, open-core / freemium).
///
/// Базовые функции (детект + переключение) бесплатны. Платные расширения
/// (синхронизация, доп. языки, автозамена, приоритетная поддержка) — план Pro,
/// активируемый лицензионным ключом для версии вне App Store (Вариант B ТЗ).
///
/// Ключ — это офлайн-проверяемый токен: `base64url(payload).base64url(signature)`,
/// где payload — JSON {email, plan, expiry}, подписанный Ed25519-ключом
/// издателя. Приложение проверяет подпись встроенным публичным ключом — без
/// обращения к сети. Валидная лицензия хранится в Keychain (раздел 11/22).
public final class LicenseService: ObservableObject {
    public enum Plan: String, Codable, Equatable {
        case free
        case pro
    }

    public struct License: Codable, Equatable {
        public let email: String
        public let plan: Plan
        /// Unix-время окончания (0 — бессрочно).
        public let expiry: TimeInterval

        public var isExpired: Bool {
            expiry != 0 && Date().timeIntervalSince1970 > expiry
        }
    }

    public enum ActivationError: LocalizedError {
        case malformed
        case badSignature
        case expired

        public var errorDescription: String? {
            switch self {
            case .malformed: return L10n.text("license.error.malformed", "Некорректный ключ.")
            case .badSignature: return L10n.text("license.error.signature", "Подпись ключа недействительна.")
            case .expired: return L10n.text("license.error.expired", "Срок действия ключа истёк.")
            }
        }
    }

    /// Публичный ключ издателя (base64). В open-source сборке — плейсхолдер;
    /// в релизе заменяется реальным ключом проекта. Инъектируется для тестов.
    public static let releasePublicKeyBase64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

    private let keychainAccount = "license"
    private let publicKey: Curve25519.Signing.PublicKey?

    @Published public private(set) var current: License

    public init(publicKeyBase64: String = LicenseService.releasePublicKeyBase64) {
        if let data = Data(base64Encoded: publicKeyBase64),
           let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data) {
            publicKey = key
        } else {
            publicKey = nil
        }
        current = Self.freeLicense
        current = loadStored() ?? Self.freeLicense
    }

    public static let freeLicense = License(email: "", plan: .free, expiry: 0)

    public var isPro: Bool {
        current.plan == .pro && !current.isExpired
    }

    /// В open-source/dev-сборке (публичный ключ-плейсхолдер) платные функции
    /// разблокированы — иначе их нельзя было бы протестировать без сервера
    /// лицензий. В релизе ключ реальный, и гейтинг работает (раздел 22).
    public var isDevBuild: Bool {
        publicKey == nil
            || (try? Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: Self.releasePublicKeyBase64) ?? Data()))?.rawRepresentation == publicKey?.rawRepresentation
    }

    /// Доступны ли платные расширения (синхронизация, доп. возможности).
    public var proFeaturesUnlocked: Bool {
        isPro || isDevBuild
    }

    /// Активация лицензионного ключа. Бросает `ActivationError` при ошибке.
    @discardableResult
    public func activate(key rawKey: String) throws -> License {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".")
        guard parts.count == 2,
              let payloadData = Self.base64urlDecode(String(parts[0])),
              let signature = Self.base64urlDecode(String(parts[1])) else {
            throw ActivationError.malformed
        }
        guard let publicKey, publicKey.isValidSignature(signature, for: payloadData) else {
            throw ActivationError.badSignature
        }
        guard let license = try? JSONDecoder().decode(License.self, from: payloadData) else {
            throw ActivationError.malformed
        }
        guard !license.isExpired else { throw ActivationError.expired }

        store(license)
        DispatchQueue.main.async { self.current = license }
        Log.app.info("Лицензия активирована: план \(license.plan.rawValue)")
        return license
    }

    /// Сброс к бесплатному плану (удаление лицензии).
    public func deactivate() {
        KeychainHelper.delete(account: keychainAccount)
        DispatchQueue.main.async { self.current = Self.freeLicense }
    }

    /// Восстановление покупок: перечитывает лицензию из Keychain (раздел 22).
    public func restore() {
        DispatchQueue.main.async { self.current = self.loadStored() ?? Self.freeLicense }
    }

    // MARK: - Хранение

    private func loadStored() -> License? {
        guard let data = KeychainHelper.read(account: keychainAccount),
              let license = try? JSONDecoder().decode(License.self, from: data),
              !license.isExpired else {
            return nil
        }
        return license
    }

    private func store(_ license: License) {
        guard let data = try? JSONEncoder().encode(license) else { return }
        KeychainHelper.write(account: keychainAccount, data: data)
    }

    // MARK: - base64url

    public static func base64urlDecode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    public static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
