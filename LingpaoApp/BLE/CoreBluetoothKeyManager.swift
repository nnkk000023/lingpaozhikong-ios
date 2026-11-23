import CoreBluetooth
import Foundation
import LingpaoCore
import Observation

/// BLE 外设扫描候选项
public struct DiscoveredBLEPeripheral: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public var rssi: Int
    public let protocolMinor: Int
}

/// BLE 蓝牙连接状态机
public enum BLEConnectionStage: String {
    case idle = "未连接"
    case scanning = "正在扫描车辆蓝牙..."
    case connecting = "正在连接并协商 MTU..."
    case authenticating = "正在进行 ECDH/AES 握手..."
    case ready = "蓝牙钥匙已就绪（近场秒控）"
    case disconnected = "已断开"
    case error = "连接异常"
}

/// 基于 `CoreBluetooth`（支持后台状态恢复 `CBCentralManagerOptionRestoreIdentifierKey`）的零跑 BLE 数字钥匙控制器
@MainActor
@Observable
public final class CoreBluetoothKeyManager: NSObject {
    public private(set) var bluetoothState: CBManagerState = .unknown
    public private(set) var stage: BLEConnectionStage = .idle
    public private(set) var discoveredPeripherals: [DiscoveredBLEPeripheral] = []
    public private(set) var connectedPeripheralName: String = ""
    public private(set) var currentRSSI: Int?
    public private(set) var protocolMinor: Int = BLEConstants.defaultProtocolMinor
    public private(set) var statusLog: String = "尚未连接车辆蓝牙"
    public private(set) var hasReconnectCredential: Bool = false

    private var centralManager: CBCentralManager!
    private var peripheralMap: [UUID: CBPeripheral] = [:]
    private var activePeripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?

    private var activeCertificate: BleKeyCertificate?
    private var activeAccountId: String = ""
    private var activeDeviceId: String = ""
    private var activeConfig: BLEPassiveConfiguration = BLEPassiveConfiguration()
    private var sessionCrypto: BLESessionCrypto?
    private let frameBuffer = BLEFrameBuffer()

    /// 待发送队列与外部动作确认回调
    public var onDoorActionConfirmed: ((Bool) -> Void)?

    private static let serviceCBUUID = CBUUID(string: BLEConstants.serviceUUIDString)
    private static let characteristicCBUUID = CBUUID(string: BLEConstants.characteristicUUIDString)
    private static let restoreIdentifier = "com.lingpao.personal.ble.central"

    public override init() {
        super.init()
        self.centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }

