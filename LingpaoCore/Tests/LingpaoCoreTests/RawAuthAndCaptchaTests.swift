import XCTest
@testable import LingpaoCore

final class RawAuthAndCaptchaTests: XCTestCase {
    func testRawAuthParsesNestedAppLoginVOJSON() throws {
        let json = """
        {
          "deviceID": "myDev998877665544",
          "smDeviceId": "B1234567890ABCDEF",
          "data": {
            "phone": "13900001111",
            "appLoginVO": {
              "accountId": "1008899",
              "token": "oldTok_abcdef1234567890",
              "refreshToken": "oldRef_1234567890abcdef",
              "tokenExpired": "21600"
            }
          }
        }
        """
        let parsed = try RawAuthParser.parse(rawText: json)
        XCTAssertEqual(parsed.accountId, "1008899")
        XCTAssertEqual(parsed.token, "oldTok_abcdef1234567890")
        XCTAssertEqual(parsed.refreshToken, "oldRef_1234567890abcdef")
        XCTAssertEqual(parsed.deviceId, "myDev998877665544")
        XCTAssertEqual(parsed.smDeviceId, "B1234567890ABCDEF")
        XCTAssertEqual(parsed.phone, "13900001111")
    }

    func testRawAuthParsesSingleLineCommaFormat() throws {
        let parsed = try RawAuthParser.parse(rawText: "acc9988, tok_1234567890123456, ref_1234567890123456", phoneInput: "13800001111")
        XCTAssertEqual(parsed.accountId, "acc9988")
        XCTAssertEqual(parsed.token, "tok_1234567890123456")
        XCTAssertEqual(parsed.refreshToken, "ref_1234567890123456")
        XCTAssertEqual(parsed.phone, "13800001111")
    }

    func testRawAuthParsesCapturedHeadersText() throws {
        let dump = """
        POST /app-user HTTP/1.1
        accountId: 88776655
        XFX-CDN-CROSS-NODE: capturedToken_abcdefgh1234
        XFX-CDN-CROSS-REFRESH-NODE: capturedRefresh_abcdefgh12
        APPImei: imei_9988776655443322
        """
        let parsed = try RawAuthParser.parse(rawText: dump)
        XCTAssertEqual(parsed.accountId, "88776655")
        XCTAssertEqual(parsed.token, "capturedToken_abcdefgh1234")
        XCTAssertEqual(parsed.refreshToken, "capturedRefresh_abcdefgh12")
        XCTAssertEqual(parsed.deviceId, "imei_9988776655443322")
    }

    func testExtractCaptchaIdFromRiskTypeOrFallback() {
        let extracted = GeetestChallenge.extractCaptchaId(from: "slide|abcdef0123456789abcdef0123456789|v4")
        XCTAssertEqual(extracted, "abcdef0123456789abcdef0123456789")

        let fallback = GeetestChallenge.extractCaptchaId(from: "unknown|risk")
        XCTAssertEqual(fallback, GeetestChallenge.fallbackCaptchaId)
    }
}
