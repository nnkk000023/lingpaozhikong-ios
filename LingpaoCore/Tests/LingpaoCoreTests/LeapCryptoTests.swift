import CommonCrypto
import CryptoKit
import XCTest
@testable import LingpaoCore

final class LeapCryptoTests: XCTestCase {
    func testConcatSortedValuesJoinsValuesWithoutDelimiterOrKeyNames() {
        let first: [String: String?] = [
            "b": "valB",
            "a": "valA",
            "ignored": nil
        ]
        let second: [String: String?] = [
            "b": "overrideB",
            "0": "zero"
        ]
        // Key ASCII 升序： "0" -> "a" -> "b"，值直接无分隔拼接
        let result = LeapCrypto.concatSortedValues(first, second)
        XCTAssertEqual(result, "zero" + "valA" + "overrideB")
    }

    func testSignLegacyParamsComputesMiddle16MD5AndRemovesToken() {
        let signed = LeapCrypto.signLegacyParams(
            business: ["vin": "LTEST1234567890"],
            deviceID: "dev001",
            tokenOrRefreshToken: "secretTokenVal",
            isRefresh: false,
            includeTimestamp: true,
            timestampMs: 1_700_000_000_000,
            nonce: "12345"
        )
        XCTAssertNil(signed["token"])
        XCTAssertNil(signed["refreshtoken"])
        XCTAssertEqual(signed["timespan"], "1700000000000")
        XCTAssertEqual(signed["nonce"], "12345")
        XCTAssertEqual(signed["deviceID"], "dev001")
        XCTAssertEqual(signed["vin"], "LTEST1234567890")

        // 预期顺序（ASCII 升序）：deviceID -> nonce -> timespan -> token -> vin
        let raw = "dev001" + "12345" + "1700000000000" + "secretTokenVal" + "LTEST1234567890"
        let fullMD5 = LeapCrypto.md5Hex(raw)
        let s = fullMD5.index(fullMD5.startIndex, offsetBy: 8)
        let e = fullMD5.index(fullMD5.startIndex, offsetBy: 24)
        XCTAssertEqual(signed["signStr"], String(fullMD5[s..<e]))
        XCTAssertEqual(signed["signStr"]?.count, 16)
    }

    func testGatewayHmacKeyDerivationXORsJWTSignatureWithR2AndR3() throws {
        // 构造固定 4 字节签名和 r2, r3
        let sigBytes = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let r2Bytes = Data([0x11, 0x22, 0x33, 0x44])
        let r3Bytes = Data([0x55, 0x66, 0x77, 0x88])
        let payloadJSON = try JSONSerialization.data(withJSONObject: [
            "user_name": "u1|deviceId:extractedDevice99",
            "exp": 1_800_000_000
        ])

        func toB64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        let jwt = "\(toB64URL(Data("{\"alg\":\"HS256\"}".utf8))).\(toB64URL(payloadJSON)).\(toB64URL(sigBytes))"
        let loginObj: [String: Any] = [
            "accessToken": jwt,
            "refreshToken": "gwRef001",
            "accountId": "acc01",
            "signParam": [
                "r2": r2Bytes.base64EncodedString(),
                "r3": r3Bytes.base64EncodedString()
            ]
        ]

        let derived = try LeapCrypto.deriveGatewaySession(from: loginObj, fallbackAccountId: "acc01")
        XCTAssertEqual(derived.extractedDeviceId, "extractedDevice99")
        XCTAssertEqual(derived.session.expiresAtMs, 1_800_000_000_000)

        let expectedBytes: [UInt8] = [
            UInt8(0xAA ^ 0x11 ^ 0x55),
            UInt8(0xBB ^ 0x22 ^ 0x66),
            UInt8(0xCC ^ 0x33 ^ 0x77),
            UInt8(0xDD ^ 0x44 ^ 0x88)
        ]
        let expectedKey = Data(expectedBytes)
        XCTAssertEqual(derived.session.hmacKeyData, expectedKey)
    }

    func testEncryptPhoneRSASucceedsAndOmitsTrailingPadding() throws {
        let encrypted = try LeapCrypto.encryptPhoneRSA("13800138000")
        XCTAssertFalse(encrypted.isEmpty)
        XCTAssertFalse(encrypted.contains("="))
        XCTAssertFalse(encrypted.contains("+"))
        XCTAssertFalse(encrypted.contains("/"))
    }

    func testEncryptOpPasswordDoublesShort32TokenAndProducesValidAES128CBC() throws {
        let shortToken32 = "0123456789abcdef0123456789abcdef"
        let b64 = try LeapCrypto.encryptOpPassword("1234", token: shortToken32)
        guard let cipher = Data(base64Encoded: b64) else {
            XCTFail("密文非合法 Base64")
            return
        }
        // 使用规范 Key/IV 手工反向解密校验等于 "1234"
        let keyHex = LeapCrypto.md5Hex(shortToken32)
        let ks = keyHex.index(keyHex.startIndex, offsetBy: 8)
        let ke = keyHex.index(keyHex.startIndex, offsetBy: 24)
        let keyData = Data(keyHex[ks..<ke].utf8)
        let plain = try LeapCrypto.aes128CBCDecrypt(data: cipher, key: keyData, iv: keyData)
        XCTAssertEqual(String(data: plain, encoding: .utf8), "1234")
    }

    func testSM3AndSM4RoundTripAndStandardVector() throws {
        // GM/T 0004-2012 标准测试向量：SM3("abc")
        let digest = SM3.hash(Data("abc".utf8))
        XCTAssertEqual(
            LeapCrypto.hexLower(digest),
            "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0"
        )

        let key = Data((0..<16).map { UInt8($0) })
        let iv = Data((16..<32).map { UInt8($0) })
        let plain = Data("零跑BLE国密SM4测试载荷123".utf8)
        let cipher = try SM4.encryptCBC(plaintext: plain, key: key, iv: iv)
        let decrypted = try SM4.decryptCBC(ciphertext: cipher, key: key, iv: iv)
        XCTAssertEqual(decrypted, plain)
    }
}
