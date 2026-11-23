import Foundation

/// 国密 SM3（GM/T 0004-2012）与 SM4-128-CBC + PKCS7（GM/T 0002-2012）纯 Swift 原生实现
/// 零外部 C 库依赖，可用于 `keyType == 1` 的 BLE 会话密钥派生与加解密
public enum SM3 {
    private static let iv: [UInt32] = [
        0x7380166F, 0x4914B2B9, 0x172442D7, 0xDA8A0600,
        0xA96F30BC, 0x163138AA, 0xE38DEE4D, 0xB0FB0E4E
    ]

    public static func hash(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        let bitLen = UInt64(bytes.count) * 8

        // 消息填充：先补 0x80，再补 0 直到长度 ≡ 56 (mod 64)，最后附大端 64 位比特长度
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0x00)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLen >> shift) & 0xFF))
        }

        var v = iv
        var w = [UInt32](repeating: 0, count: 68)
        var w1 = [UInt32](repeating: 0, count: 64)

        for offset in stride(from: 0, to: bytes.count, by: 64) {
            for j in 0..<16 {
                let idx = offset + j * 4
                w[j] = (UInt32(bytes[idx]) << 24)
                    | (UInt32(bytes[idx + 1]) << 16)
                    | (UInt32(bytes[idx + 2]) << 8)
                    | UInt32(bytes[idx + 3])
            }
            for j in 16..<68 {
                let term = w[j - 16] ^ w[j - 9] ^ rotL(w[j - 3], 15)
                w[j] = p1(term) ^ rotL(w[j - 13], 7) ^ w[j - 6]
            }
            for j in 0..<64 {
                w1[j] = w[j] ^ w[j + 4]
            }

            var a = v[0], b = v[1], c = v[2], d = v[3]
            var e = v[4], f = v[5], g = v[6], h = v[7]

            for j in 0..<64 {
                let tj: UInt32 = j < 16 ? 0x79CC4519 : 0x7A879D8A
                let ss1 = rotL(rotL(a, 12) &+ e &+ rotL(tj, UInt32(j % 32)), 7)
                let ss2 = ss1 ^ rotL(a, 12)
                let tt1 = ff(j, a, b, c) &+ d &+ ss2 &+ w1[j]
                let tt2 = gg(j, e, f, g) &+ h &+ ss1 &+ w[j]
                d = c
                c = rotL(b, 9)
                b = a
                a = tt1
                h = g
                g = rotL(f, 19)
                f = e
                e = p0(tt2)
            }

            v[0] ^= a; v[1] ^= b; v[2] ^= c; v[3] ^= d
            v[4] ^= e; v[5] ^= f; v[6] ^= g; v[7] ^= h
        }

        var out = Data(capacity: 32)
        for word in v {
            out.append(UInt8((word >> 24) & 0xFF))
            out.append(UInt8((word >> 16) & 0xFF))
            out.append(UInt8((word >> 8) & 0xFF))
            out.append(UInt8(word & 0xFF))
        }
        return out
    }

    @inline(__always)
    private static func rotL(_ x: UInt32, _ n: UInt32) -> UInt32 {
        let s = n & 31
        return s == 0 ? x : ((x << s) | (x >> (32 - s)))
    }

    @inline(__always)
    private static func p0(_ x: UInt32) -> UInt32 {
        x ^ rotL(x, 9) ^ rotL(x, 17)
    }

    @inline(__always)
    private static func p1(_ x: UInt32) -> UInt32 {
        x ^ rotL(x, 15) ^ rotL(x, 23)
    }

    @inline(__always)
    private static func ff(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        j < 16 ? (x ^ y ^ z) : ((x & y) | (x & z) | (y & z))
    }

    @inline(__always)
    private static func gg(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        j < 16 ? (x ^ y ^ z) : ((x & y) | (~x & z))
    }
}

public enum SM4Error: Error, LocalizedError, Equatable {
    case invalidKeyLength
    case invalidIVLength
    case invalidInputLength
    case invalidPadding

    public var errorDescription: String? {
        switch self {
        case .invalidKeyLength: return "SM4 密钥必须为 16 字节"
        case .invalidIVLength: return "SM4 CBC IV 必须为 16 字节"
        case .invalidInputLength: return "SM4 CBC 密文长度必须为 16 的正整数倍"
        case .invalidPadding: return "SM4 解密 PKCS7 填充无效"
        }
    }
}