    /// 配置当前车辆凭证后准备扫描或重连
    public func configure(
        certificate: BleKeyCertificate?,
        accountId: String,
        deviceId: String,
        passiveConfig: BLEPassiveConfiguration
    ) {
        self.activeCertificate = certificate
        self.activeAccountId = accountId
        self.activeDeviceId = deviceId
        self.activeConfig = passiveConfig
        if let cert = certificate {
            let storedCred = KeychainStore.shared.loadReconnectCredential(accountId: accountId, vin: cert.vin)
            self.hasReconnectCredential = (storedCred != nil && !storedCred!.isEmpty)
        } else {
            self.hasReconnectCredential = false
        }
    }

    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            stage = .error
            statusLog = "请先打开 iPhone 蓝牙开关"
            return
        }
        discoveredPeripherals.removeAll()
        stage = .scanning
        statusLog = "正在搜索 FFFE 零跑蓝牙钥匙广播..."

        // 优先尝试通过已绑定 UUID 快速检索重连
        if let vin = activeCertificate?.vin,
           let savedUUID = KeychainStore.shared.loadBoundPeripheralUUID(vin: vin),
           let known = centralManager.retrievePeripherals(withIdentifiers: [savedUUID]).first {
            peripheralMap[savedUUID] = known
            statusLog = "发现上次绑定的车辆蓝牙，正在尝试重连..."
            connect(to: known)
            return
        }

        centralManager.scanForPeripherals(
            withServices: [Self.serviceCBUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func stopScanning() {
        centralManager.stopScan()
        if stage == .scanning {
            stage = .idle
        }
    }

    public func connect(peripheralID: UUID) {
        guard let peripheral = peripheralMap[peripheralID] else { return }
        connect(to: peripheral)
    }

    private func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan()
        activePeripheral = peripheral
        peripheral.delegate = self
        stage = .connecting
        connectedPeripheralName = peripheral.name ?? "零跑车载蓝牙"
        statusLog = "正在建立 GATT 连接..."
        centralManager.connect(peripheral, options: nil)
    }

    public func disconnect() {
        if let p = activePeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        activePeripheral = nil
        controlCharacteristic = nil
        sessionCrypto = nil
        frameBuffer.reset()
        stage = .disconnected
        statusLog = "蓝牙连接已断开"
    }

    /// 通过近场 BLE 通道发送解锁 / 闭锁指令（`cmd = 0 / 1`）
    public func sendLockCommand(isLock: Bool) {
        guard stage == .ready,
              let crypto = sessionCrypto,
              let peripheral = activePeripheral,
              let char = controlCharacteristic else {
            statusLog = "蓝牙会话尚未认证完成，无法发送指令"
            return
        }
        do {
            let cmd: BLECommandCode = isLock ? .lock : .unlock
            let frame = try BLEFrameCodec.encodeCommandFrame(crypto: crypto, command: cmd)
            writeChunkedFrame(frame, to: peripheral, characteristic: char)
            statusLog = isLock ? "已通过蓝牙发送上锁指令" : "已通过蓝牙发送解锁指令"
        } catch {
            stage = .error
            statusLog = "蓝牙指令加密失败：\(error.localizedDescription)"
        }
    }

    /// 读取实时 RSSI 距离指标
    public func refreshRSSI() {
        activePeripheral?.readRSSI()
    }

    // MARK: - 握手与分片发送逻辑

    private func startHandshake(useReconnectIfAvailable: Bool) {
        guard let cert = activeCertificate,
              let peripheral = activePeripheral,
              let char = controlCharacteristic else {
            stage = .error
            statusLog = "缺少云端蓝牙证书，请先在「蓝牙钥匙」同步证书"
            return
        }

        do {
            let crypto = try BLESessionCrypto.establish(certificate: cert)
            self.sessionCrypto = crypto
            self.frameBuffer.reset()
            stage = .authenticating

            let vin = cert.vin
            if useReconnectIfAvailable,
               let credHex = KeychainStore.shared.loadReconnectCredential(accountId: activeAccountId, vin: vin),
               !credHex.isEmpty {
                let recFrame = try BLEFrameCodec.encodeReconnectFrame(
                    crypto: crypto,
                    credentialHex: credHex,
                    accountId: activeAccountId,
                    configuration: activeConfig,
                    buttonCap: activeConfig.buttonEnabled && protocolMinor >= 9
                )
                writeChunkedFrame(recFrame, to: peripheral, characteristic: char)
                statusLog = "已发送快速重连帧（0xAAEE）..."
            } else {
                let authFrame = try BLEFrameCodec.encodeAuthFrame(
                    crypto: crypto,
                    certificate: cert,
                    accountId: activeAccountId,
                    deviceId: activeDeviceId,
                    configuration: activeConfig,
                    protocolMinor: protocolMinor,
                    buttonCap: activeConfig.buttonEnabled && protocolMinor >= 9
                )
                writeChunkedFrame(authFrame, to: peripheral, characteristic: char)
                statusLog = "已发送完整 ECDH 认证握手帧（0xAAAE）..."
            }
        } catch {
            stage = .error
            statusLog = "握手异常：\(error.localizedDescription)"
        }
    }

    private func writeChunkedFrame(_ frame: Data, to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let supportsWithResponse = characteristic.properties.contains(.write)
        let writeType: CBCharacteristicWriteType = supportsWithResponse ? .withResponse : .withoutResponse
        let maxChunk = min(max(peripheral.maximumWriteValueLength(for: writeType), 20), 160)

        var offset = 0
        while offset < frame.count {
            let end = min(offset + maxChunk, frame.count)
            let chunk = frame.subdata(in: offset..<end)
            peripheral.writeValue(chunk, for: characteristic, type: writeType)
            offset = end
        }
    }

    private func handleIncomingNotification(_ data: Data) {
        guard let crypto = sessionCrypto else { return }
        do {
            let rawFrames = try frameBuffer.appendAndExtract(data)
            for frame in rawFrames {
                let event = try BLEFrameBuffer.decodeEvent(from: frame, crypto: crypto)
                switch event {
                case .authenticatedConfirm:
                    stage = .ready
                    statusLog = "BLE 身份认证通过，近场控制已就绪"
                    if let vin = activeCertificate?.vin {
                        KeychainStore.shared.saveBoundPeripheralUUID(activePeripheral?.identifier, vin: vin)
                    }
                    // 认证后下发被动配置同步 cmd = 3
                    if let p = activePeripheral, let c = controlCharacteristic {
                        let cfgPayload = Data(activeConfig.wirePayload9Bytes(buttonCap: activeConfig.buttonEnabled && protocolMinor >= 9))
                        if let cfgFrame = try? BLEFrameCodec.encodeCommandFrame(crypto: crypto, command: .syncPassiveConfig, payload: cfgPayload) {
                            writeChunkedFrame(cfgFrame, to: p, characteristic: c)
                        }
                    }

                case .reconnectCredential(let credHex):
                    if let vin = activeCertificate?.vin, !credHex.isEmpty {
                        KeychainStore.shared.saveReconnectCredential(credHex, accountId: activeAccountId, vin: vin)
                        hasReconnectCredential = true
                        statusLog = "已缓存快速重连凭证"
                    }

                case .keyConfigResponse:
                    statusLog = "无感配置参数已同步至车端"

                case .doorActionConfirm(let triggerSource, let action):
                    let isLock = (action == 1)
                    statusLog = isLock ? "车端确认：车门已上锁（source=\(triggerSource)）" : "车端确认：车门已解锁（source=\(triggerSource)）"
                    onDoorActionConfirmed?(isLock)

                case .errorCode(let errCode):
                    // 3, 4, 7 表示快速重连凭证失效，自动清除并回退完整认证
                    if [3, 4, 7].contains(errCode) {
                        if let vin = activeCertificate?.vin {
                            KeychainStore.shared.saveReconnectCredential(nil, accountId: activeAccountId, vin: vin)
                            hasReconnectCredential = false
                        }
                        statusLog = "快速重连失效（err=\(errCode)），自动回退完整认证..."
                        startHandshake(useReconnectIfAvailable: false)
                    } else if errCode == 18 {
                        statusLog = "车辆暂未接受认证（err=18），重置后重试..."
                        startHandshake(useReconnectIfAvailable: false)
                    } else {
                        stage = .error
                        statusLog = "车端返回蓝牙拒绝码：\(errCode)"
                    }

                case .unknownEncrypted(let parts):
                    statusLog = "收到其他加密回执：\(parts.joined(separator: ";"))"
                }
            }
        } catch {
            statusLog = "蓝牙帧解析异常：\(error.localizedDescription)"
        }
    }
}

