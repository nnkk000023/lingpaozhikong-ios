import Foundation

public enum RawAuthParserError: Error, LocalizedError, Equatable {
    case emptyInput
    case invalidJSON(String)
    case missingAccountOrToken

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "导入内容不能为空"
        case .invalidJSON(let detail):
            return "JSON 格式错误，请检查粘贴内容：\(detail)"
        case .missingAccountOrToken:
            return "未能解析出有效的 accountId 和 token，请确保内容包含这两项凭据"
        }
    }
}

/// 解析后的原始认证凭据实体（精确复刻 `GG.T()` 导入机制）
public struct ParsedRawAuth: Equatable, Sendable {
    public var accountId: String
    public var token: String
    public var refreshToken: String
    public var tokenExpiredSeconds: String
    public var deviceId: String?
    public var smDeviceId: String?
    public var phone: String?

    public init(
        accountId: String,
        token: String,
        refreshToken: String = "",
        tokenExpiredSeconds: String = "21600",
        deviceId: String? = nil,
        smDeviceId: String? = nil,
        phone: String? = nil
    ) {
        self.accountId = accountId
        self.token = token
        self.refreshToken = refreshToken
        self.tokenExpiredSeconds = tokenExpiredSeconds
        self.deviceId = deviceId
        self.smDeviceId = smDeviceId
        self.phone = phone
    }
}

/// 原始认证凭据解析器（100% 兼容 JSON / 单行逗号 / 抓包自由文本，见 `GG.T()` L1547-L1740）
public enum RawAuthParser {
    public static func parse(rawText: String, phoneInput: String = "") throws -> ParsedRawAuth {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RawAuthParserError.emptyInput
        }
        let trimmedPhone = phoneInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // 模式 1：JSON 对象（`{ ... }`）
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            guard let jsonData = trimmed.data(using: .utf8) else {
                throw RawAuthParserError.invalidJSON("非 UTF-8 文本")
            }
            let rootObj: [String: Any]
            do {
                guard let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    throw RawAuthParserError.invalidJSON("根节点必须为 JSON 对象")
                }
                rootObj = parsed
            } catch let err as RawAuthParserError {
                throw err
            } catch {
                throw RawAuthParserError.invalidJSON(error.localizedDescription)
            }

            let dataObj = rootObj["data"] as? [String: Any]
            let targetObj = (rootObj["appLoginVO"] as? [String: Any])
                ?? (rootObj["appOneLoginVO"] as? [String: Any])
                ?? (dataObj?["appLoginVO"] as? [String: Any])
                ?? (dataObj?["appOneLoginVO"] as? [String: Any])
                ?? findAuthDictionaryRecursively(rootObj)
                ?? rootObj

            let accountId = nonEmptyString(targetObj["accountId"])
                ?? nonEmptyString(targetObj["identifier"])
                ?? nonEmptyString(targetObj["userId"])
                ?? nonEmptyString(rootObj["accountId"])
                ?? nonEmptyString(rootObj["identifier"])
                ?? ""

            let token = nonEmptyString(targetObj["token"])
                ?? nonEmptyString(targetObj["security"])
                ?? nonEmptyString(rootObj["token"])
                ?? nonEmptyString(rootObj["security"])
                ?? ""

            let refreshToken = nonEmptyString(targetObj["refreshToken"])
                ?? nonEmptyString(rootObj["refreshToken"])
                ?? ""

            let tokenExpired = stringValue(targetObj["tokenExpired"])
                ?? stringValue(rootObj["tokenExpired"])
                ?? "21600"

            let deviceId = nonEmptyString(rootObj["deviceID"])
                ?? nonEmptyString(rootObj["deviceId"])
                ?? nonEmptyString(rootObj["deviceid"])
                ?? nonEmptyString(rootObj["appimei"])
                ?? nonEmptyString(targetObj["deviceID"])
                ?? nonEmptyString(targetObj["deviceId"])

            let smDeviceId = nonEmptyString(rootObj["smDeviceId"])
                ?? nonEmptyString(rootObj["smdeviceid"])
                ?? nonEmptyString(rootObj["sm_device_id"])

            let jsonPhone = nonEmptyString(rootObj["phone"])
                ?? nonEmptyString(dataObj?["phone"])
                ?? nonEmptyString(targetObj["phone"])

            guard !accountId.isEmpty && !token.isEmpty else {
                throw RawAuthParserError.missingAccountOrToken
            }

            return ParsedRawAuth(
                accountId: accountId,
                token: token,
                refreshToken: refreshToken,
                tokenExpiredSeconds: tokenExpired.isEmpty ? "21600" : tokenExpired,
                deviceId: deviceId,
                smDeviceId: smDeviceId,
                phone: trimmedPhone.isEmpty ? jsonPhone : trimmedPhone
            )
        }

        // 模式 2：单行逗号分隔（`accountId,token[,refreshToken]`）
        if trimmed.contains(",") && !trimmed.contains("\n") {
            let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            let accountId = parts.count > 0 ? parts[0] : ""
            let token = parts.count > 1 ? parts[1] : ""
            let refreshToken = parts.count > 2 ? parts[2] : ""
            guard !accountId.isEmpty && !token.isEmpty else {
                throw RawAuthParserError.missingAccountOrToken
            }
            return ParsedRawAuth(
                accountId: accountId,
                token: token,
                refreshToken: refreshToken,
                tokenExpiredSeconds: "21600",
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone
            )
        }

        // 模式 3：多行 HTTP 抓包文本 / Key-Value 正则提取
        let token = firstCapture(in: trimmed, pattern: "(?:token|security|XFX-CDN-CROSS-NODE)[\"':=\\s]+([a-zA-Z0-9_-]{16,})") ?? ""
        let accountId = firstCapture(in: trimmed, pattern: "(?:accountId|identifier|userId|account_id)[\"':=\\s]+([a-zA-Z0-9_-]+)") ?? ""
        let refreshToken = firstCapture(in: trimmed, pattern: "(?:refreshToken|XFX-CDN-CROSS-REFRESH-NODE)[\"':=\\s]+([a-zA-Z0-9_-]{16,})") ?? ""
        let deviceId = firstCapture(in: trimmed, pattern: "(?:deviceID|deviceId|deviceid|appimei)[\"':=\\s]+([a-zA-Z0-9_-]{16,})")
        let smDeviceId = firstCapture(in: trimmed, pattern: "(?:smDeviceId|smdeviceid|sm_device_id)[\"':=\\s]+([a-zA-Z0-9_%/+=.-]{16,})")

        guard !accountId.isEmpty && !token.isEmpty else {
            throw RawAuthParserError.missingAccountOrToken
        }

        return ParsedRawAuth(
            accountId: accountId,
            token: token,
            refreshToken: refreshToken,
            tokenExpiredSeconds: "21600",
            deviceId: deviceId,
            smDeviceId: smDeviceId,
            phone: trimmedPhone.isEmpty ? nil : trimmedPhone
        )
    }

    private static func findAuthDictionaryRecursively(_ object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            let hasAccount = nonEmptyString(dict["accountId"]) != nil || nonEmptyString(dict["identifier"]) != nil
            let hasToken = nonEmptyString(dict["token"]) != nil || nonEmptyString(dict["security"]) != nil
            if hasAccount && hasToken {
                return dict
            }
            for value in dict.values {
                if let nested = findAuthDictionaryRecursively(value) {
                    return nested
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let nested = findAuthDictionaryRecursively(item) {
                    return nested
                }
            }
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let str = stringValue(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else {
            return nil
        }
        return str
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let val = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return val.isEmpty ? nil : val
    }
}