public enum SM4 {
    private static let sbox: [UInt8] = [
        0xD6, 0x90, 0xE9, 0xFE, 0xCC, 0xE1, 0x3D, 0xB7, 0x16, 0xB6, 0x14, 0xC2, 0x28, 0xFB, 0x2C, 0x05,
        0x2B, 0x67, 0x9A, 0x76, 0x2A, 0xBE, 0x04, 0xC3, 0xAA, 0x44, 0x13, 0x26, 0x49, 0x86, 0x06, 0x99,
        0x9C, 0x42, 0x50, 0xF4, 0x91, 0xEF, 0x98, 0x7A, 0x33, 0x54, 0x0B, 0x43, 0xED, 0xCF, 0xAC, 0x62,
        0xE4, 0xB3, 0x1C, 0xA9, 0xC9, 0x08, 0xE8, 0x95, 0x80, 0xDF, 0x94, 0xFA, 0x75, 0x8F, 0x3F, 0xA6,
        0x47, 0x07, 0xA7, 0xFC, 0xF3, 0x73, 0x17, 0xBA, 0x83, 0x59, 0x3C, 0x19, 0xE6, 0x85, 0x4F, 0xA8,
        0x68, 0x6B, 0x81, 0xB2, 0x71, 0x64, 0xDA, 0x8B, 0xF8, 0xEB, 0x0F, 0x4B, 0x70, 0x56, 0x9D, 0x35,
        0x1E, 0x24, 0x0E, 0x5E, 0x63, 0x58, 0xD1, 0xA2, 0x25, 0x22, 0x7C, 0x3B, 0x01, 0x21, 0x78, 0x87,
        0xD4, 0x00, 0x46, 0x57, 0x9F, 0xD3, 0x27, 0x52, 0x4C, 0x36, 0x02, 0xE7, 0xA0, 0xC4, 0xC8, 0x9E,
        0xEA, 0xBF, 0x8A, 0xD2, 0x40, 0xC7, 0x38, 0xB5, 0xA3, 0xF7, 0xF2, 0xCE, 0xF9, 0x61, 0x15, 0xA1,
        0xE0, 0xAE, 0x5D, 0xA4, 0x9B, 0x34, 0x1A, 0x55, 0xAD, 0x93, 0x32, 0x30, 0xF5, 0x8C, 0xB1, 0xE3,
        0x1D, 0xF6, 0xE2, 0x2E, 0x82, 0x66, 0xCA, 0x60, 0xC0, 0x29, 0x23, 0xAB, 0x0D, 0x53, 0x4E, 0x6F,
        0xD5, 0xDB, 0x37, 0x45, 0xDE, 0xFD, 0x8E, 0x2F, 0x03, 0xFF, 0x6A, 0x72, 0x6D, 0x6C, 0x5B, 0x51,
        0x8D, 0x1B, 0xAF, 0x92, 0xBB, 0xDD, 0xBC, 0x7F, 0x11, 0xD9, 0x5C, 0x41, 0x1F, 0x10, 0x5A, 0xD8,
        0x0A, 0xC1, 0x31, 0x88, 0xA5, 0xCD, 0x7B, 0xBD, 0x2D, 0x74, 0xD0, 0x12, 0xB8, 0xE5, 0xB4, 0xB0,
        0x89, 0x69, 0x97, 0x4A, 0x0C, 0x96, 0x77, 0x7E, 0x65, 0xB9, 0xF1, 0x09, 0xC5, 0x6E, 0xC6, 0x84,
        0x18, 0xF0, 0x7D, 0xEC, 0x3A, 0xDC, 0x4D, 0x20, 0x79, 0xEE, 0x5F, 0x3E, 0xD7, 0xCB, 0x39, 0x48
    ]

    private static let fk: [UInt32] = [0xA3B1BAC6, 0x56AA3350, 0x677D9197, 0xB27022DC]

    private static let ck: [UInt32] = [
        0x00070E15, 0x1C232A31, 0x383F464D, 0x545B6269,
        0x70777E85, 0x8C939AA1, 0xA8AFB6BD, 0xC4CBD2D9,
        0xE0E7EEF5, 0xFC030A11, 0x181F262D, 0x343B4249,
        0x50575E65, 0x6C737A81, 0x888F969D, 0xA4ABB2B9,
        0xC0C7CED5, 0xDCE3EAF1, 0xF8FF060D, 0x141B2229,
        0x30373E45, 0x4C535A61, 0x686F767D, 0x848B9299,
        0xA0A7AEB5, 0xBCC3CAD1, 0xD8DFE6ED, 0xF4FB0209,
        0x10171E25, 0x2C333A41, 0x484F565D, 0x646B7279
    ]

    public static func encryptCBC(plaintext: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == 16 else { throw SM4Error.invalidKeyLength }
        guard iv.count == 16 else { throw SM4Error.invalidIVLength }

        let rk = expandKey(key)
        let padded = pkcs7Pad(plaintext, blockSize: 16)
        var out = Data(capacity: padded.count)
        var prev = [UInt8](iv)

        let pBytes = [UInt8](padded)
        for offset in stride(from: 0, to: pBytes.count, by: 16) {
            var block = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 {
                block[i] = pBytes[offset + i] ^ prev[i]
            }
            let encrypted = cryptBlock(block, roundKeys: rk)
            out.append(contentsOf: encrypted)
            prev = encrypted
        }
        return out
    }

