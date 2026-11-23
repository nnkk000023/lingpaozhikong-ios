import Foundation

/// 旧用户系统会话凭证（`https://appuser.leapmotor.cn` 体系）
public struct OldSession: Codable, Equatable, Sendable {
    public var accountId: String
    public var token: String
    public var refreshToken: String
    public var tokenExpiredSeconds: String
    public var issuedAtMs: Int64

    public init(
        accountId: String,
        token: String,
        refreshToken: String,
        tokenExpiredSeconds: String = "21600",
        issuedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.accountId = accountId
        self.token = token
        self.refreshToken = refreshToken
        self.tokenExpiredSeconds = tokenExpiredSeconds
        self.issuedAtMs = issuedAtMs
    }

    /// 计算旧 Token 的绝对过期时间戳（毫秒），若无法解析则按默认 21600 秒推算
    public var expiresAtMs: Int64 {
        let secs = Int64(tokenExpiredSeconds.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 21600
        let validSecs = secs > 0 ? secs : 21600
        return issuedAtMs + validSecs * 1000
    }
}

/// 网关系统会话凭证（`app-gw-global-master` 与区域网关体系）
public struct GatewaySession: Codable, Equatable, Sendable {
    public var accountId: String
    public var accessToken: String
    public var refreshToken: String
    /// 由 JWT 第 3 段签名与 `signParam.r2/r3` 三方逐字节异或派生的 HMAC 密钥（Base64 编码）
    public var hmacKeyBase64: String
    public var expiresAtMs: Int64

    public init(
        accountId: String,
        accessToken: String,
        refreshToken: String,
        hmacKeyBase64: String,
        expiresAtMs: Int64
    ) {
        self.accountId = accountId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.hmacKeyBase64 = hmacKeyBase64
        self.expiresAtMs = expiresAtMs
    }

    /// 网关 HMAC 原始字节密钥
    public var hmacKeyData: Data? {
        let cleaned = hmacKeyBase64.filter { !$0.isWhitespace && !$0.isNewline }
        return Data(base64Encoded: cleaned)
    }
}

/// 车辆动态区域路由（由 `getCarRoute` 返回）
public struct CarRoute: Codable, Equatable, Sendable {
    public var appRegion: String
    public var appCenter: String

    public init(appRegion: String, appCenter: String) {
        self.appRegion = appRegion
        self.appCenter = appCenter
    }
}

/// 车辆空调能力上下限配置
public struct HvacCapability: Codable, Equatable, Hashable, Sendable {
    public var minTemp: Int
    public var maxTemp: Int
    public var minFan: Int?
    public var maxFan: Int?

    public static let `default` = HvacCapability(minTemp: 19, maxTemp: 32, minFan: 1, maxFan: 9)

    public init(minTemp: Int = 19, maxTemp: Int = 32, minFan: Int? = 1, maxFan: Int? = 9) {
        self.minTemp = minTemp
        self.maxTemp = maxTemp
        self.minFan = minFan
        self.maxFan = maxFan
    }
}

/// 客户端持久化与运行期完整会话状态
public struct SessionState: Codable, Equatable, Sendable {
    public var deviceId: String
    public var phone: String
    public var smDeviceId: String
    public var oldSession: OldSession?
    public var gatewaySession: GatewaySession?
    public var selectedVin: String
    public var selectedCarType: String
    public var selectedNickname: String
    public var selectedYear: String
    public var selectedPaintId: String
    public var selectedSeatLayout: SeatLayout?
    public var carRoute: CarRoute?
    public var hvacCapability: HvacCapability

    public init(
        deviceId: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
        phone: String = "",
        smDeviceId: String = "",
        oldSession: OldSession? = nil,
        gatewaySession: GatewaySession? = nil,
        selectedVin: String = "",
        selectedCarType: String = "C16",
        selectedNickname: String = "零跑C16",
        selectedYear: String = "",
        selectedPaintId: String = "liquid_silver",
        selectedSeatLayout: SeatLayout? = nil,
        carRoute: CarRoute? = nil,
        hvacCapability: HvacCapability = .default
    ) {
        self.deviceId = deviceId
        self.phone = phone
        self.smDeviceId = smDeviceId
        self.oldSession = oldSession
        self.gatewaySession = gatewaySession
        self.selectedVin = selectedVin
        self.selectedCarType = selectedCarType
        self.selectedNickname = selectedNickname
        self.selectedYear = selectedYear
        self.selectedPaintId = selectedPaintId
        self.selectedSeatLayout = selectedSeatLayout
        self.carRoute = carRoute
        self.hvacCapability = hvacCapability
    }

    public var isLoggedIn: Bool {
        oldSession != nil && !(oldSession?.token.isEmpty ?? true)
    }
}
