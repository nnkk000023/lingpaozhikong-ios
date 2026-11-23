import LingpaoCore
import SwiftUI

/// 异步渲染的 3/4 实车缩略图（支持随 `paintId` 动态 Metal 着染并带 32 槽内存缓存）
public struct VehicleThumbnailView: View {
    public let carType: String?
    public let paintId: String?
    public var width: CGFloat = 88
    public var height: CGFloat = 54

    @Environment(\.colorScheme) private var colorScheme
    @State private var thumbnail: UIImage?

    public init(carType: String?, paintId: String?, width: CGFloat = 88, height: CGFloat = 54) {
        self.carType = carType
        self.paintId = paintId
        self.width = width
        self.height = height
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                Image(systemName: "car.side.fill")
                    .font(.system(size: min(width, height) * 0.42))
                    .foregroundStyle(palette.inactive.opacity(0.65))
            }
        }
        .frame(width: width, height: height)
        .task(id: "\(carType ?? "")|\(paintId ?? "")") {
            let loaded = await CarAssetLoader.shared.loadHeroThumbnail(for: carType, paintId: paintId)
            withAnimation(.easeIn(duration: 0.16)) {
                thumbnail = loaded
            }
        }
    }
}

/// 顶栏全局多车快速切换胶囊（用于控车 / 充电 / 出行等全端顶部栏）
public struct GlobalVehicleChip: View {
    @Bindable var viewModel: AppViewModel
    public var compact: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: AppViewModel, compact: Bool = false) {
        self.viewModel = viewModel
        self.compact = compact
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let profile = viewModel.currentCarProfile
        let paint = viewModel.currentPaintColor
        let count = viewModel.vehicles.count

        // 仅在多辆车时显示可切换入口，单车保持精简清爽
        if count > 1 {
            let indexText = "\((viewModel.currentVehicleIndex ?? 0) + 1)/\(count)"
            Button {
                viewModel.isVehicleGaragePresented = true
            } label: {
                HStack(spacing: compact ? 5 : 6) {
                    Circle()
                        .fill(Color(argb: paint.argb))
                        .frame(width: compact ? 8 : 9, height: compact ? 8 : 9)
                        .overlay(Circle().stroke(palette.line, lineWidth: 0.8))

                    Text(profile.displayName)
                        .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)

                    Text(indexText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.secondary)
                }
                .padding(.horizontal, compact ? 9 : 11)
                .padding(.vertical, compact ? 5 : 6)
                .background(
                    Capsule()
                        .fill(palette.card.opacity(0.95))
                        .overlay(Capsule().stroke(palette.line, lineWidth: 0.8))
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("global_vehicle_switcher")
            .accessibilityLabel("切换车辆，当前\(profile.displayName)")
        }
    }
}

