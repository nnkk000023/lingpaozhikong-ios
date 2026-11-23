import CommonCrypto
import CryptoKit
import Foundation
import Security

public enum LeapCryptoError: Error, LocalizedError, Equatable {
    case invalidPublicKey
    case rsaEncryptionFailed(String)
    case tokenTooShortForOpPassword
    case aesFailed(Int32)
    case invalidGatewayTokenFormat
    case missingSignParams

    public var errorDescription: String? {
        switch self {
        case .invalidPublicKey:
            return "内置 RSA 公钥解析失败"
        case .rsaEncryptionFailed(let detail):
            return "RSA 加密失败：\(detail)"
        case .tokenTooShortForOpPassword:
            return "Token 长度不足，无法加密操作密码"
        case .aesFailed(let status):
            return "AES 加解密失败（status=\(status)）"
        case .invalidGatewayTokenFormat:
            return "网关 accessToken 不是三段式 JWT"
        case .missingSignParams:
            return "网关登录响应缺少 accessToken 或 signParam.r2/r3"
        }
    }
}

/// 零跑全量签名与加解密原语（严格对应反编译 `defpackage.GG` 与 `AbstractC1805ni0`）
public enum LeapCrypto {
    /// 固定登录手机号加密 RSA-1024 X.509 SPKI 公钥（Base64）
    public static let phoneRSAPublicKeyBase64 =
        "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDHUIQKhkwNqJFTZPe98mC1lmpbY9r/+7PEWZg8ebqYXT3sumKRaQ0zcoTx42x0iybmCRXy4CcZrgGAbwKzwqwNw0rFquJ6c7mgQA6k3lZU3p96qBlzK7DSkoFR6mO9pjcd2hlJ8wH+IwI5b8IWWZhwVN/4cM7npG0S0zeRn3soEwIDAQAB"

    /// 基础请求头固定版本号（对齐 `GG.W` 与 `GG.V`）
    public static let appVersion = "1.23.00"
    public static let subVersion = "3.24.5-1"

    // MARK: - 1. GG.p0 参数纯值拼接