    public static func decryptCBC(ciphertext: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == 16 else { throw SM4Error.invalidKeyLength }
        guard iv.count == 16 else { throw SM4Error.invalidIVLength }
        guard !ciphertext.isEmpty && ciphertext.count % 16 == 0 else {
            throw SM4Error.invalidInputLength
        }

        let rk = Array(expandKey(key).reversed())
        var out = Data(capacity: ciphertext.count)
        var prev = [UInt8](iv)

        let cBytes = [UInt8](ciphertext)
        for offset in stride(from: 0, to: cBytes.count, by: 16) {
            let block = Array(cBytes[offset..<(offset + 16)])
            let decrypted = cryptBlock(block, roundKeys: rk)
            for i in 0..<16 {
                out.append(decrypted[i] ^ prev[i])
            }
            prev = block
        }
        return try pkcs7Unpad(out, blockSize: 16)
    }

    private static func expandKey(_ key: Data) -> [UInt32] {
        let kb = [UInt8](key)
        var k = [UInt32](repeating: 0, count: 36)
        for i in 0..<4 {
            k[i] = loadWord(kb, offset: i * 4) ^ fk[i]
        }
        var rk = [UInt32](repeating: 0, count: 32)
        for i in 0..<32 {
            let tmp = k[i + 1] ^ k[i + 2] ^ k[i + 3] ^ ck[i]
            rk[i] = k[i] ^ lPrime(tau(tmp))
            k[i + 4] = rk[i]
        }
        return rk
    }

    private static func cryptBlock(_ input: [UInt8], roundKeys rk: [UInt32]) -> [UInt8] {
        var x0 = loadWord(input, offset: 0)
        var x1 = loadWord(input, offset: 4)
        var x2 = loadWord(input, offset: 8)
        var x3 = loadWord(input, offset: 12)

        for i in 0..<32 {
            let next = x0 ^ l(tau(x1 ^ x2 ^ x3 ^ rk[i]))
            x0 = x1; x1 = x2; x2 = x3; x3 = next
        }

        var out = [UInt8](repeating: 0, count: 16)
        storeWord(x3, into: &out, offset: 0)
        storeWord(x2, into: &out, offset: 4)
        storeWord(x1, into: &out, offset: 8)
        storeWord(x0, into: &out, offset: 12)
        return out
    }

    @inline(__always)
    private static func tau(_ a: UInt32) -> UInt32 {
        (UInt32(sbox[Int((a >> 24) & 0xFF)]) << 24)
            | (UInt32(sbox[Int((a >> 16) & 0xFF)]) << 16)
            | (UInt32(sbox[Int((a >> 8) & 0xFF)]) << 8)
            | UInt32(sbox[Int(a & 0xFF)])
    }

    @inline(__always)
    private static func rotL(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }

    @inline(__always)
    private static func l(_ b: UInt32) -> UInt32 {
        b ^ rotL(b, 2) ^ rotL(b, 10) ^ rotL(b, 18) ^ rotL(b, 24)
    }

    @inline(__always)
    private static func lPrime(_ b: UInt32) -> UInt32 {
        b ^ rotL(b, 13) ^ rotL(b, 23)
    }

    @inline(__always)
    private static func loadWord(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    @inline(__always)
    private static func storeWord(_ w: UInt32, into out: inout [UInt8], offset: Int) {
        out[offset] = UInt8((w >> 24) & 0xFF)
        out[offset + 1] = UInt8((w >> 16) & 0xFF)
        out[offset + 2] = UInt8((w >> 8) & 0xFF)
        out[offset + 3] = UInt8(w & 0xFF)
    }

    private static func pkcs7Pad(_ data: Data, blockSize: Int) -> Data {
        let padLen = blockSize - (data.count % blockSize)
        var padded = data
        padded.append(contentsOf: repeatElement(UInt8(padLen), count: padLen))
        return padded
    }

    private static func pkcs7Unpad(_ data: Data, blockSize: Int) throws -> Data {
        guard let last = data.last else { throw SM4Error.invalidPadding }
        let padLen = Int(last)
        guard padLen >= 1 && padLen <= blockSize && padLen <= data.count else {
            throw SM4Error.invalidPadding
        }
        for i in (data.count - padLen)..<data.count {
            if data[i] != last { throw SM4Error.invalidPadding }
        }
        return data.prefix(data.count - padLen)
    }
}
