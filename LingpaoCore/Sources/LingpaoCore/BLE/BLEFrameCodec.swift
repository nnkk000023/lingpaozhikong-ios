import Foundation

/// 零跑 BLE 上行封包器与下行滑窗拆包解码器（精确对应 `Q9`, `C0341Na`, `C0367Oa`, `C0523Ua`）
public enum BLEFrameCodec {
    /// 封装常规加密业务控制帧 `0xAA 0xAB`（对应 `Q9.a`）
    public static func encodeCommandFrame(
        crypto: BLESessionCrypto,
        command: BLECommandCode,
        payload: Data = Data(),
        unixSeconds: UInt64 = UInt64(Date().timeIntervalSince1970)
    ) throws -> Data {
        var body = BLESessionCrypto.encodeLE(unixSeconds, length: 8)
        body.append(command.rawValue)
        body.append(payload)

        var crcBody = Data([BLESessionCrypto.crc8(body)])
        crcBody.append(body)

        let cipher = try crypto.encrypt(crcBody)
        let b64Data = Data(cipher.base64EncodedString().utf8)

        var frame = Data([0xAA, BLEFrameType.encrypted.rawValue])
        frame.append(BLESessionCrypto.encodeLE(UInt64(b64Data.count), length: 4))
        frame.append(b64Data)
        return frame
    }

    /// 封装首次完整认证握手帧 `0xAA 0xAE`（对应 `C0341Na.c`）
    public static func encodeAuthFrame(
        crypto: BLESessionCrypto,
        certificate: BleKeyCertificate,
        accountId: String,
        deviceId: String,
        configuration: BLEPassiveConfiguration = BLEPassiveConfiguration(),
        protocolMinor: Int = BLEConstants.defaultProtocolMinor,
        buttonCap: Bool = false,
        v2Mode: Bool = false,
        unixSeconds: UInt64 = UInt64(Date().timeIntervalSince1970)
    ) throws -> Data {
        var certParts = certificate.plainText.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard certParts.count >= 6 else {
            throw BLECryptoError.invalidFrameFormat("证书 plainText 字段不足 6 段")
        }
        if v2Mode {
            certParts = [certParts[0], accountId, deviceId, certParts[3], certParts[4], certParts[5]]
        } else {
            certParts[1] = accountId
            certParts[2] = deviceId
        }

        let calibStr = configuration.calibration.formattedString
        let switchStr: String
        if v2Mode {
            let full9 = configuration.wirePayload9Bytes(buttonCap: buttonCap)
            switchStr = full9.suffix(4).map { String($0) }.joined(separator: ";")
        } else {
            let switches = buildLegacySwitchBytes(configuration: configuration, protocolMinor: protocolMinor)
            switchStr = switches.map { String($0) }.joined(separator: ";")
        }

        let configString = "\(unixSeconds);\(certParts.joined(separator: ";"));\(calibStr);\(switchStr);"
        let configBytes = Data(configString.utf8)

        let cleanedSign = certificate.signResult.filter { !$0.isWhitespace && !$0.isNewline }
        guard let signBytes = Data(base64Encoded: cleanedSign), !signBytes.isEmpty else {
            throw BLECryptoError.invalidFrameFormat("证书 signResult Base64 无效")
        }

        var authPlain = BLESessionCrypto.encodeLE(UInt64(configBytes.count), length: 4)
        authPlain.append(configBytes)
        authPlain.append(signBytes)

        let encryptedAuth = try crypto.encrypt(authPlain)
        let b64Auth = Data(encryptedAuth.base64EncodedString().utf8)

        var inner = BLESessionCrypto.encodeLE(UInt64(crypto.sessionId), length: 4)
        inner.append(crypto.clientPublicKeyUncompressed65)
        inner.append(b64Auth)
        inner.append(contentsOf: [0x01, 0x09])

        guard inner.count <= 65_535 else {
            throw BLECryptoError.invalidFrameFormat("认证握手帧过长")
        }

        var frame = Data([0xAA, BLEFrameType.authentication.rawValue])
        frame.append(BLESessionCrypto.encodeLE(UInt64(inner.count), length: 2))
        frame.append(inner)
        return frame
    }