/// 车况首页顶部车名标题栏（多车时附带下拉切车与序数角标；仅一辆车时不显示任何切换入口与下拉箭头）
public struct HomeVehicleHeaderButton: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let count = viewModel.vehicles.count

        HStack(spacing: 6) {
            Text(viewModel.currentVehicleName)
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if count > 1 {
                Button {
                    viewModel.isVehicleGaragePresented = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(palette.good)

                        if let idx = viewModel.currentVehicleIndex {
                            Text("\(idx + 1)/\(count)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(palette.ink)
                                .background(Capsule().fill(palette.card))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home_vehicle_switcher")
                .accessibilityLabel("切换爱车，当前共\(count)辆")
            }

            if viewModel.isDemoMode {
                Text("演示")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(palette.good)
                    .background(Capsule().fill(palette.good.opacity(0.14)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if count > 1 {
                viewModel.isVehicleGaragePresented = true
            }
        }
    }
}

/// 全局统一车库抽屉：整合多车绑定列表切换与全系 12 款零跑车型统一网格展厅
public struct VehicleGarageSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var isLocalModelOverrideExpanded: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // 区块 1：我的多车车库列表
                    myVehiclesSection(palette: palette)

                    // 区块 2：全系车型展厅（演示模式直接展示；线上模式可折叠用于本地车模校正）
                    if viewModel.isDemoMode {
                        modelShowcaseSection(palette: palette, isCorrectionMode: false)
                    } else {
                        onlineModelOverrideSection(palette: palette)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("我的车库（\(viewModel.vehicles.count) 辆）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(palette.secondary)
                    }
                    .accessibilityLabel("关闭车库")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func myVehiclesSection(palette: LingpaoPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的车辆")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("点击卡片立即切换当前控车对象")
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
            }

            if viewModel.vehicles.isEmpty {
                Text("当前账号暂未绑定车辆")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .lingpaoCard(padding: 14)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.vehicles) { car in
                        let isCurrent = car.vin == viewModel.session.selectedVin
                        let activePaintId = isCurrent ? viewModel.session.selectedPaintId : car.outColor
                        let paint = PaintCatalog.resolvePaint(id: activePaintId, carTypeOrId: car.carType)

                        HStack(spacing: 10) {
                            Button {
                                viewModel.selectVehicle(car)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VehicleThumbnailView(
                                        carType: car.carType,
                                        paintId: activePaintId,
                                        width: 86,
                                        height: 52
                                    )

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(car.vehicleName)
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(palette.ink)
                                                .lineLimit(1)

                                            if car.isShared {
                                                Text("共享")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .foregroundStyle(palette.warningText)
                                                    .background(Capsule().fill(palette.warning.opacity(0.15)))
                                            }
                                        }

                                        Text("\(car.carType) · \(car.powertrain.displayName)")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(palette.secondary)

                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(Color(argb: paint.argb))
                                                .frame(width: 8, height: 8)
                                                .overlay(Circle().stroke(palette.line, lineWidth: 0.6))
                                            Text(paint.displayName)
                                                .font(.caption2)
                                                .foregroundStyle(palette.secondary)
                                            Text("· VIN \(car.vin.suffix(6))")
                                                .font(.caption2)
                                                .foregroundStyle(palette.inactive)
                                        }
                                    }

                                    Spacer(minLength: 4)

                                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isCurrent ? palette.good : palette.inactive)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // 演示模式下且车库不止 1 辆车时，允许移除非当前体验车
                            if viewModel.isDemoMode && viewModel.vehicles.count > 1 && !isCurrent {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.removeDemoVehicle(vin: car.vin)
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(palette.inactive)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("移除 \(car.vehicleName)")
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isCurrent ? palette.good.opacity(0.08) : palette.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(isCurrent ? palette.good : palette.line, lineWidth: isCurrent ? 1.5 : 0.8)
                                )
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func onlineModelOverrideSection(palette: LingpaoPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isLocalModelOverrideExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本地渲染车型校正")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.ink)
                        Text("仅调整本机 3D 车模样式，不影响云端车辆 VIN")
                            .font(.caption2)
                            .foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    Image(systemName: isLocalModelOverrideExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.secondary)
                }
                .lingpaoCard(padding: 14)
            }
            .buttonStyle(.plain)

            if isLocalModelOverrideExpanded {
                modelShowcaseSection(palette: palette, isCorrectionMode: true)
            }
        }
    }

    @ViewBuilder
    private func modelShowcaseSection(palette: LingpaoPalette, isCorrectionMode: Bool) -> some View {
        let currentProfileId = viewModel.currentCarProfile.id
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isCorrectionMode ? "选择本地车模（12 款）" : "全系车型展厅（12 款）")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text(isCorrectionMode ? "不改 VIN" : "点击即加入并切换")
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(CarModelCatalog.showcaseModels) { model in
                    let isCurrent = model.id == currentProfileId
                    let existingCar = viewModel.vehicles.first {
                        CarModelCatalog.profile(for: $0.carType).id == model.id
                    }
                    let thumbPaintId: String = isCurrent
                        ? viewModel.session.selectedPaintId
                        : (existingCar?.outColor ?? PaintCatalog.availablePaints(for: model.displayName).first?.id ?? "liquid_silver")

                    Button {
                        if viewModel.isDemoMode {
                            viewModel.addOrSwitchDemoModel(modelId: model.id)
                        } else {
                            viewModel.overrideLocalCarModel(modelId: model.id)
                        }
                        dismiss()
                    } label: {
                        VStack(spacing: 5) {
                            HStack {
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(palette.good)
                                } else if existingCar != nil && !isCorrectionMode {
                                    Text("在车库")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .foregroundStyle(palette.secondary)
                                        .background(Capsule().fill(palette.background))
                                } else {
                                    Color.clear.frame(height: 14)
                                }
                            }

                            VehicleThumbnailView(
                                carType: model.displayName,
                                paintId: thumbPaintId,
                                width: 78,
                                height: 46
                            )

                            Text(model.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.ink)

                            Text(model.bodyStyle.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .foregroundStyle(isCurrent ? palette.good : palette.secondary)
                                .background(
                                    Capsule()
                                        .fill(isCurrent ? palette.good.opacity(0.14) : palette.background)
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isCurrent ? palette.good.opacity(0.08) : palette.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isCurrent ? palette.good : palette.line, lineWidth: isCurrent ? 1.5 : 0.8)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("garage_model_\(model.id)")
                    .accessibilityLabel("\(model.displayName) \(model.bodyStyle.displayName)")
                }
            }
        }
    }
}
