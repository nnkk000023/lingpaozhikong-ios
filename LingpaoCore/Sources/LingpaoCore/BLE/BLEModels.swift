import Foundation

/// BLE GATT UUID 及状态机基础模型（精确对齐 `E9`, `A9`, `R9`, `W8`, `U9`, `C9`）
public enum BLEConstants {
    public static let serviceUUIDString = "0000fffe-0000-1000-8000-00805f9b34fb"
    public static let characteristicUUIDString = "0000fff2-0000-1000-8000-00805f9b34fb"
    public static let cccdUUIDString = "00002902-0000-1000-8000-00805f9b34fb"
    public static let minorVersionPattern = #"^000001([0-9a-f]{2})-0000-1000-8000-00805f9b34fb$"#
    public static let defaultProtocolMinor: Int = 8
    public static let maxReceiveBufferSize: Int = 65_539

    /// 从广播服务 UUID 字符串列表中提取协议次版本号（匹配 `000001xx-...`），未匹配返回 `nil`
    public static func extractProtocolMinor(from uuidStrings: [String]) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: minorVersionPattern, options: [.caseInsensitive]) else {
            return nil
        }
        for uuid in uuidStrings {
            let trimmed = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                return Int(trimmed[range], radix: 16)
            }
        }
        return nil
    }
}

/// 蓝牙密钥密码学体系
public enum BLEKeyType: Int, Codable, Sendable {
    /// 国际标准：ECDH P-256 + SHA-256 + AES-128-CBC
    case p256AES = 0
    /// 国密：SM2 + SM3 + SM4-128-CBC
    case sm2SM4 = 1

    public var displayName: String {
        switch self {
        case .p256AES: return "ECDH P-256 + AES-128"
        case .sm2SM4: return "国密 SM2 + SM4-128"
        }
    }
}

/// 云端下发的车辆蓝牙数字钥匙证书（对应 `C9`）
public struct BleKeyCertificate: Codable, Equatable, Sendable {
    public var vin: String
    public var ecdhPublicKey: String
    public var keyType: BLEKeyType
    public var passwordCard: String
    public var plainText: String
    public var signResult: String

    public init(
        vin: String,
        ecdhPublicKey: String,
        keyType: BLEKeyType,
        passwordCard: String,
        plainText: String,
        signResult: String
    ) {
        self.vin = vin
        self.ecdhPublicKey = ecdhPublicKey
        self.keyType = keyType
        self.passwordCard = passwordCard
        self.plainText = plainText
        self.signResult = signResult
    }
}

/// 蓝牙 RSSI 距离标定参数（对应 `W8`）
public struct BLECalibration: Codable, Equatable, Sendable {
    public static let `default` = BLECalibration(
        distanceCalibration: 56,
        coefficientHundredths: 200,
        unlockCalibration: 8,
        lockCalibration: 16
    )

    public var distanceCalibration: Int
    public var coefficientHundredths: Int
    public var unlockCalibration: Int
    public var lockCalibration: Int

    public init(
        distanceCalibration: Int = 56,
        coefficientHundredths: Int = 200,
        unlockCalibration: Int = 8,
        lockCalibration: Int = 16
    ) {
        self.distanceCalibration = min(max(distanceCalibration, 0), 255)
        self.coefficientHundredths = min(max(coefficientHundredths, 0), 65535)
        self.unlockCalibration = min(max(unlockCalibration, 0), 255)
        self.lockCalibration = min(max(lockCalibration, 0), 255)
    }

    public var formattedString: String {
        let whole = coefficientHundredths / 100
        let frac = String(format: "%02d", coefficientHundredths % 100)
        let u = String(format: "%02d", unlockCalibration)
        let l = String(format: "%02d", lockCalibration)
        return "\(distanceCalibration);\(whole).\(frac);\(u);\(l)"
    }
}

/// 蓝牙无感解闭锁参数（对应 `U9`）
public struct BLEPassiveConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var autoUnlock: Bool
    public var autoLock: Bool
    public var buttonEnabled: Bool
    public var calibration: BLECalibration

    public init(
        enabled: Bool = true,
        autoUnlock: Bool = false,
        autoLock: Bool = false,
        buttonEnabled: Bool = false,
        calibration: BLECalibration = .default
    ) {
        self.enabled = enabled
        self.autoUnlock = autoUnlock
        self.autoLock = autoLock
        self.buttonEnabled = buttonEnabled
        self.calibration = calibration
    }

    /// 构造 `cmd = 3` 或快速重连内嵌的 9 字节参数负载（对应 `U9.c(buttonCap)`）
    public func wirePayload9Bytes(buttonCap: Bool) -> [UInt8] {
        let p0 = UInt8(calibration.distanceCalibration & 0xFF)
        let p1 = UInt8(calibration.coefficientHundredths & 0xFF)
        let p2 = UInt8((calibration.coefficientHundredths >> 8) & 0xFF)
        let p3 = UInt8(calibration.unlockCalibration & 0xFF)
        let p4 = UInt8(calibration.lockCalibration & 0xFF)
        let bEnabled: UInt8 = enabled ? 1 : 0
        let bLock: UInt8 = (enabled && autoLock) ? 1 : 0
        let bUnlock: UInt8 = (enabled && autoUnlock) ? 1 : 0
        let bButton: UInt8 = buttonCap ? 1 : 0
        return [p0, p1, p2, p3, p4, bEnabled, bLock, bUnlock, bButton]
    }
}

/// 蓝牙业务指令码（对应 `R9`）
public enum BLECommandCode: UInt8, Sendable {
    case unlock = 0
    case lock = 1
    case syncPassiveConfig = 3
}

/// BLE 帧头魔数（第二字节）
public enum BLEFrameType: UInt8, Sendable {
    case authentication = 0xAE
    case reconnect = 0xEE
    case encrypted = 0xAB
    case event = 0xAC
}

/// 下行蓝牙帧解析后的事件（对应 `C0523Ua.b` 解析结果）
public enum BLEDownlinkEvent: Equatable, Sendable {
    /// `0xAA 0xAB` 解密文本 `"0;..."`：认证确认
    case authenticatedConfirm([String])
    /// `0xAA 0xAB` 解密文本 `"1;<credentialHex>"`：下发快速重连凭证
    case reconnectCredential(String)
    /// `0xAA 0xAB` 解密文本 `"2;..."`：钥匙配置设置响应
    case keyConfigResponse([String])
    /// `0xAA 0xAB` 其它文本载荷
    case unknownEncrypted([String])
    /// `0xAA 0xAC` `eventType == 1`：错误码（`3, 4, 7` 触发清除快速凭证回退完整认证；`18` 表示未接受认证）
    case errorCode(UInt8)
    /// `0xAA 0xAC` `eventType == 2`：车门动作确认事件（`triggerSource == 1` 为 App 发起，`action == 0` 解锁 / `1` 上锁）
    case doorActionConfirm(triggerSource: UInt8, action: UInt8)
}