    /// 封装凭快速凭证重连帧 `0xAA 0xEE`（对应 `C0367Oa.c`）
    public static func encodeReconnectFrame(
        crypto: BLESessionCrypto,
        credentialHex: String,
        accountId: String,
        configuration: BLEPassiveConfiguration = BLEPassiveConfiguration(),
        buttonCap: Bool = false,
        unixSeconds: UInt64 = UInt64(Date().timeIntervalSince1970)
    ) throws -> Data {
        guard let credBytes = hexToBytes(credentialHex) else {
            throw BLECryptoError.invalidFrameFormat("快速重连凭证 Hex 格式无效")
        }
        let accountData = Data(accountId.utf8)
        guard !accountData.isEmpty && accountData.count <= 65_535 else {
            throw BLECryptoError.invalidFrameFormat("accountId 长度无效")
        }

        var plain = BLESessionCrypto.encodeLE(unixSeconds, length: 8)
        plain.append(credBytes)
        plain.append(contentsOf: configuration.wirePayload9Bytes(buttonCap: buttonCap))
        plain.append(BLESessionCrypto.encodeLE(UInt64(accountData.count), length: 2))
        plain.append(accountData)

        let encrypted = try crypto.encrypt(plain)
        let b64Rec = Data(encrypted.base64EncodedString().utf8)

        let totalLen = b64Rec.count + 87
        guard totalLen <= 65_535 else {
            throw BLECryptoError.invalidFrameFormat("快速重连帧过长")
        }

        var body = Data([0xAA, BLEFrameType.reconnect.rawValue])
        body.append(BLESessionCrypto.encodeLE(UInt64(totalLen), length: 2))
        body.append(BLESessionCrypto.encodeLE(UInt64(crypto.sessionId), length: 4))
        body.append(crypto.clientPublicKeyUncompressed65)
        body.append(b64Rec)
        body.append(contentsOf: [0x01, 0x09])

        let digest = BLESessionCrypto.digest(keyType: crypto.keyType, data: body)
        guard digest.count >= 16 else {
            throw BLECryptoError.invalidFrameFormat("摘要长度不足 16 字节")
        }
        body.append(digest.prefix(16))
        return body
    }

    /// 构造经典开关参数字节（对应 `U9.b(protocolMinor)`）
    private static func buildLegacySwitchBytes(configuration: BLEPassiveConfiguration, protocolMinor: Int) -> [UInt8] {
        let enabled = configuration.enabled
        let b0: UInt8 = (!enabled || (protocolMinor < 9 && !configuration.autoUnlock)) ? 0 : 1
        let b1: UInt8 = (enabled && configuration.autoLock) ? 1 : 0
        if protocolMinor < 9 {
            return [b0, b1]
        }
        let b2: UInt8 = (enabled && configuration.autoUnlock) ? 1 : 0
        let b3: UInt8 = (enabled && configuration.buttonEnabled) ? 1 : 0
        return [b0, b1, b2, b3]
    }

    public static func hexToBytes(_ hex: String) -> Data? {
        let cleaned = hex.filter { !$0.isWhitespace && !$0.isNewline }
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let nextIdx = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<nextIdx], radix: 16) else { return nil }
            data.append(byte)
            idx = nextIdx
        }
        return data
    }
}

/// 原始已切分下行帧
public struct BLERawFrame: Equatable, Sendable {
    public let type: BLEFrameType
    public let rawData: Data
}

/// BLE Notify 滑窗粘包/半包切帧缓冲（精确对齐 `C2743z9` 与 `C0523Ua.b`）
public final class BLEFrameBuffer {
    private var buffer: [UInt8] = []
    public let maxSize: Int

    public init(maxSize: Int = BLEConstants.maxReceiveBufferSize) {
        self.maxSize = maxSize
    }

    public func reset() {
        buffer.removeAll(keepingCapacity: false)
    }

