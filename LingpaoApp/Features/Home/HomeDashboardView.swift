import LingpaoCore
import SwiftUI
import UIKit

/// Tab 1「车况」总览页：左侧精炼车况列 + 右侧避让车外俯视图 + 下方快捷控车操作组（支持下拉震动静默刷新）
public struct HomeDashboardView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var isQuickEditorPresented: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let vehicle = viewModel.selectedVehicle
        let t = viewModel.telemetry

        VStack(alignment: .leading, spacing: 0) {
            // 固定顶部标题行（整行干净无右上按钮，刷新改为列表下拉静默更新并带触感反馈）
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HomeVehicleHeaderButton(viewModel: viewModel)

                    if let weather = viewModel.locationWeather {
                        Label(
                            "\(weather.cityName) \(weather.weatherText) \(weather.temperatureCelsius)°C",
                            systemImage: "location.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // 左列核心指标区（收窄至 176pt，让右侧车身与左侧胎压保持清晰间距）
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        // 主电量与续航卡
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(Int(t.displaySoc.rounded()))")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundStyle(palette.ink)
                                Text("%")
                                    .font(.headline)
                                    .foregroundStyle(palette.secondary)
                            }

                            ProgressView(value: t.displaySoc / 100.0)
                                .tint(t.isCharging ? palette.good : (t.displaySoc < 20 ? palette.warning : palette.good))

                            Label("纯电续航 \(Int(t.electricRangeKm.rounded())) km", systemImage: "bolt.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(palette.positiveText)

                            if vehicle?.isRangeExtender == true {
                                Label("综合续航 \(Int(t.combinedRangeKm.rounded())) km", systemImage: "fuelpump.fill")
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondary)
                            }
                        }
                        .lingpaoCard(padding: 14)

                        // 门锁与车舱简报卡
                        VStack(alignment: .leading, spacing: 8) {
                            StatusRowItem(
                                icon: t.isLocked ? "lock.fill" : "lock.open.fill",
                                text: t.isLocked ? "全车已闭锁" : "车辆未上锁",
                                color: t.isLocked ? palette.positiveText : palette.warning
                            )
                            StatusRowItem(
                                icon: t.hasOpenClosure ? "car.side.air.circulate" : "checkmark.shield.fill",
                                text: t.hasOpenClosure ? "存在未关闭车门" : "门窗与备箱闭合",
                                color: t.hasOpenClosure ? palette.warning : palette.secondary
                            )
                            if let temp = t.interiorTemp {
                                StatusRowItem(
                                    icon: "thermometer.medium",
                                    text: String(format: "车内 %.1f°C", temp),
                                    color: palette.secondary
                                )
                            }
                        }
                        .lingpaoCard(padding: 14)

                        // 进入充电专页胶囊按钮（点击直接平移缩放到 (218, 74, 0.68) 并显示左侧竖向 SOC 流光条）
                        Button {
                            withAnimation(.spring(duration: 0.4)) {
                                viewModel.isChargeSheetPresented = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: t.isCharging ? "bolt.circle.fill" : "ev.charger.fill")
                                Text(t.isCharging ? "充电中 · \(String(format: "%.1f", t.chargePowerKw)) kW" : "充电管理与预约")
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(palette.good))
                        }
                    }
                    .frame(maxWidth: 176)

                    Spacer(minLength: 140)
                }
                .padding(.top, 8)

                // 下方：快捷控车操作宫格（置于安全滚动区下段，不挡顶部车图）
                Spacer(minLength: 120)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("快捷控制")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.secondary)

                        Spacer()

                        Button {
                            isQuickEditorPresented = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "slider.horizontal.3")
                                Text("编辑")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.good)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(palette.good.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home_edit_quick_controls")
                    }

                    let actions = viewModel.layoutPreferences.homeQuickActions
                    BalancedActionGrid(items: actions, maxColumns: 4, spacing: 10) { action in
                        let spec = homeQuickSpec(for: action, telemetry: t)
                        QuickControlButton(
                            title: spec.title,
                            icon: spec.icon,
                            isActive: spec.isActive,
                            palette: palette
                        ) {
                            executeHomeQuickAction(action, telemetry: t)
                        }
                    }
                }
                .lingpaoCard(padding: 14)

                // 全车状态详情卡
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("累计总里程")
                            .font(.caption)
                            .foregroundStyle(palette.secondary)
                        Text(String(format: "%.0f km", t.totalMileageKm))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(palette.ink)
                    }
                    Spacer()
                    Divider().frame(height: 30)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("健康充电上限")
                            .font(.caption)
                            .foregroundStyle(palette.secondary)
                        Text("\(t.healthyChargeTargetSoc)%")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(palette.good)
                    }
                }
                .lingpaoCard(padding: 14)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            }
            .clipped()
            .refreshable {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if viewModel.isDemoMode {
                    try? await Task.sleep(nanoseconds: 550_000_000)
                } else {
                    await viewModel.refreshAllOnlineData(silent: true)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .sheet(isPresented: $isQuickEditorPresented) {
            HomeQuickControlEditorSheet(viewModel: viewModel)
        }
    }

    private func homeQuickSpec(for action: HomeQuickAction, telemetry: VehicleTelemetry) -> (title: String, icon: String, isActive: Bool) {
        switch action {
        case .lockToggle:
            return (telemetry.isLocked ? "解锁" : "闭锁", telemetry.isLocked ? "lock.open.fill" : "lock.fill", !telemetry.isLocked)
        case .climateToggle:
            return (telemetry.acOn ? "关空调" : "开空调", "fan.fill", telemetry.acOn)
        case .horn:
            return ("寻车", "horn.blast.fill", false)
        case .trunkToggle:
            return (telemetry.trunkOpen ? "关尾箱" : "开尾箱", "car.top.radiowaves.rear.right.fill", telemetry.trunkOpen)
        case .frunkToggle:
            return (telemetry.hoodOpen ? "关前备箱" : "开前备箱", "car.top.radiowaves.front.fill", telemetry.hoodOpen)
        case .windowVent:
            return ("车窗通风", "car.top.door.front.left.open", telemetry.hasOpenWindow)
        case .windowClose:
            return ("车窗全关", "window.ceiling.closed", false)
        case .sentryToggle:
            return (telemetry.sentryModeOn ? "关哨兵" : "开哨兵", "eye.circle.fill", telemetry.sentryModeOn)
        case .mirrorHeat:
            return (telemetry.rearMirrorHeatingOn ? "关镜热" : "后视镜热", "heat.waves", telemetry.rearMirrorHeatingOn)
        case .quickCool:
            return ("极速降温", "snowflake", false)
        case .quickHeat:
            return ("极速升温", "flame.fill", false)
        case .deodorize:
            return ("快速除味", "wind", false)
        }
    }

    private func executeHomeQuickAction(_ action: HomeQuickAction, telemetry: VehicleTelemetry) {
        switch action {
        case .lockToggle:
            viewModel.executeControl(telemetry.isLocked ? .unlock : .lock)
        case .climateToggle:
            viewModel.executeControl(telemetry.acOn ? .acOff : .acOn)
        case .horn:
            viewModel.executeControl(.horn)
        case .trunkToggle:
            viewModel.executeControl(.trunk(open: !telemetry.trunkOpen))
        case .frunkToggle:
            viewModel.executeControl(.frunk(open: !telemetry.hoodOpen))
        case .windowVent:
            viewModel.executeControl(.window(percentCode: "2"))
        case .windowClose:
            viewModel.executeControl(.window(percentCode: "0"))
        case .sentryToggle:
            viewModel.executeControl(.sentryMode(on: !telemetry.sentryModeOn))
        case .mirrorHeat:
            viewModel.executeControl(.mirrorHeating(on: !telemetry.rearMirrorHeatingOn))
        case .quickCool:
            viewModel.executeControl(.quickCool)
        case .quickHeat:
            viewModel.executeControl(.quickHeat)
        case .deodorize:
            viewModel.executeControl(.deodorize)
        }
    }
}

private struct StatusRowItem: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

private struct QuickControlButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let palette: LingpaoPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(isActive ? .white : palette.ink)
                    .background(
                        Circle()
                            .fill(isActive ? palette.good : palette.background)
                    )

                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isActive ? palette.good : palette.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
