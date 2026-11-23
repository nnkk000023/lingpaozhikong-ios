import CryptoKit
import Foundation

public enum BLECryptoError: Error, LocalizedError, Equatable {
    case invalidVIN
    case invalidPasswordCard
    case invalidVehiclePublicKey
    case sm2ExchangeProviderRequired
    case crcMismatch
    case invalidFrameFormat(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVIN:
            return "车辆 VIN 不能为空"
        case .invalidPasswordCard:
            return "蓝牙证书 passwordCard 长度不足（需 >= 80 字节）"
        case .invalidVehiclePublicKey:
            return "车辆 ECDH 公钥格式无效（应为 65 字节未压缩点或 X.509 公钥）"
        case .sm2ExchangeProviderRequired:
            return "当前车辆蓝牙证书使用国密 SM2（keyType=1），请注入 SM2 曲线点乘交换实现"
        case .crcMismatch:
            return "蓝牙业务帧 CRC-8 校验失败"
        case .invalidFrameFormat(let detail):
            return "蓝牙帧格式异常：\(detail)"
        }
    }
}

/// 国密 `keyType == 1` SM2（`sm2p256v1`）协商扩展协议
/// 注意：SM3 摘要与 SM4-128-CBC 加解密已在本包原生提供，若实车证书为 `keyType == 1`，可注入 `sm2p256v1` 标量乘扩展实现该协议
public protocol SM2KeyExchanging: Sendable {
    func agree(vehiclePublicKeyBase64: String) throws -> (clientPublicKeyUncompressed65: Data, sharedSecret32: Data)
}

/// 零跑 BLE 蓝牙会话加解密与密钥派生引擎（精确对齐 `E9`, `Q9`, `C0393Pa`, `AbstractC0343Nc`）
public final class BLESessionCrypto: @unchecked Sendable {
    public let sessionId: UInt32
    public let keyType: BLEKeyType
    public let clientPublicKeyUncompressed65: Data
    public let aesOrSm4Key: Data
    public let aesOrSm4IV: Data
    public let certHash: Data
    public var isClosed: Bool = false

    /// 内部直接构造（测试或已完成协商后初始化）
    public init(
        sessionId: UInt32,
        keyType: BLEKeyType,
        clientPublicKeyUncompressed65: Data,
        aesOrSm4Key: Data,
        aesOrSm4IV: Data,
        certHash: Data
    ) {
        self.sessionId = sessionId
        self.keyType = keyType
        self.clientPublicKeyUncompressed65 = clientPublicKeyUncompressed65
        self.aesOrSm4Key = aesOrSm4Key
        self.aesOrSm4IV = aesOrSm4IV
        self.certHash = certHash
    }

    /// 根据云端蓝牙证书发起 ECDH（或 SM2）握手协商并派生 128-bit 会话 Key 与 IV
    public static func establish(
        certificate: BleKeyCertificate,
        sessionId: UInt32 = UInt32.random(in: 1...UInt32.max),
        sm2Exchanger: (any SM2KeyExchanging)? = nil
    ) throws -> BLESessionCrypto {
        let vinTrimmed = certificate.vin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vinTrimmed.isEmpty else { throw BLECryptoError.invalidVIN }
        guard certificate.passwordCard.utf8.count >= 80 else {
            throw BLECryptoError.invalidPasswordCard
        }

        let clientPubKey65: Data
        let sharedSecret32: Data

        switch certificate.keyType {
        case .p256AES:
            let vehiclePubData = try decodeVehicleP256Point(certificate.ecdhPublicKey)
            let ephemeral = P256.KeyAgreement.PrivateKey()
            // x963Representation 固定为 0x04 || X(32B) || Y(32B) 共 65 字节
            clientPubKey65 = ephemeral.publicKey.x963Representation
            let vehicleKey = try P256.KeyAgreement.PublicKey(x963Representation: vehiclePubData)
            let secret = try ephemeral.sharedSecretFromKeyAgreement(with: vehicleKey)
            sharedSecret32 = secret.withUnsafeBytes { Data($0) }
        case .sm2SM4:
            guard let sm2Exchanger else {
                throw BLECryptoError.sm2ExchangeProviderRequired
            }
            let agreed = try sm2Exchanger.agree(vehiclePublicKeyBase64: certificate.ecdhPublicKey)
            clientPubKey65 = agreed.clientPublicKeyUncompressed65
            sharedSecret32 = agreed.sharedSecret32
        }

        let derived = try deriveKeyAndIV(
            keyType: certificate.keyType,
            sessionId: sessionId,
            vin: vinTrimmed,
            passwordCard: certificate.passwordCard,
            sharedSecret: sharedSecret32
        )
        let certHash = computeCertificateHash(certificate)

        return BLESessionCrypto(
            sessionId: sessionId,
            keyType: certificate.keyType,
            clientPublicKeyUncompressed65: clientPubKey65,
            aesOrSm4Key: derived.key,
            aesOrSm4IV: derived.iv,
            certHash: certHash
        )
    }

