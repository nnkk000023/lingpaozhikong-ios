import Foundation
import LingpaoCore
import Security

/// 外观模式偏好（字符串枚举，无 UIKit 依赖便于 App 与 Widget Extension 共享 KeychainStore）
public enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// 基于 iOS Keychain + App Group UserDefaults 的安全持久化仓储
public final class KeychainStore: SessionStoring, @unchecked Sendable {
    public static let shared = KeychainStore()

    private let service = "com.lingpao.personal.secure"
    private let lock = NSLock()
    private let defaults: UserDefaults

    private enum Keys {
        static let sessionState = "lingpao.session.state.v1"
        static let opPassword = "lingpao.control.pin.v1"
        static let amapKey = "lingpao.amap.web.key.v1"
        static let appearance = "lingpao.ui.appearance.v1"
        static let bleCertPrefix = "lingpao.ble.cert."
        static let bleCredPrefix = "lingpao.ble.reconnect."
        static let blePeripheralPrefix = "lingpao.ble.peripheral."
        static let blePassiveConfig = "lingpao.ble.passive.config.v1"
        static let liveActivityEnabled = "lingpao.ui.live_activity.enabled.v1"
        static let controlLayoutPreferences = "lingpao.ui.control_layout.v2"
    }

    public init() {
        self.defaults = UserDefaults(suiteName: SharedSnapshotStore.appGroupIdentifier) ?? .standard
    }

    // MARK: - SessionStoring

    public func loadSession() -> SessionState {
        lock.lock()
        defer { lock.unlock() }
        guard let data = readKeychain(account: Keys.sessionState),
              let state = try? JSONDecoder().decode(SessionState.self, from: data) else {
            return SessionState()
        }
        return state
    }

    public func saveSession(_ state: SessionState) {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(state) {
            writeKeychain(data, account: Keys.sessionState)
        }
    }

    public func clearSession() {
        lock.lock()
        defer { lock.unlock() }
        let current = readKeychain(account: Keys.sessionState).flatMap { try? JSONDecoder().decode(SessionState.self, from: $0) }
        var cleared = SessionState()
        if let current {
            cleared.deviceId = current.deviceId
            cleared.selectedPaintId = current.selectedPaintId
            cleared.selectedCarType = current.selectedCarType
        }
        if let data = try? JSONEncoder().encode(cleared) {
            writeKeychain(data, account: Keys.sessionState)
        }
    }

    // MARK: - 操控密码与用户偏好

    public func loadOpPassword() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let data = readKeychain(account: Keys.opPassword),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    public func saveOpPassword(_ pin: String) {
        lock.lock()
        defer { lock.unlock() }
        writeKeychain(Data(pin.utf8), account: Keys.opPassword)
    }

    public func loadAmapKey() -> String {
        defaults.string(forKey: Keys.amapKey) ?? ""
    }

    public func saveAmapKey(_ key: String) {
        defaults.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.amapKey)
    }

    public func loadAppearance() -> AppearancePreference {
        guard let raw = defaults.string(forKey: Keys.appearance),
              let pref = AppearancePreference(rawValue: raw) else {
            return .system
        }
        return pref
    }

    public func saveAppearance(_ pref: AppearancePreference) {
        defaults.set(pref.rawValue, forKey: Keys.appearance)
    }

    // MARK: - BLE 证书、重连快速凭证与外设 UUID 绑定（按 accountId + vin 指纹隔离）

    private func bleKeySuffix(accountId: String, vin: String) -> String {
        LeapCrypto.sha256Hex(Data("\(accountId)\0\(vin)".utf8))
    }

    public func saveBleCertificate(_ cert: BleKeyCertificate, accountId: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = Keys.bleCertPrefix + bleKeySuffix(accountId: accountId, vin: cert.vin)
        if let data = try? JSONEncoder().encode(cert) {
            writeKeychain(data, account: key)
        }
    }

    public func loadBleCertificate(accountId: String, vin: String) -> BleKeyCertificate? {
        lock.lock()
        defer { lock.unlock() }
        let key = Keys.bleCertPrefix + bleKeySuffix(accountId: accountId, vin: vin)
        guard let data = readKeychain(account: key) else { return nil }
        return try? JSONDecoder().decode(BleKeyCertificate.self, from: data)
    }

    public func saveReconnectCredential(_ hex: String?, accountId: String, vin: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = Keys.bleCredPrefix + bleKeySuffix(accountId: accountId, vin: vin)
        if let hex, !hex.isEmpty {
            writeKeychain(Data(hex.utf8), account: key)
        } else {
            deleteKeychain(account: key)
        }
    }

    public func loadReconnectCredential(accountId: String, vin: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let key = Keys.bleCredPrefix + bleKeySuffix(accountId: accountId, vin: vin)
        guard let data = readKeychain(account: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func saveBoundPeripheralUUID(_ uuid: UUID?, vin: String) {
        let key = Keys.blePeripheralPrefix + vin
        if let uuid {
            defaults.set(uuid.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func loadBoundPeripheralUUID(vin: String) -> UUID? {
        guard let str = defaults.string(forKey: Keys.blePeripheralPrefix + vin) else { return nil }
        return UUID(uuidString: str)
    }

    public func savePassiveConfig(_ config: BLEPassiveConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: Keys.blePassiveConfig)
        }
    }

    public func loadPassiveConfig() -> BLEPassiveConfiguration {
        guard let data = defaults.data(forKey: Keys.blePassiveConfig),
              let cfg = try? JSONDecoder().decode(BLEPassiveConfiguration.self, from: data) else {
            return BLEPassiveConfiguration()
        }
        return cfg
    }

    /// 灵动岛充电实况总开关（默认开启，仅在车辆处于充电状态时触发显示）
    public func loadLiveActivityEnabled() -> Bool {
        if defaults.object(forKey: Keys.liveActivityEnabled) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.liveActivityEnabled)
    }

    public func saveLiveActivityEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.liveActivityEnabled)
    }

    /// 主页与控车定制卡片排序及功能布局缓存
    public func loadControlLayoutPreferences() -> ControlLayoutPreferences? {
        guard let data = defaults.data(forKey: Keys.controlLayoutPreferences),
              let prefs = try? JSONDecoder().decode(ControlLayoutPreferences.self, from: data) else {
            return nil
        }
        return prefs
    }

    public func saveControlLayoutPreferences(_ prefs: ControlLayoutPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: Keys.controlLayoutPreferences)
        }
    }

    // MARK: - 底层 Keychain 查询辅助

    private func writeKeychain(_ data: Data, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func readKeychain(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func deleteKeychain(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
