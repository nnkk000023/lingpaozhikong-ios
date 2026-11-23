import Foundation
import LingpaoCore

#if canImport(SmAntiFraud)
import SmAntiFraud
#endif

/// 数美设备安全标识提供器（兼容官方 iOS `SmAntiFraud.xcframework` 原生直连与手动/Raw Auth 凭据兜底）
public enum ShumeiDeviceProvider {
    /// 从原包 `G30.java` 实证还原的数美接入参数
    public static let organization = "mRCScLRggvJAYnjU7WgS"
    public static let appId = "default"
    public static let publicKey =
        "MIIDLzCCAhegAwIBAgIBMDANBgkqhkiG9w0BAQUFADAyMQswCQYDVQQGEwJDTjELMAkGA1UECwwCU00xFjAUBgNVBAMMDWUuaXNodW1laS5jb20wHhcNMjMwMzEzMDcwMDM4WhcNNDMwMzA4MDcwMDM4WjAyMQswCQYDVQQGEwJDTjELMAkGA1UECwwCU00xFjAUBgNVBAMMDWUuaXNodW1laS5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCeaT5VtCQdHxs8vJYrn5v+gcIuHHK46wVD+EmHJoQyfG0po4/TJiqLNTMkmXRkSpnNXQkI1ISa8WJEdx98bEeh+k0PejTeMnMnh/N3pl0RoQwUJdSZ2JGYv7wI2G0T2yaltVLE9SfuJ94CS2jS1sMqR5TZNgDncGdNnTWmU+JBjyHvw4WDukIE+ut6XTmXOFuc2M/sUENGpAmDKydIba8eE+UqczskLeHHZEK3OIBb/rXRceA2Ev0OS3E8+440XNj1rSEM6GDowJstX0g4AHVlXyfIX9Q5CUt8ou2yLM/sV2DoyOZhlO8VOVlROyoEPSJ2zB4PXT5Wh59REeU6fOjXAgMBAAGjUDBOMB0GA1UdDgQWBBRPX/BD6jvfsAAvNtuIQG3MJEAb+jAfBgNVHSMEGDAWgBRPX/BD6jvfsAAvNtuIQG3MJEAb+jAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBBQUAA4IBAQAan9/tQSgVH4ecCzqK+0t96mkNt/w14k3QFD0ix5UehTrk3d4v2fJ9Vf4RzWe2MsM6VfXIgRJwNi1msYiz+Z1flsDaVuw0RZGaAbPKkidbsd6nL8EQfL/VANi7P31G6u1/Nk3E8bfAAnFesYogVK0/T/WlXhJo1P9/HXRaKPydoS0u8uNPR4RN0aPeKglOYlzykcmCFDowNsMmq4ktYOtyuyTNQm2HkHYPREbkxr5nnvQwrzlvARnqH9Fu/4ZIQxMSZtQnCVLmQ3FO0eICDw/jAXrCnWAgtgc9kNNonaEnXItp/KQliEPlMvOTNyklffwKQwiCDC5OXTIVBQj5prsR"

    public static var hasNativeSDK: Bool {
        #if canImport(SmAntiFraud)
        return true
        #else
        return false
        #endif
    }

    /// 异步读取有效 `smDeviceId`（优先原生 SDK，其次读取已配置/导入缓存）
    public static func resolveDeviceId(manualOverride: String?, stored: String) async -> String? {
        if let manual = manualOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !manual.isEmpty {
            return manual
        }
        if !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        #if canImport(SmAntiFraud)
        return await withCheckedContinuation { continuation in
            let option = SmOption()
            option.organization = organization
            option.appId = appId
            option.publicKey = publicKey
            option.usingHttps = true
            option.notCollect = ["wifiip", "bssid", "ssid", "oaid", "locationCls"]
            SmAntiFraud.shareInstance().create(option)
            SmAntiFraud.shareInstance().getDeviceId { smId in
                continuation.resume(returning: smId)
            }
        }
        #else
        return nil
        #endif
    }
}
