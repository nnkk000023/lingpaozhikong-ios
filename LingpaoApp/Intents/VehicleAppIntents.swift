import AppIntents
import Foundation
import LingpaoCore

/// 后台静默控车共享执行器（供 Siri 语音、iOS 17 Interactive Widget 与 iPhone Action Button 共用）
enum IntentVehicleExecutor {
    static func execute(_ command: ControlCommand) async -> String {
        let store = KeychainStore.shared
        let session = store.loadSession()
        let payload = (try? command.buildPayload())
        let summary = payload?.summary ?? "控车操作"

        guard session.isLoggedIn else {
            if var snap = SharedSnapshotStore.load() {
                switch command {
                case .lock: snap.isLocked = true
                case .unlock: snap.isLocked = false
                case .acOn: snap.acOn = true
                case .acOff: snap.acOn = false
                default: break
                }
                snap.lastActionMessage = "\(summary)（演示缓存）"
                snap.updatedAt = Date()
                SharedSnapshotStore.save(snap)
            }
            return "未登录正式账号，已在小组件缓存演示执行「\(summary)」"
        }

        let opPwd = store.loadOpPassword()
        guard !opPwd.isEmpty else {
            return "请先在 App「我的」页面保存 4 位操控密码"
        }

        let client = LeapAPIClient(store: store)
        do {
            _ = try await client.sendRemoteControl(command: command, opPassword: opPwd)
            if var snap = SharedSnapshotStore.load() {
                switch command {
                case .lock: snap.isLocked = true
                case .unlock: snap.isLocked = false
                case .acOn: snap.acOn = true
                case .acOff: snap.acOn = false
                default: break
                }
                snap.lastActionMessage = summary
                snap.updatedAt = Date()
                SharedSnapshotStore.save(snap)
            }
            return "零跑已执行：\(summary)"
        } catch {
            return "\(summary)失败：\(error.localizedDescription)"
        }
    }

    static func refreshTelemetrySnapshot() async -> String {
        let store = KeychainStore.shared
        let session = store.loadSession()
        guard session.isLoggedIn else {
            return "当前为演示/未登录状态"
        }
        let client = LeapAPIClient(store: store)
        do {
            let t = try await client.fetchTelemetry(vin: session.selectedVin)
            let snap = SharedVehicleSnapshot(
                vin: session.selectedVin,
                vehicleName: session.selectedNickname,
                carType: session.selectedCarType,
                paintId: session.selectedPaintId,
                soc: t.displaySoc,
                rangeKm: t.electricRangeKm,
                isLocked: t.isLocked,
                acOn: t.acOn,
                interiorTemp: t.interiorTemp,
                isCharging: t.isCharging,
                chargePowerKw: t.chargePowerKw,
                chargeRemainMinutes: t.chargeRemainTimeMinutes,
                updatedAt: Date(),
                lastActionMessage: "车况已同步"
            )
            SharedSnapshotStore.save(snap)
            return "已同步最新车况：电量 \(Int(t.displaySoc.rounded()))%，续航 \(Int(t.electricRangeKm.rounded())) km"
        } catch {
            return "刷新车况失败：\(error.localizedDescription)"
        }
    }
}

/// 一键锁车 AppIntent（Widget 交互按钮 & Siri & Action Button）
public struct LockVehicleIntent: AppIntent {
    public static var title: LocalizedStringResource = "锁车"
    public static var description = IntentDescription("远程闭锁零跑汽车车门")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = await IntentVehicleExecutor.execute(.lock)
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

/// 一键解锁 AppIntent
public struct UnlockVehicleIntent: AppIntent {
    public static var title: LocalizedStringResource = "解锁车辆"
    public static var description = IntentDescription("远程解锁零跑汽车车门")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = await IntentVehicleExecutor.execute(.unlock)
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

/// 切换空调开关 AppIntent
public struct ToggleClimateIntent: AppIntent {
    public static var title: LocalizedStringResource = "切换空调"
    public static var description = IntentDescription("开启或关闭零跑汽车空调")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let isCurrentlyOn = SharedSnapshotStore.load()?.acOn ?? false
        let msg = await IntentVehicleExecutor.execute(isCurrentlyOn ? .acOff : .acOn)
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

/// 鸣笛寻车 AppIntent
public struct FindCarIntent: AppIntent {
    public static var title: LocalizedStringResource = "鸣笛寻车"
    public static var description = IntentDescription("触发零跑汽车鸣笛与双闪寻车")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = await IntentVehicleExecutor.execute(.horn)
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

/// 刷新小组件车况 AppIntent
public struct RefreshTelemetryIntent: AppIntent {
    public static var title: LocalizedStringResource = "同步车况"
    public static var description = IntentDescription("从零跑云端获取最新电量和车门锁状态")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = await IntentVehicleExecutor.execute(.vehicleWake)
        let syncMsg = await IntentVehicleExecutor.refreshTelemetrySnapshot()
        return .result(dialog: IntentDialog(stringLiteral: "\(msg)；\(syncMsg)"))
    }
}

/// Siri 捷径快捷短语自动注册
public struct LingpaoShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LockVehicleIntent(),
            phrases: [
                "锁上我的\(.applicationName)",
                "用\(.applicationName)锁车"
            ],
            shortTitle: "零跑锁车",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: ToggleClimateIntent(),
            phrases: [
                "打开或关闭\(.applicationName)空调",
                "用\(.applicationName)开空调"
            ],
            shortTitle: "切换空调",
            systemImageName: "fan.fill"
        )
        AppShortcut(
            intent: FindCarIntent(),
            phrases: [
                "用\(.applicationName)寻车",
                "\(.applicationName)鸣笛寻车"
            ],
            shortTitle: "鸣笛寻车",
            systemImageName: "horn.blast.fill"
        )
    }
}
