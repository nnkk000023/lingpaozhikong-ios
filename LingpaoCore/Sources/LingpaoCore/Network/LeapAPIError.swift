import Foundation

/// 零跑网络请求与业务鉴权统一错误类型
public enum LeapAPIError: Error, LocalizedError, Equatable {
    case notLoggedIn(String)
    case noVehicleSelected
    case missingPhoneForRenewal
    case missingSmDeviceId
    case httpError(statusCode: Int, message: String, endpoint: String)
    case invalidJSON(endpoint: String, preview: String)
    case legacyTokenExpired(String)
    case gatewayTokenExpired(String)
    case geetestChallengeRequired(GeetestChallenge)
    case businessError(code: String, message: String, endpoint: String)
    case missingResponseData(String)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn(let detail): return detail
        case .noVehicleSelected: return "还没有选择车辆 VIN"
        case .missingPhoneForRenewal: return "旧 Token 续期需要手机号，请重新登录"
        case .missingSmDeviceId: return "设备安全验证未返回标识（smDeviceId），请重试或使用原始凭据导入"
        case .httpError(let code, let msg, _): return "请求失败（HTTP \(code)）：\(msg)"
        case .invalidJSON(_, let preview): return "非 JSON 响应：\(preview)"
        case .legacyTokenExpired(let msg): return msg
        case .gatewayTokenExpired(let msg): return msg
        case .geetestChallengeRequired: return "需要完成极验安全滑块验证"
        case .businessError(let code, let msg, _): return "业务请求失败（\(code)）：\(msg)"
        case .missingResponseData(let msg): return msg
        }
    }

    /// 精确匹配 `GG.Q(json)` 检测旧 Token 是否失效
    public static func isLegacyTokenExpiredJSON(_ json: [String: Any]) -> Bool {
        if let result = stringValue(json["result"]), result == "39" {
            return true
        }
        let msg = (json["msg"] as? String) ?? (json["message"] as? String) ?? ""
        guard !msg.isEmpty else { return false }
        let pattern = "信息校验失败|第三方TOKEN失效|token.*失效|鉴权失败"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)) != nil {
            return true
        }
        return false
    }

    /// 精确匹配 `GG.v(...)` 检测网关 Token 是否失效
    public static func isGatewayTokenExpiredJSON(_ json: [String: Any]) -> Bool {
        let code = stringValue(json["code"])
            ?? stringValue(json["result"])
            ?? stringValue(json["status"])
            ?? ""
        if code == "401" || code == "403" {
            return true
        }
        let combined = [
            json["msg"] as? String ?? "",
            json["message"] as? String ?? "",
            json["error"] as? String ?? ""
        ].joined(separator: " ").lowercased()
        guard !combined.isEmpty else { return false }
        let p1 = try? NSRegularExpression(pattern: "token|登录|鉴权|认证")
        let p2 = try? NSRegularExpression(pattern: "expire|expired|invalid|过期|失效|无效|重新登录")
        let fullRange = NSRange(combined.startIndex..., in: combined)
        return p1?.firstMatch(in: combined, range: fullRange) != nil
            && p2?.firstMatch(in: combined, range: fullRange) != nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
}
