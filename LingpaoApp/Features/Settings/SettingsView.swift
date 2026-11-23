import LingpaoCore
import SwiftUI

/// Tab 4「我的」页：多车切换、33 色官方车漆 GPU 实时换色、座椅布局、操控 PIN 与高德 Key 管理
public struct SettingsView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var editPin: String = ""
    @State private var editAmapKey: String = ""

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let profile = CarModelCatalog.profile(for: viewModel.selectedVehicle?.carType ?? viewModel.session.selectedCarType)
        let paints = PaintCatalog.availablePaints(for: profile.displayName)
        let selectedPaint = PaintCatalog.resolvePaint(id: viewModel.session.selectedPaintId, carTypeOrId: profile.displayName)

        VStack(alignment: .leading, spacing: 0) {
            // 固定页面顶部标题，防止深色模式卡片滚动侵入状态栏与灵动岛
            Text("我的与车辆设置")
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                // 1. 统一风格的「我的车辆」核心卡片与横向多车切换带
                myVehiclesCard(palette: palette, profile: profile, selectedPaint: selectedPaint)

                // 2. 官方车漆实时 GPU Metal 换色器
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("官方车漆换色（Metal 实时着染）")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Text(selectedPaint.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.good)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                        ForEach(paints) { paint in
                            let isChosen = paint.id == selectedPaint.id
                            Button {
                                viewModel.updatePaint(id: paint.id)
                            } label: {
                                VStack(spacing: 5) {
                                    Circle()
                                        .fill(Color(argb: paint.argb))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Circle().stroke(isChosen ? palette.good : palette.line, lineWidth: isChosen ? 2.5 : 1)
                                        )
                                    Text(paint.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(isChosen ? palette.good : palette.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .lingpaoCard(padding: 14)

                // 3. 蓝牙数字钥匙入口
                Button {
                    viewModel.prepareBleFromCache()
                    viewModel.isBleSheetPresented = true
                } label: {
                    HStack {
                        Label("蓝牙数字钥匙管理与标定", systemImage: "wave.3.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Text(viewModel.bleManager.stage.rawValue)
                            .font(.caption)
                            .foregroundStyle(viewModel.bleManager.stage == .ready ? palette.good : palette.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(palette.inactive)
                    }
                    .lingpaoCard(padding: 14)
                }
                .buttonStyle(.plain)

                // 4. 安全与接口配置（4 位控车 PIN、高德 Key、外观）
                VStack(alignment: .leading, spacing: 12) {
                    Text("安全与外观偏好")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.ink)

                    HStack {
                        SecureField("4-8 位远程操控密码（PIN）", text: $editPin)
                            .keyboardType(.numberPad)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(palette.background))
                        Button("保存 PIN") {
                            viewModel.saveControlPin(editPin)
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 10).fill(palette.good))
                    }

                    HStack {
                        TextField("高德 Web 服务 32 位 Key（用于天气/定位）", text: $editAmapKey)
                            .font(.caption)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(palette.background))
                        Button("保存 Key") {
                            viewModel.saveAmapKey(editAmapKey)
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .foregroundStyle(palette.ink)
                        .background(RoundedRectangle(cornerRadius: 10).fill(palette.background))
                    }

                    Picker("外观模式", selection: Binding(
                        get: { viewModel.appearance },
                        set: { viewModel.updateAppearance($0) }
                    )) {
                        ForEach(AppearancePreference.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Divider()
                        .overlay(palette.line)

                    Toggle(isOn: Binding(
                        get: { viewModel.liveActivityEnabled },
                        set: { viewModel.updateLiveActivityEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("灵动岛充电实况")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(palette.ink)
                            Text("仅在充电进行时显示实时功率与预计剩余时间")
                                .font(.caption2)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .tint(palette.good)
                    .accessibilityIdentifier("settings_live_activity_toggle")
                }
                .lingpaoCard(padding: 14)

                // 5. 退出登录 / 退出演示
                Button(role: .destructive) {
                    viewModel.logout()
                } label: {
                    Text(viewModel.isDemoMode ? "退出演示并前往登录" : "退出当前账号")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(palette.danger)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            }
            .clipped()
        }
        .onAppear {
            editPin = KeychainStore.shared.loadOpPassword()
            editAmapKey = viewModel.amapKey
        }
    }

    @ViewBuilder
    private func myVehiclesCard(
        palette: LingpaoPalette,
        profile: CarModelProfile,
        selectedPaint: PaintColor
    ) -> some View {
        let otherVehicles = viewModel.vehicles.filter { $0.vin != viewModel.session.selectedVin }
        let displayedOthers = Array(otherVehicles.prefix(2))

        VStack(alignment: .leading, spacing: 12) {
            // 顶部：标题 + 多车计数（单车精简不冗杂）+ 右上角车型展厅/管理车库统一入口
            HStack {
                Text("我的车辆")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.ink)

                if viewModel.vehicles.count > 1 {
                    Text("\(viewModel.vehicles.count) 辆")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .foregroundStyle(palette.secondary)
                        .background(Capsule().fill(palette.background))
                }

                Spacer()

                Button {
                    viewModel.isVehicleGaragePresented = true
                } label: {
                    HStack(spacing: 3) {
                        Text(viewModel.isDemoMode ? "车型展厅" : "管理车库")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.good)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings_open_garage")
            }

            // 1. 当前激活车辆大卡（单车时仅此一张卡片，底部清爽无额外内容）
            vehicleRowCard(
                carType: profile.displayName,
                vehicleName: viewModel.currentVehicleName,
                powertrain: viewModel.selectedVehicle?.powertrain ?? .bev,
                paintId: viewModel.session.selectedPaintId,
                vin: viewModel.selectedVehicle?.vin ?? viewModel.session.selectedVin,
                isCurrent: true,
                palette: palette
            ) {
                viewModel.isVehicleGaragePresented = true
            }
            .accessibilityIdentifier("settings_current_vehicle_card")

            // 2. 多车场景（>1 辆）：其余车辆采用完全同造型同规格的 3/4 实车大卡
            if !displayedOthers.isEmpty {
                VStack(spacing: 10) {
                    ForEach(displayedOthers) { car in
                        vehicleRowCard(
                            carType: car.carType,
                            vehicleName: car.vehicleName,
                            powertrain: car.powertrain,
                            paintId: car.outColor,
                            vin: car.vin,
                            isCurrent: false,
                            palette: palette
                        ) {
                            viewModel.selectVehicle(car)
                        }
                    }

                    if otherVehicles.count > displayedOthers.count {
                        Button {
                            viewModel.isVehicleGaragePresented = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("查看全部 \(viewModel.vehicles.count) 辆车")
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.good)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 多座椅布局（C16 / D19）
            if profile.supportedLayouts.count > 1 {
                Divider()
                    .overlay(palette.line)

                HStack {
                    Text("座椅布局")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.secondary)
                    Spacer()
                    ForEach(profile.supportedLayouts) { layout in
                        let cur = viewModel.session.selectedSeatLayout ?? profile.defaultLayout
                        Button(layout.displayName) {
                            viewModel.updateSeatLayout(layout)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(cur == layout ? .white : palette.ink)
                        .background(Capsule().fill(cur == layout ? palette.good : palette.background))
                    }
                }
            }
        }
        .lingpaoCard(padding: 14)
    }

    @ViewBuilder
    private func vehicleRowCard(
        carType: String,
        vehicleName: String,
        powertrain: PowertrainType,
        paintId: String,
        vin: String,
        isCurrent: Bool,
        palette: LingpaoPalette,
        action: @escaping () -> Void
    ) -> some View {
        let modelProfile = CarModelCatalog.profile(for: carType)
        let paint = PaintCatalog.resolvePaint(id: paintId, carTypeOrId: modelProfile.displayName)
        let vinSuffix = String(vin.suffix(6))

        Button(action: action) {
            HStack(spacing: 12) {
                VehicleThumbnailView(
                    carType: modelProfile.displayName,
                    paintId: paint.id,
                    width: 92,
                    height: 56
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(vehicleName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)

                        if isCurrent {
                            Text("当前")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white)
                                .background(Capsule().fill(palette.good))
                        }
                    }

                    HStack(spacing: 5) {
                        Text("\(modelProfile.displayName) · \(powertrain.displayName)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(palette.secondary)

                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(palette.inactive)

                        Circle()
                            .fill(Color(argb: paint.argb))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(palette.line, lineWidth: 0.6))

                        Text(paint.displayName)
                            .font(.caption2)
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }

                    Text(vinSuffix.isEmpty ? "演示体验车" : "VIN \(vinSuffix)")
                        .font(.caption2)
                        .foregroundStyle(palette.inactive)
                }

                Spacer(minLength: 4)

                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCurrent ? palette.good : palette.inactive)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCurrent ? palette.good.opacity(0.06) : palette.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isCurrent ? palette.good : palette.line, lineWidth: isCurrent ? 1.4 : 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