    /// 追加一段下行蓝牙通知字节并切出所有完整帧
    public func appendAndExtract(_ incoming: Data) throws -> [BLERawFrame] {
        guard incoming.count <= maxSize else {
            throw BLECryptoError.invalidFrameFormat("单次接收数据超出上限 \(maxSize)")
        }
        buffer.append(contentsOf: incoming)
        var frames: [BLERawFrame] = []
        var cursor = 0

        while buffer.count - cursor >= 2 {
            let b0 = buffer[cursor]
            let b1 = buffer[cursor + 1]
            guard b0 == 0xAA else {
                cursor += 1
                continue
            }
            let frameType: BLEFrameType
            if b1 == BLEFrameType.encrypted.rawValue {
                frameType = .encrypted
            } else if b1 == BLEFrameType.event.rawValue {
                frameType = .event
            } else {
                cursor += 1
                continue
            }

            let headerLen = (frameType == .event) ? 10 : 6
            guard buffer.count - cursor >= headerLen else {
                break
            }

            let lenOffset = (frameType == .event) ? (cursor + 6) : (cursor + 2)
            let lenSize = (frameType == .event) ? 2 : 4
            let payloadLen = BLESessionCrypto.decodeLE(buffer[lenOffset..<(lenOffset + lenSize)])

            if frameType == .encrypted && payloadLen == 0 {
                cursor += 1
                continue
            }
            let totalLen = UInt64(headerLen) + payloadLen
            guard totalLen <= UInt64(maxSize) else {
                cursor += 1
                continue
            }
            if UInt64(buffer.count - cursor) >= totalLen {
                let end = cursor + Int(totalLen)
                frames.append(BLERawFrame(type: frameType, rawData: Data(buffer[cursor..<end])))
                cursor = end
            } else {
                break
            }
        }

        if cursor > 0 {
            buffer.removeFirst(cursor)
        }
        if buffer.count == 1 && buffer[0] != 0xAA {
            buffer.removeAll(keepingCapacity: true)
        }
        if buffer.count > maxSize {
            buffer.removeAll(keepingCapacity: false)
            throw BLECryptoError.invalidFrameFormat("接收缓冲溢出上限 \(maxSize)")
        }
        return frames
    }

    /// 将已切分帧解密并解析为语义事件 `BLEDownlinkEvent`
    public static func decodeEvent(from rawFrame: BLERawFrame, crypto: BLESessionCrypto) throws -> BLEDownlinkEvent {
        let bytes = [UInt8](rawFrame.rawData)
        switch rawFrame.type {
        case .encrypted:
            guard bytes.count >= 6 else {
                throw BLECryptoError.invalidFrameFormat("0xAAAB 帧长度不足")
            }
            let b64Str = String(decoding: bytes[6...], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let cipherData = Data(base64Encoded: b64Str) else {
                throw BLECryptoError.invalidFrameFormat("0xAAAB 载荷 Base64 无效")
            }
            let plainData = try crypto.decrypt(cipherData)
            let text = String(decoding: plainData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = text.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            let tag = parts.first ?? ""
            switch tag {
            case "0":
                return .authenticatedConfirm(parts)
            case "1":
                let cred = parts.count > 1 ? parts[1] : ""
                return .reconnectCredential(cred)
            case "2":
                return .keyConfigResponse(parts)
            default:
                return .unknownEncrypted(parts)
            }

        case .event:
            guard bytes.count >= 11 else {
                throw BLECryptoError.invalidFrameFormat("0xAAAC 事件帧缺少载荷")
            }
            let payload = Array(bytes[10...])
            let eventType = payload[0]
            if eventType == 1 {
                return .errorCode(payload.last ?? 0)
            } else if eventType == 2 && payload.count >= 3 {
                return .doorActionConfirm(triggerSource: payload[1], action: payload[2])
            }
            throw BLECryptoError.invalidFrameFormat("未知事件类型 \(eventType)")

        case .authentication, .reconnect:
            throw BLECryptoError.invalidFrameFormat("上行握手帧不应出现在下行通道")
        }
    }
}