    /// 将多组字典合并（后传入的同 key 覆盖前者，忽略 `nil` Value），
    /// 按 Key 标准 ASCII/UTF-8 字典序升序排序后，**仅拼接 Value**（空字符串 `""` 分隔）。
    public static func concatSortedValues(_ maps: [String: String?]...) -> String {
        var merged: [String: String] = [:]
        for map in maps {
            for (k, v) in map {
                if let val = v {
                    merged[k] = val
                }
            }
        }
        // Swift String `<` 按 Unicode Scalar / UTF-8 字节序比较，与 Kotlin sortedBy ASCII 一致
        let sortedKeys = merged.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) })
        return sortedKeys.compactMap { merged[$0] }.joined()
    }

    // MARK: - 2. MD5 / SHA256 / HMAC-SHA256 工具

    /// MD5 32 位小写十六进制
    public static func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 64 位小写十六进制
    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// HMAC-SHA256 64 位小写十六进制
    public static func hmacSHA256Hex(message: Data, key: Data) -> String {
        let symKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: symKey)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// 小写十六进制工具（兼容 BLE 模块使用）
    public static func hexLower(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 3. GG.X 旧业务参数签名（signStr）

    /// 生成 `[10000, 10010000)` 随机整数字符串
    public static func randomNonce() -> String {
        let val = Int.random(in: 10000..<10_010_000)
        return String(val)
    }

    /// 精确实现 `GG.X`：先写入 `timespan`、`nonce`、`deviceID`、`token`/`refreshtoken` 与业务字段，
    /// 对 `p0` 算 MD5 并取 `[8..<24]` 写入 `signStr`，再移除 `token`/`refreshtoken`。
    public static func signLegacyParams(
        business: [String: String?],
        deviceID: String,
        tokenOrRefreshToken: String,
        isRefresh: Bool = false,
        includeTimestamp: Bool = true,
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        nonce: String = randomNonce()
    ) -> [String: String] {
        var source: [String: String?] = [:]
        if includeTimestamp {
            source["timespan"] = String(timestampMs)
        }
        source["nonce"] = nonce
        source["deviceID"] = deviceID
        source[isRefresh ? "refreshtoken" : "token"] = tokenOrRefreshToken
        for (k, v) in business {
            source[k] = v
        }

        let concat = concatSortedValues(source)
        let fullMD5 = md5Hex(concat)
        let start = fullMD5.index(fullMD5.startIndex, offsetBy: 8)
        let end = fullMD5.index(fullMD5.startIndex, offsetBy: 24)
        let signStr = String(fullMD5[start..<end])

        source.removeValue(forKey: isRefresh ? "refreshtoken" : "token")
        var output: [String: String] = [:]
        for (k, v) in source {
            if let v {
                output[k] = v
            }
        }
        output["signStr"] = signStr
        return output
    }

    // MARK: - 4. GG.W 与 GG.V HTTP Header 构造与网关签名

    /// 精确实现 `GG.W(withToken:)`
    public static func buildBaseHeaders(
        deviceId: String,
        oldToken: String?,
        withToken: Bool
    ) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": "okhttp/4.9.3",
            "APPPlatform": "Android",
            "APPVersion": appVersion,
            "APPImei": deviceId,
            "C-VERSIONS": "APP",
            "XFX-CDN-VRS": "v4"
        ]
        if withToken, let oldToken, !oldToken.isEmpty {
            headers["XFX-CDN-CROSS-NODE"] = oldToken
        }
        return headers
    }

    /// 精确实现 `GG.V(map, useHmac, customKey)`
    public static func buildGatewayHeaders(
        business: [String: String?],
        deviceId: String,
        accountId: String,
        accessToken: String?,
        carvin: String,
        cartype: String,
        hmacKey: Data?,
        useHmac: Bool,
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        nonce: String = randomNonce()
    ) throws -> [String: String] {
        let tsStr = String(timestampMs)
        var headers: [String: String] = [
            "source": "leapmotor",
            "channel": "1",
            "acceptLanguage": "zh-CN",
            "x-region": "CN",
            "x-api-signature-version": "2.0",
            "digest": "",
            "version": appVersion,
            "deviceType": "android",
            "nonce": nonce,
            "timestamp": tsStr,
            "deviceId": deviceId,
            "userId": accountId,
            "carvin": carvin,
            "cartype": cartype,
            "x-subversion": subVersion
        ]

        let commonSignFields: [String: String?] = [
            "acceptLanguage": "zh-CN",
            "channel": "1",
            "deviceId": deviceId,
            "deviceType": "android",
            "nonce": nonce,
            "source": "leapmotor",
            "timestamp": tsStr,
            "version": appVersion
        ]

        let signSeed = concatSortedValues(commonSignFields, business)
        let seedData = Data(signSeed.utf8)

        if useHmac {
            guard let accessToken, !accessToken.isEmpty else {
                throw LeapCryptoError.missingSignParams
            }
            guard let hmacKey else {
                throw LeapCryptoError.missingSignParams
            }
            headers["token"] = accessToken
            headers["userId"] = accountId
            headers["sign"] = hmacSHA256Hex(message: seedData, key: hmacKey)
        } else {
            headers["sign"] = sha256Hex(seedData)
        }
        return headers
    }

    // MARK: - 5. GG.u 网关 HMAC 密钥派生（JWT 第 3 段 ^ r2 ^ r3）

    /// 解码 Base64URL 字符串（`-` -> `+`，`_` -> `/`，自动补齐 `=`）
    public static func decodeBase64URL(_ input: String) -> Data? {
        var b64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 {
            b64.append("=")
        }
        return Data(base64Encoded: b64)
    }

    /// 解析 `/base/base-user/account/v1/login` 响应体，派生网关会话与可能回写的 `deviceId`
    public static func deriveGatewaySession(
        from loginDataJSON: [String: Any],
        fallbackAccountId: String,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> (session: GatewaySession, extractedDeviceId: String?) {
        let accessToken = (loginDataJSON["accessToken"] as? String) ?? ""
        let signParam = loginDataJSON["signParam"] as? [String: Any]
        let r2 = (signParam?["r2"] as? String) ?? ""
        let r3 = (signParam?["r3"] as? String) ?? ""

        guard !accessToken.isEmpty, !r2.isEmpty, !r3.isEmpty else {
            throw LeapCryptoError.missingSignParams
        }

        let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let sigBytes = decodeBase64URL(parts[2]),
              let r2Bytes = Data(base64Encoded: r2.filter { !$0.isWhitespace && !$0.isNewline }),
              let r3Bytes = Data(base64Encoded: r3.filter { !$0.isWhitespace && !$0.isNewline }) else {
            throw LeapCryptoError.invalidGatewayTokenFormat
        }

        let count = min(sigBytes.count, min(r2Bytes.count, r3Bytes.count))
        var xorBytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            xorBytes[i] = sigBytes[i] ^ r2Bytes[i] ^ r3Bytes[i]
        }
        let hmacKeyBase64 = Data(xorBytes).base64EncodedString()

        // 解析 JWT payload 中的 deviceId 与 exp
        var extractedDeviceId: String?
        var expMs: Int64 = 0
        if let payloadData = decodeBase64URL(parts[1]),
           let payloadObj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
            if let userName = payloadObj["user_name"] as? String,
               let regex = try? NSRegularExpression(pattern: "deviceId:([a-zA-Z0-9_-]+)"),
               let match = regex.firstMatch(in: userName, range: NSRange(userName.startIndex..., in: userName)),
               let range = Range(match.range(at: 1), in: userName) {
                let candidate = String(userName[range])
                if !candidate.isEmpty {
                    extractedDeviceId = candidate
                }
            }
            if let exp = (payloadObj["exp"] as? NSNumber)?.int64Value, exp > 0 {
                expMs = exp * 1000
            }
        }

        if expMs <= 0, let ttl = (loginDataJSON["tokenExpireTime"] as? NSNumber)?.int64Value, ttl > 0 {
            expMs = nowMs + ttl * 1000
        }

        let accountId = fallbackAccountId.isEmpty ? ((loginDataJSON["accountId"] as? String) ?? "") : fallbackAccountId
        let refreshToken = (loginDataJSON["refreshToken"] as? String) ?? ""
        let session = GatewaySession(
            accountId: accountId,
            accessToken: accessToken,
            refreshToken: refreshToken,
            hmacKeyBase64: hmacKeyBase64,
            expiresAtMs: expMs
        )
        return (session, extractedDeviceId)
    }

    // MARK: - 6. 手机号 RSA-1024 PKCS1 加密（AbstractC1805ni0.W）

    /// 使用内置 RSA-1024 公钥对手机号执行 `RSA/ECB/PKCS1Padding` 加密，输出无尾部 `=` 的 URL-Safe Base64
    public static func encryptPhoneRSA(_ phone: String) throws -> String {
        guard let spkiData = Data(base64Encoded: phoneRSAPublicKeyBase64),
              let pkcs1Data = extractPKCS1FromSPKI(spkiData) else {
            throw LeapCryptoError.invalidPublicKey
        }
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 1024
        ]
        var cfError: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(pkcs1Data as CFData, attrs as CFDictionary, &cfError) else {
            throw LeapCryptoError.rsaEncryptionFailed(cfError?.takeRetainedValue().localizedDescription ?? "SecKeyCreateWithData failed")
        }
        let plainData = Data(phone.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard let cipher = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, plainData as CFData, &cfError) as Data? else {
            throw LeapCryptoError.rsaEncryptionFailed(cfError?.takeRetainedValue().localizedDescription ?? "SecKeyCreateEncryptedData failed")
        }
        var b64 = cipher.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        while b64.hasSuffix("=") {
            b64.removeLast()
        }
        return b64
    }

    /// 从 X.509 `SubjectPublicKeyInfo` ASN.1 DER 中提取内部 `RSAPublicKey` PKCS#1 载荷
    /// 结构：`SEQUENCE { SEQUENCE { rsaEncryption OID, NULL }, BIT STRING (0x00 || RSAPublicKey) }`
    public static func extractPKCS1FromSPKI(_ spki: Data) -> Data? {
        let bytes = [UInt8](spki)
        var offset = 0

        func readLength() -> Int? {
            guard offset < bytes.count else { return nil }
            let first = Int(bytes[offset])
            offset += 1
            if first < 0x80 {
                return first
            }
            let numBytes = first & 0x7F
            guard numBytes > 0 && numBytes <= 4 && offset + numBytes <= bytes.count else { return nil }
            var length = 0
            for _ in 0..<numBytes {
                length = (length << 8) | Int(bytes[offset])
                offset += 1
            }
            return length
        }

        // 外层 SEQUENCE (0x30)
        guard offset < bytes.count, bytes[offset] == 0x30 else { return nil }
        offset += 1
        guard let _ = readLength() else { return nil }

        // AlgorithmIdentifier SEQUENCE (0x30)，跳过
        guard offset < bytes.count, bytes[offset] == 0x30 else { return nil }
        offset += 1
        guard let algLen = readLength(), offset + algLen <= bytes.count else { return nil }
        offset += algLen

        // BIT STRING (0x03)
        guard offset < bytes.count, bytes[offset] == 0x03 else { return nil }
        offset += 1
        guard let bitStrLen = readLength(), bitStrLen > 1, offset + bitStrLen <= bytes.count else { return nil }
        // 第 1 个字节为 unused bits 计数，正常为 0x00
        guard bytes[offset] == 0x00 else { return nil }
        offset += 1
        return Data(bytes[offset..<(offset + bitStrLen - 1)])
    }

    // MARK: - 7. 远程控车操控密码 AES-128-CBC 加密（AbstractC1805ni0.B）

    private static func md5Middle16ASCII(_ input: String) -> Data {
        let hex = md5Hex(input)
        let s = hex.index(hex.startIndex, offsetBy: 8)
        let e = hex.index(hex.startIndex, offsetBy: 24)
        return Data(hex[s..<e].utf8)
    }

    /// 精确实现 `AbstractC1805ni0.B(password, token)` 生成 `oppwd`
    public static func encryptOpPassword(_ password: String, token: String) throws -> String {
        var normToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if normToken.count >= 32 && normToken.count < 64 {
            normToken += normToken
        }
        guard normToken.count >= 64 else {
            throw LeapCryptoError.tokenTooShortForOpPassword
        }
        let idx32 = normToken.index(normToken.startIndex, offsetBy: 32)
        let idx64 = normToken.index(normToken.startIndex, offsetBy: 64)
        let keyData = md5Middle16ASCII(String(normToken[..<idx32]))
        let ivData = md5Middle16ASCII(String(normToken[idx32..<idx64]))
        let plainData = Data(password.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let encrypted = try aes128CBCEncrypt(data: plainData, key: keyData, iv: ivData)
        return encrypted.base64EncodedString()
    }

    // MARK: - 8. AES-128-CBC + PKCS7 通用封装（供 oppwd 与 BLE keyType==0 共用）

    public static func aes128CBCEncrypt(data: Data, key: Data, iv: Data) throws -> Data {
        try aes128CBC(operation: CCOperation(kCCEncrypt), data: data, key: key, iv: iv)
    }

    public static func aes128CBCDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        try aes128CBC(operation: CCOperation(kCCDecrypt), data: data, key: key, iv: iv)
    }

    private static func aes128CBC(operation: CCOperation, data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128 else {
            throw LeapCryptoError.aesFailed(Int32(kCCParamError))
        }
        let outCapacity = data.count + kCCBlockSizeAES128
        var outBytes = [UInt8](repeating: 0, count: outCapacity)
        var outMoved: size_t = 0

        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                data.withUnsafeBytes { dataPtr in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, kCCKeySizeAES128,
                        ivPtr.baseAddress,
                        dataPtr.baseAddress, data.count,
                        &outBytes, outCapacity,
                        &outMoved
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw LeapCryptoError.aesFailed(status)
        }
        return Data(outBytes.prefix(outMoved))
    }
}
