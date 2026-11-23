import LingpaoCore
import SwiftUI

/// 蓝牙数字钥匙配置、证书同步与近场秒控弹窗
public struct BleKeyControlSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var passiveConfig: BLEPassiveConfiguration = KeychainStore.shared.loadPassiveConfig()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let ble = viewModel.bleManager
        let vin = viewModel.selectedVehicle?.vin ?? viewModel.session.selectedVin
        let accountId = viewModel.session.oldSession?.accountId ?? ""
        let cert = (!vin.isEmpty && !accountId.isEmpty) ? KeychainStore.shared.loadBleCertificate(accountId: accountId, vin: vin) : nil

        NavigationStack {
            List {
                Section("证书与加密套件") {
                    if let cert {
                        LabeledContent("VIN", value: cert.vin)
                        LabeledContent("加密体系", value: cert.keyType.displayName)
                        LabeledContent("快速重连凭证", value: ble.hasReconnectCredential ? "已缓存 (0xAAEE)" : "待认证生成")
                    } else {
                        Text("本地尚未同步蓝牙证书")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await viewModel.syncAndPrepareBleKey() }
                    } label: {
                        Label("从零跑云端同步数字钥匙证书", systemImage: "icloud.and.arrow.down.fill")
                            .foregroundStyle(palette.good)
                    }
                    .disabled(viewModel.isBusy || viewModel.isDemoMode)
                }

                Section("近场连接（CoreBluetooth FFFE / FFF2）") {
                    LabeledContent("连接阶段", value: ble.stage.rawValue)
                    if let rssi = ble.currentRSSI {
                        LabeledContent("信号强度 (RSSI)", value: "\(rssi) dBm")
                    }
                    LabeledContent("协议次版本", value: "v\(ble.protocolMinor)")
                    Text(ble.statusLog)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if ble.stage == .ready {
                        HStack(spacing: 12) {
                            Button("蓝牙解锁") { ble.sendLockCommand(isLock: false) }
                                .buttonStyle(.borderedProminent)
                                .tint(palette.good)

                            Button("蓝牙锁车") { ble.sendLockCommand(isLock: true) }
                                .buttonStyle(.bordered)
                        }
                        Button("读取 RSSI", action: { ble.refreshRSSI() })
                        Button("断开连接", role: .destructive, action: { ble.disconnect() })
                    } else {
                        Button("扫描周围零跑车辆蓝牙") {
                            ble.startScanning()
                        }
                    }

                    ForEach(ble.discoveredPeripherals) { item in
                        Button {
                            ble.connect(peripheralID: item.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name).font(.subheadline.weight(.semibold))
                                    Text("Minor v\(item.protocolMinor) · UUID \(item.id.uuidString.prefix(8))...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(item.rssi) dBm")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                }

                Section("无感解闭锁参数标定") {
                    Toggle("启用无感钥匙总开关", isOn: $passiveConfig.enabled)
                    Toggle("靠近自动解锁", isOn: $passiveConfig.autoUnlock)
                    Toggle("离车自动闭锁", isOn: $passiveConfig.autoLock)
                    Toggle("微动按键启用（需 Minor >= 9）", isOn: $passiveConfig.buttonEnabled)
                    Button("保存本地标定配置") {
                        KeychainStore.shared.savePassiveConfig(passiveConfig)
                        viewModel.prepareBleFromCache()
                        viewModel.showToast("蓝牙标定参数已保存")
                    }
                }
            }
            .navigationTitle("蓝牙数字钥匙")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
