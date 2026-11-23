import LingpaoCore
import SwiftUI

/// 充电专页：配合 `CarPose.charge` (218, 74, 0.68) 与左侧呼吸 SOC 竖向条展示完整充放电、健康充电上限与预约谷电管理
public struct ChargeDetailView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var healthySoc: Double = 90
    @State private var healthyEnabled: Bool = true
    @State private var scheduleEnabled: Bool = false
    @State private var startTime = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var continueFull: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let t = viewModel.telemetry

        VStack(spacing: 14) {
            // 顶部导航返回条（二级页面仅保留返回按钮，界面干净不显示额外车名与切换）
            HStack {
                Button {
                    withAnimation(.spring(duration: 0.4)) {
                        viewModel.isChargeSheetPresented = false
                    }
                } label: {
                    Label("返回车况", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(palette.card))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // 左侧充电指标卡 + 车模完整留白展示区（高度锁定 >= 335pt，确保下半部按钮绝不遮挡车尾与光条）
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t.isCharging ? "正在快速充电" : "充电待机")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(t.isCharging ? palette.good : palette.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(Int(t.displaySoc.rounded()))")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.ink)
                            Text("%")
                                .font(.headline)
                                .foregroundStyle(palette.secondary)
                        }

                        Text("功率：\(String(format: "%.1f kW", t.chargePowerKw))")
                            .font(.caption)
                            .foregroundStyle(palette.secondary)

                        Text(t.isCharging ? "预计剩余：\(t.chargeRemainTimeMinutes) 分钟" : "续航：\(Int(t.electricRangeKm.rounded())) km")
                            .font(.caption)
                            .foregroundStyle(palette.secondary)

                        if let battTemp = t.currentBatteryTemp {
                            Text("当前电池温度：\(String(format: "%.0f°C", battTemp))")
                                .font(.caption2)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .frame(maxWidth: 174, alignment: .leading)
                    .lingpaoCard(padding: 14)

                    Spacer()
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 96)
            }
            .frame(height: 330, alignment: .top)

            // 底部控制滚动区（裁切避免向上滑动侵入车模与状态栏）
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // 1. 立即充停 & 解锁充电枪
                    HStack(spacing: 10) {
                        Button {
                            viewModel.executeControl(t.isCharging ? .stopCharging : .startCharging)
                        } label: {
                            Label(t.isCharging ? "停止充电" : "开始充电", systemImage: t.isCharging ? "stop.circle.fill" : "bolt.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.isCharging ? palette.danger : palette.good))
                        }

                        Button {
                            viewModel.executeControl(.unlockCharger)
                        } label: {
                            Label("解锁充电枪", systemImage: "lock.open.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(palette.ink)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card))
                        }
                    }

                    // 2. 健康充电上限滑块（开启时上限最高 90%，关闭后最高 100%）
                    let maxHealthyLimit: Double = healthyEnabled ? 90 : 100
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("健康充电限值")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.ink)
                            Spacer()
                            Toggle("", isOn: $healthyEnabled)
                                .labelsHidden()
                                .onChange(of: healthyEnabled) { _, isOn in
                                    if isOn && healthySoc > 90 {
                                        healthySoc = 90
                                    }
                                }
                        }

                        HStack {
                            Text("限值 \(Int(min(healthySoc, maxHealthyLimit)))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.good)
                                .frame(minWidth: 56, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { min(healthySoc, maxHealthyLimit) },
                                    set: { healthySoc = $0 }
                                ),
                                in: 50...maxHealthyLimit,
                                step: 5
                            )
                            .tint(palette.good)
                            Button("保存") {
                                let targetInt = Int(min(healthySoc, maxHealthyLimit))
                                healthySoc = Double(targetInt)
                                Task {
                                    if viewModel.isDemoMode {
                                        viewModel.telemetry.healthyChargeTargetSoc = targetInt
                                        viewModel.telemetry.healthyChargeEnabled = healthyEnabled
                                        viewModel.showToast("健康充电上限已设为 \(targetInt)%（演示）")
                                    } else {
                                        do {
                                            try await viewModel.apiClient.setHealthyCharging(enabled: healthyEnabled, targetSoc: targetInt)
                                            viewModel.telemetry.healthyChargeTargetSoc = targetInt
                                            viewModel.telemetry.healthyChargeEnabled = healthyEnabled
                                            viewModel.showToast("健康充电设置成功")
                                        } catch {
                                            viewModel.showToast("设置失败：\(error.localizedDescription)")
                                        }
                                    }
                                }
                            }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(palette.background))
                        }

                        if healthyEnabled {
                            Text("开启健康充电时上限最高 90%，有助于延缓电池老化")
                                .font(.caption2)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .lingpaoCard(padding: 14)

                    // 3. 预约谷电充电
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("预约谷电充电")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.ink)
                            Spacer()
                            Toggle("", isOn: $scheduleEnabled).labelsHidden()
                        }
                        HStack {
                            DatePicker("开始", selection: $startTime, displayedComponents: .hourAndMinute)
                            DatePicker("结束", selection: $endTime, displayedComponents: .hourAndMinute)
                        }
                        Toggle("谷电时段外继续充满", isOn: $continueFull)
                            .font(.caption)

                        Button("下发预约充电设置") {
                            let df = DateFormatter()
                            df.dateFormat = "HH:mm"
                            let s = df.string(from: startTime)
                            let e = df.string(from: endTime)
                            if viewModel.isDemoMode {
                                viewModel.telemetry.chargeScheduleEnabled = scheduleEnabled
                                viewModel.telemetry.chargeScheduleStart = s
                                viewModel.telemetry.chargeScheduleEnd = e
                                viewModel.showToast("已保存预约充电 \(s)-\(e)（演示）")
                            } else {
                                Task {
                                    do {
                                        try await viewModel.apiClient.setChargeSchedule(
                                            enabled: scheduleEnabled,
                                            startTime: s,
                                            endTime: e,
                                            targetSoc: Int(healthySoc),
                                            opPassword: KeychainStore.shared.loadOpPassword(),
                                            recharge: continueFull
                                        )
                                        viewModel.showToast("预约充电下发成功")
                                    } catch {
                                        viewModel.showToast("下发失败：\(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.good))
                    }
                    .lingpaoCard(padding: 14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .clipped()
        }
        .onAppear {
            healthyEnabled = t.healthyChargeEnabled
            healthySoc = min(Double(t.healthyChargeTargetSoc), t.healthyChargeEnabled ? 90 : 100)
            scheduleEnabled = t.chargeScheduleEnabled
        }
    }
}