// MARK: - CBCentralManagerDelegate & CBPeripheralDelegate

extension CoreBluetoothKeyManager: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            self.bluetoothState = state
            if state != .poweredOn && self.stage == .scanning {
                self.stage = .error
                self.statusLog = "蓝牙未就绪"
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let first = peripherals.first {
            Task { @MainActor in
                self.activePeripheral = first
                first.delegate = self
                self.connectedPeripheralName = first.name ?? "零跑车载蓝牙（恢复）"
                self.statusLog = "已从系统状态恢复蓝牙连接"
            }
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let uuidStrings = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let minor = BLEConstants.extractProtocolMinor(from: uuidStrings) ?? BLEConstants.defaultProtocolMinor
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "零跑车辆"
        let item = DiscoveredBLEPeripheral(id: peripheral.identifier, name: name, rssi: RSSI.intValue, protocolMinor: minor)

        Task { @MainActor in
            self.peripheralMap[peripheral.identifier] = peripheral
            self.protocolMinor = minor
            if let idx = self.discoveredPeripherals.firstIndex(where: { $0.id == item.id }) {
                self.discoveredPeripherals[idx] = item
            } else {
                self.discoveredPeripherals.append(item)
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.stage = .connecting
            self.statusLog = "已连接，正在发现服务 FFFE..."
            peripheral.discoverServices([Self.serviceCBUUID])
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.stage = .disconnected
            self.controlCharacteristic = nil
            self.sessionCrypto = nil
            self.statusLog = error != nil ? "连接中断：\(error!.localizedDescription)" : "蓝牙连接已断开"
        }
    }
}

extension CoreBluetoothKeyManager: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.serviceCBUUID }) else {
                self.stage = .error
                self.statusLog = "未发现 FFFE 主服务"
                return
            }
            peripheral.discoverCharacteristics([Self.characteristicCBUUID], for: service)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard error == nil, let char = service.characteristics?.first(where: { $0.uuid == Self.characteristicCBUUID }) else {
                self.stage = .error
                self.statusLog = "未发现 FFF2 读写特征值"
                return
            }
            self.controlCharacteristic = char
            peripheral.setNotifyValue(true, for: char)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard error == nil, characteristic.isNotifying else {
                self.stage = .error
                self.statusLog = "开启 FFF2 通知订阅失败"
                return
            }
            self.startHandshake(useReconnectIfAvailable: true)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        Task { @MainActor in
            self.handleIncomingNotification(value)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            self.currentRSSI = RSSI.intValue
        }
    }
}
