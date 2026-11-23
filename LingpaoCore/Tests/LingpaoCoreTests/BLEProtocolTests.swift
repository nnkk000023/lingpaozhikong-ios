import CryptoKit
import XCTest
@testable import LingpaoCore

final class BLEProtocolTests: XCTestCase {
    func testExtractProtocolMinorFromAdvertisingUUIDs() {
        let uuids = [
            "0000fffe-0000-1000-8000-00805f9b34fb",
            "00000109-0000-1000-8000-00805f9b34fb"
        ]
        XCTAssertEqual(BLEConstants.extractProtocolMinor(from: uuids), 9)
        XCTAssertNil(BLEConstants.extractProtocolMinor(from: ["0000fffe-0000-1000-8000-00805f9b34fb"]))
    }

    func testCRC8Polynomial0x07() {
        let sample = Data("123456789".utf8)
        // 标准 CRC-8/SMBUS (poly=0x07, init=0x00) 对 "123456789" 的校验值为 0xF4
        XCTAssertEqual(BLESessionCrypto.crc8(sample), 0xF4)
    }

    func testECDHKeyDerivationCommandFrameAndSlidingBufferRoundTrip() throws {
        let vehiclePrivate = P256.KeyAgreement.PrivateKey()
        let vehiclePubBase64 = vehiclePrivate.publicKey.x963Representation.base64EncodedString()
        let passwordCard = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", count: 3) // 108 bytes
        let cert = BleKeyCertificate(
            vin: "LPZ1234567890TEST",
            ecdhPublicKey: vehiclePubBase64,
            keyType: .p256AES,
            passwordCard: passwordCard,
            plainText: "v1;accPlaceholder;devPlaceholder;extra1;extra2;extra3",
            signResult: Data("sigBytes".utf8).base64EncodedString()
        )

        let session = try BLESessionCrypto.establish(certificate: cert, sessionId: 0x1122_3344)
        XCTAssertEqual(session.clientPublicKeyUncompressed65.count, 65)
        XCTAssertEqual(session.clientPublicKeyUncompressed65[0], 0x04)
        XCTAssertEqual(session.aesOrSm4Key.count, 16)
        XCTAssertEqual(session.aesOrSm4IV.count, 16)

        // 1. 测试认证帧 0xAA 0xAE
        let authFrame = try BLEFrameCodec.encodeAuthFrame(
            crypto: session,
            certificate: cert,
            accountId: "1008899",
            deviceId: "iosDevice123",
            unixSeconds: 1_700_000_123
        )
        XCTAssertEqual(authFrame[0], 0xAA)
        XCTAssertEqual(authFrame[1], 0xAE)

        // 2. 测试业务锁车指令 0xAA 0xAB，并用车端侧反向解密校对 CRC-8 与 cmd
        let lockFrame = try BLEFrameCodec.encodeCommandFrame(
            crypto: session,
            command: .lock,
            unixSeconds: 1_700_000_200
        )
        XCTAssertEqual(lockFrame[0], 0xAA)
        XCTAssertEqual(lockFrame[1], 0xAB)
        let payloadLen = Int(BLESessionCrypto.decodeLE([UInt8](lockFrame)[2..<6]))
        let b64Data = lockFrame[6..<(6 + payloadLen)]
        let cipher = Data(base64Encoded: b64Data)!
        let plainCRCBody = try session.decrypt(cipher)
        let crc = plainCRCBody[0]
        let body = plainCRCBody.dropFirst()
        XCTAssertEqual(crc, BLESessionCrypto.crc8(Data(body)))
        XCTAssertEqual(body[body.startIndex + 8], BLECommandCode.lock.rawValue)

        // 3. 测试下行粘包/半包滑窗解析：1 条快速凭证响应 0xAA 0xAB + 1 条确认门锁事件 0xAA 0xAC
        let credEncB64 = try session.encrypt(Data("1;deadbeefcafebabe".utf8)).base64EncodedData()
        var encDownFrame = Data([0xAA, 0xAB])
        encDownFrame.append(BLESessionCrypto.encodeLE(UInt64(credEncB64.count), length: 4))
        encDownFrame.append(credEncB64)

        var eventFrame = Data([0xAA, 0xAC, 0x00, 0x00, 0x00, 0x00])
        eventFrame.append(BLESessionCrypto.encodeLE(3, length: 2))
        eventFrame.append(contentsOf: [0x01, 0x09]) // header padded to 10B
        eventFrame.append(contentsOf: [0x02, 0x01, 0x01]) // doorActionConfirm(trigger=1, action=lock)

        var combined = Data([0x00, 0xFF]) // 模拟前导噪声
        combined.append(encDownFrame)
        combined.append(eventFrame)

        let ring = BLEFrameBuffer()
        // 分两半喂入模拟半包与粘包
        let part1 = try ring.appendAndExtract(combined.prefix(12))
        let part2 = try ring.appendAndExtract(combined.dropFirst(12))
        let allFrames = part1 + part2
        XCTAssertEqual(allFrames.count, 2)

        let ev1 = try BLEFrameBuffer.decodeEvent(from: allFrames[0], crypto: session)
        XCTAssertEqual(ev1, .reconnectCredential("deadbeefcafebabe"))

        let ev2 = try BLEFrameBuffer.decodeEvent(from: allFrames[1], crypto: session)
        XCTAssertEqual(ev2, .doorActionConfirm(triggerSource: 1, action: 1))

        // 4. 测试快速重连帧 0xAA 0xEE（含 16B 摘要尾）
        let reconnect = try BLEFrameCodec.encodeReconnectFrame(
            crypto: session,
            credentialHex: "deadbeefcafebabe",
            accountId: "1008899",
            unixSeconds: 1_700_000_300
        )
        XCTAssertEqual(reconnect[0], 0xAA)
        XCTAssertEqual(reconnect[1], 0xEE)
        let recTotalLen = Int(BLESessionCrypto.decodeLE([UInt8](reconnect)[2..<4]))
        XCTAssertEqual(reconnect.count, 4 + recTotalLen)
    }

    func testSM4CryptoEstablishWithMockedSM2Exchanger() throws {
        struct MockSM2: SM2KeyExchanging {
            func agree(vehiclePublicKeyBase64: String) throws -> (clientPublicKeyUncompressed65: Data, sharedSecret32: Data) {
                var pub = Data([0x04])
                pub.append(Data(repeating: 0x22, count: 64))
                return (pub, Data(repeating: 0x5A, count: 32))
            }
        }
        let cert = BleKeyCertificate(
            vin: "LPZSM2TEST0000001",
            ecdhPublicKey: "placeholder",
            keyType: .sm2SM4,
            passwordCard: String(repeating: "0123456789", count: 9),
            plainText: "v1;a;d;x;y;z",
            signResult: Data("sig".utf8).base64EncodedString()
        )
        let session = try BLESessionCrypto.establish(certificate: cert, sessionId: 42, sm2Exchanger: MockSM2())
        let msg = Data("SM4_KEY_TEST".utf8)
        let enc = try session.encrypt(msg)
        let dec = try session.decrypt(enc)
        XCTAssertEqual(dec, msg)
    }
}