    /// 精确实现 `E9.c()` 会话 Key/IV 派生算法
    public static func deriveKeyAndIV(
        keyType: BLEKeyType,
        sessionId: UInt32,
        vin: String,
        passwordCard: String,
        sharedSecret: Data
    ) throws -> (key: Data, iv: Data) {
        let cardBytes = Array(passwordCard.utf8)
        guard cardBytes.count >= 80 else {
            throw BLECryptoError.invalidPasswordCard
        }

        // 1. offsetSeed = LE4(sessionId) || reversed(vin).UTF8
        var offsetSeed = encodeLE(UInt64(sessionId), length: 4)
        let reversedVIN = String(vin.reversed())
        offsetSeed.append(Data(reversedVIN.utf8))

        // 2. offsetDigest = H(offsetSeed)
        let offsetDigest = digest(keyType: keyType, data: offsetSeed)
        let idx = (Int(offsetDigest[0] & 0xFF) >> 4) * 5
        guard idx + 5 <= cardBytes.count else {
            throw BLECryptoError.invalidPasswordCard
        }

        // 3. masterDigest = H(cardSlice(5B) || sharedSecret)
        var masterSeed = Data(cardBytes[idx..<(idx + 5)])
        masterSeed.append(sharedSecret)
        let masterDigest = digest(keyType: keyType, data: masterSeed)

        // 4. 转为 64 字节小写 hex ASCII 字符串，取 [0..<16] 作 Key、[48..<64] 作 IV
        let hexString = LeapCrypto.hexLower(masterDigest)
        let hexBytes = Array(hexString.utf8)
        guard hexBytes.count == 64 else {
            throw BLECryptoError.invalidFrameFormat("masterDigest 长度异常")
        }
        return (
            key: Data(hexBytes[0..<16]),
            iv: Data(hexBytes[48..<64])
        )
    }

    /// 计算证书 6 字段长度前缀绑定摘要 `AbstractC0343Nc.J(cert)`（SHA-256）
    public static func computeCertificateHash(_ cert: BleKeyCertificate) -> Data {
        let fields = [
            cert.ecdhPublicKey,
            String(cert.keyType.rawValue),
            cert.passwordCard,
            cert.plainText,
            cert.signResult,
            cert.vin
        ]
        var buf = Data()
        for f in fields {
            let utf8 = Data(f.utf8)
            buf.append(encodeLE(UInt64(utf8.count), length: 4))
            buf.append(utf8)
        }
        return Data(SHA256.hash(data: buf))
    }

    /// 摘要分发函数 `H(x)`：`keyType == 0` -> SHA-256；`keyType == 1` -> SM3
    public static func digest(keyType: BLEKeyType, data: Data) -> Data {
        switch keyType {
        case .p256AES:
            return Data(SHA256.hash(data: data))
        case .sm2SM4:
            return SM3.hash(data)
        }
    }

    /// 小端序无符号整数编码 `AbstractC0343Nc.y0(val, len)`
    public static func encodeLE(_ value: UInt64, length: Int) -> Data {
        var out = Data(capacity: length)
        for shift in 0..<length {
            out.append(UInt8((value >> (shift * 8)) & 0xFF))
        }
        return out
    }

    /// 小端序无符号整数解码
    public static func decodeLE(_ bytes: ArraySlice<UInt8>) -> UInt64 {
        var result: UInt64 = 0
        for (i, byte) in bytes.enumerated() {
            result |= UInt64(byte) << (i * 8)
        }
        return result
    }

    /// CRC-8 计算（多项式 `0x07`，初值 `0x00`，高位先出逐字节异或移位）
    public static func crc8(_ data: Data) -> UInt8 {
        var crc: UInt8 = 0x00
        for byte in data {
            crc ^= byte
            for _ in 0..<8 {
                if (crc & 0x80) != 0 {
                    crc = (crc << 1) ^ 0x07
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }

    /// 使用当前会话对称密钥加密（`keyType == 0`: AES-128-CBC；`keyType == 1`: SM4-128-CBC）
    public func encrypt(_ plain: Data) throws -> Data {
        switch keyType {
        case .p256AES:
            return try LeapCrypto.aes128CBCEncrypt(data: plain, key: aesOrSm4Key, iv: aesOrSm4IV)
        case .sm2SM4:
            return try SM4.encryptCBC(plaintext: plain, key: aesOrSm4Key, iv: aesOrSm4IV)
        }
    }

    /// 使用当前会话对称密钥解密
    public func decrypt(_ cipher: Data) throws -> Data {
        switch keyType {
        case .p256AES:
            return try LeapCrypto.aes128CBCDecrypt(data: cipher, key: aesOrSm4Key, iv: aesOrSm4IV)
        case .sm2SM4:
            return try SM4.decryptCBC(ciphertext: cipher, key: aesOrSm4Key, iv: aesOrSm4IV)
        }
    }

    /// 兼容从 65 字节裸点 Base64 或 X.509 SPKI DER 中提取 65 字节 P-256 未压缩点
    public static func decodeVehicleP256Point(_ base64String: String) throws -> Data {
        let cleaned = base64String.filter { !$0.isWhitespace && !$0.isNewline }
        guard let raw = Data(base64Encoded: cleaned) else {
            throw BLECryptoError.invalidVehiclePublicKey
        }
        if raw.count == 65 && raw[0] == 0x04 {
            return raw
        }
        // X.509 SubjectPublicKeyInfo for P-256 末尾固定为 65 字节未压缩点（前有 26B ASN.1 头）
        if raw.count > 65 {
            let tail = raw.suffix(65)
            if tail.first == 0x04 {
                return Data(tail)
            }
        }
        throw BLECryptoError.invalidVehiclePublicKey
    }
}
