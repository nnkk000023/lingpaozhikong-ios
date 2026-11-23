import LingpaoCore
import SwiftUI
import UIKit

/// Tab 2「控车」页：支持座椅/方向盘/后视镜直接点击、上滑整体展开卡片与车模横置联动、流畅冷暖空调氛围动效与自定义分组
public struct CabinControlView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var targetTemp: Double = 24
    @State private var windLevel: Int = 3
    @State private var dragOffset: CGFloat = 0
    @State private var isAcSchedulePresented: Bool = false
    @State private var isPreheatSchedulePresented: Bool = false
    @State private var isChargeSchedulePresented: Bool = false
    @State private var isFridgePresented: Bool = false
    @State private var isLayoutEditorPresented: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let t = viewModel.telemetry
        let hvac = viewModel.selectedVehicle?.hvacCapability ?? viewModel.session.hvacCapability
        let isExpanded = viewModel.isCabinDockExpanded
        let dockMaxHeight: CGFloat = isExpanded
            ? (viewModel.selectedCabinTarget == nil ? 470 : 395)
            : 300

        VStack(spacing: 0) {
            // 顶部紧凑状态栏（移除蓝牙按钮，仅多车时展示切车胶囊，保证顶部空域净透）
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("座舱控车")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(palette.ink)

                    if viewModel.selectedCabinTarget == nil {
                        Text(isExpanded ? "下拉面板还原俯视车模" : "点击座椅或部件调节")
                            .font(.caption2)
                            .foregroundStyle(palette.secondary)
                    }
                }

                Spacer(minLength: 4)

                GlobalVehicleChip(viewModel: viewModel, compact: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // 中间：穿透触控空间，上滑展开时精确留出横置车模展示空域
            Spacer(minLength: isExpanded ? 150 : 210)

            if let target = viewModel.selectedCabinTarget {
                selectedTargetFloatingBar(target: target, telemetry: t, palette: palette)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 下半部可上滑展开控制坞（收起态支持整卡上滑呼出、展开态顶栏下滑收起）
            VStack(spacing: 8) {
                dockHeaderBar(isExpanded: isExpanded, palette: palette)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(viewModel.layoutPreferences.cabinGroupOrder) { group in
                            switch group {
                            case .climate:
                                climateControlCard(telemetry: t, hvac: hvac, palette: palette)
                            case .bodyHardware:
                                bodyHardwareCard(telemetry: t, palette: palette)
                            case .comfortSchedule:
                                scheduleCard(telemetry: t, palette: palette)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
            }
            .frame(maxHeight: dockMaxHeight)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(palette.background)
                    .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: -4)
            )
            .offset(y: dragOffset)
            .padding(.horizontal, 6)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18, coordinateSpace: .local)
                    .onChanged { value in
                        guard !isExpanded else { return }
                        if value.translation.height < 0 {
                            dragOffset = max(value.translation.height * 0.25, -36)
                        }
                    }
                    .onEnded { value in
                        guard !isExpanded else { return }
                        let shouldExpand = value.translation.height < -32
                        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                            dragOffset = 0
                            if shouldExpand {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.isCabinDockExpanded = true
                            }
                        }
                    }
            )
        }
        .onAppear {
            targetTemp = t.acTargetTemp
            windLevel = max(t.acWindLevel, hvac.minFan ?? 1)
        }
        .onChange(of: t.acTargetTemp) { _, newVal in
            withAnimation(.spring(duration: 0.35)) {
                targetTemp = newVal
            }
        }
        .onChange(of: t.acWindLevel) { _, newVal in
            windLevel = max(newVal, hvac.minFan ?? 1)
        }
        .sheet(isPresented: $isAcSchedulePresented) {
            AcScheduleSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isPreheatSchedulePresented) {
            PreheatScheduleSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isChargeSchedulePresented) {
            CabinChargeScheduleSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isFridgePresented) {
            FridgeControlSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isLayoutEditorPresented) {
            CabinLayoutEditorSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func dockHeaderBar(isExpanded: Bool, palette: LingpaoPalette) -> some View {
        ZStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                    viewModel.isCabinDockExpanded.toggle()
                }
            } label: {
                Capsule()
                    .fill(palette.secondary.opacity(0.36))
                    .frame(width: 40, height: 4.5)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("cabin_dock_handle")
            .accessibilityLabel(isExpanded ? "收起控车面板" : "展开更多控车功能")
            .highPriorityGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        let dy = value.translation.height
                        if !isExpanded && dy < 0 {
                            dragOffset = max(dy * 0.35, -40)
                        } else if isExpanded && dy > 0 {
                            dragOffset = min(dy * 0.35, 40)
                        }
                    }
                    .onEnded { value in
                        let dy = value.translation.height
                        let toggleExpand: Bool? = (!isExpanded && dy < -26)
                            ? true
                            : ((isExpanded && dy > 26) ? false : nil)
                        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                            dragOffset = 0
                            if let next = toggleExpand {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.isCabinDockExpanded = next
                            }
                        }
                    }
            )

            HStack {
                Spacer()
                Button {
                    isLayoutEditorPresented = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.grid.2x2")
                        Text("自定义")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.good)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(palette.good.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cabin_customize_layout")
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func selectedTargetFloatingBar(
        target: CabinInteractiveTarget,
        telemetry: VehicleTelemetry,
        palette: LingpaoPalette
    ) -> some View {
        switch target {
        case .seat(let seat):
            selectedSeatFloatingBar(seat: seat, telemetry: telemetry, palette: palette)
        case .steeringWheel:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("方向盘加热", systemImage: "steeringwheel")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Button("收起") {
                        withAnimation(.spring(duration: 0.25)) {
                            viewModel.selectedCabinTarget = nil
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.secondary)
                }

                HStack(spacing: 8) {
                    ForEach([(0, "关"), (1, "弱档"), (2, "强档")], id: \.0) { lv, title in
                        levelPillButton(
                            title: title,
                            isActive: telemetry.steeringWheelHeatingLevel == lv,
                            activeColor: lv == 0 ? palette.secondary : Color(hex: 0xE0793A),
                            palette: palette
                        ) {
                            viewModel.executeControl(.steeringWheelHeating(level: lv))
                        }
                    }
                }
            }
            .lingpaoCard(padding: 12)
        case .mirrors:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("外后视镜加热", systemImage: "heat.waves")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Button("收起") {
                        withAnimation(.spring(duration: 0.25)) {
                            viewModel.selectedCabinTarget = nil
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.secondary)
                }

                HStack(spacing: 8) {
                    levelPillButton(
                        title: "关闭",
                        isActive: !telemetry.rearMirrorHeatingOn,
                        activeColor: palette.secondary,
                        palette: palette
                    ) {
                        viewModel.executeControl(.mirrorHeating(on: false))
                    }
                    levelPillButton(
                        title: "开启加热",
                        isActive: telemetry.rearMirrorHeatingOn,
                        activeColor: Color(hex: 0xE0793A),
                        palette: palette
                    ) {
                        viewModel.executeControl(.mirrorHeating(on: true))
                    }
                }
            }
            .lingpaoCard(padding: 12)
        }
    }

    @ViewBuilder
    private func selectedSeatFloatingBar(seat: SeatRole, telemetry: VehicleTelemetry, palette: LingpaoPalette) -> some View {
        let heat = telemetry.heatingLevel(for: seat)
        let vent = telemetry.ventilationLevel(for: seat)
        let supportsCtrl = seat.controlPosition != nil

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(seat.displayName)座椅调节")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Button("收起") {
                    withAnimation(.spring(duration: 0.25)) {
                        viewModel.selectedCabinTarget = nil
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.secondary)
            }

            if supportsCtrl {
                HStack(spacing: 8) {
                    Text("加热")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 34, alignment: .leading)
                    ForEach(0...3, id: \.self) { lv in
                        levelPillButton(
                            title: lv == 0 ? "关" : "\(lv)档",
                            isActive: heat == lv,
                            activeColor: Color(hex: 0xE0793A),
                            palette: palette
                        ) {
                            viewModel.executeControl(.seatHeating(role: seat, level: lv))
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text("通风")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 34, alignment: .leading)
                    ForEach(0...3, id: \.self) { lv in
                        levelPillButton(
                            title: lv == 0 ? "关" : "\(lv)档",
                            isActive: vent == lv,
                            activeColor: Color(hex: 0x287DEB),
                            palette: palette
                        ) {
                            viewModel.executeControl(.seatVentilation(role: seat, level: lv))
                        }
                    }
                }
            } else {
                Text("当前中排/三排座椅仅支持座舱图展示")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
            }
        }
        .lingpaoCard(padding: 12)
    }

    @ViewBuilder
    private func levelPillButton(
        title: String,
        isActive: Bool,
        activeColor: Color,
        palette: LingpaoPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? .white : palette.ink)
            .background(
                Capsule().fill(isActive ? activeColor : palette.background)
            )
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private func climateControlCard(telemetry: VehicleTelemetry, hvac: HvacCapability, palette: LingpaoPalette) -> some View {
        let mode = telemetry.activeClimateMode
        let themeColor = climateThemeColor(mode: mode, acOn: telemetry.acOn, palette: palette)
        let statusTitle: String = {
            guard telemetry.acOn else { return "空调已关闭" }
            switch mode {
            case .quickCool: return "极速降温运行中 · 设定 \(Int(targetTemp))°C"
            case .quickHeat: return "极速升温运行中 · 设定 \(Int(targetTemp))°C"
            case .deodorize: return "快速除味换气中 · 外循环"
            case .defrost: return "前挡除霜开启 · \(Int(targetTemp))°C"
            case .cool, .heat, .off: return "运行中 · 设定 \(Int(targetTemp))°C · 风量 \(windLevel) 档"
            }
        }()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("空调系统")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.ink)
                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(telemetry.acOn ? themeColor : palette.secondary)
                }
                Spacer()
                Button(telemetry.acOn ? "关闭" : "开启") {
                    withAnimation(.spring(duration: 0.42, bounce: 0.2)) {
                        viewModel.executeControl(telemetry.acOn ? .acOff : .acOn)
                    }
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(.white)
                .background(Capsule().fill(telemetry.acOn ? palette.danger : palette.good))
            }

            HStack(spacing: 12) {
                Text("\(Int(targetTemp))°C")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(telemetry.acOn ? themeColor : palette.ink)
                    .contentTransition(.numericText())
                    .frame(width: 54, alignment: .leading)

                Slider(
                    value: $targetTemp,
                    in: Double(hvac.minTemp)...Double(hvac.maxTemp),
                    step: 1
                )
                .tint(telemetry.acOn ? themeColor : (targetTemp >= 27 ? Color(hex: 0xE0793A) : palette.good))

                Button("应用") {
                    let req = ClimateControlRequest(
                        temperature: Int(targetTemp),
                        capability: hvac,
                        windLevel: windLevel,
                        circle: telemetry.recirculationIn ? .internalLoop : .externalLoop,
                        windshieldDefrost: telemetry.windshieldDefrostOn
                    )
                    withAnimation(.spring(duration: 0.4)) {
                        viewModel.executeControl(.climate(req))
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(palette.ink)
                .background(Capsule().fill(palette.background))
            }

            // 极速冷/暖/除味/前挡除霜（带当前模式高亮与平滑状态切换）
            let climateActions = viewModel.layoutPreferences.climateQuickActions
            if !climateActions.isEmpty {
                BalancedActionGrid(items: climateActions, maxColumns: 4, spacing: 8) { item in
                    let active = isClimateActionActive(item, telemetry: telemetry)
                    let chipColor = climateActionTint(item, palette: palette)
                    modeChip(
                        item.displayName,
                        icon: item.icon,
                        isHighlighted: active,
                        highlightColor: chipColor,
                        palette: palette
                    ) {
                        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                            switch item {
                            case .quickCool: viewModel.executeControl(.quickCool)
                            case .quickHeat: viewModel.executeControl(.quickHeat)
                            case .deodorize: viewModel.executeControl(.deodorize)
                            case .defrost: viewModel.executeControl(.defrost)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [themeColor.opacity(telemetry.acOn ? 0.14 : 0.0), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(telemetry.acOn ? themeColor.opacity(0.55) : palette.line, lineWidth: telemetry.acOn ? 1.3 : 0.8)
                )
                .shadow(color: telemetry.acOn ? themeColor.opacity(0.14) : Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
        .animation(.easeInOut(duration: 0.42), value: telemetry.acOn)
        .animation(.easeInOut(duration: 0.42), value: telemetry.activeClimateMode)
    }

    @ViewBuilder
    private func bodyHardwareCard(telemetry: VehicleTelemetry, palette: LingpaoPalette) -> some View {
        let actions = viewModel.layoutPreferences.bodyHardwareActions
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("门窗与车身控制")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.ink)
                Spacer()
            }

            if actions.isEmpty {
                Text("已全部隐藏，可点击顶部「自定义」恢复功能开关")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 6)
            } else {
                BalancedActionGrid(items: actions, maxColumns: 3, spacing: 8) { item in
                    let spec = bodyActionSpec(for: item, telemetry: telemetry, palette: palette)
                    modeChip(
                        spec.title,
                        icon: spec.icon,
                        isHighlighted: spec.isHighlighted,
                        highlightColor: spec.color,
                        palette: palette
                    ) {
                        executeBodyAction(item, telemetry: telemetry)
                    }
                }
            }
        }
        .lingpaoCard(padding: 14)
    }

    @ViewBuilder
    private func scheduleCard(telemetry: VehicleTelemetry, palette: LingpaoPalette) -> some View {
        let scheduleActions = viewModel.layoutPreferences.comfortScheduleActions
        VStack(alignment: .leading, spacing: 10) {
            Text("定时预约")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.ink)

            if scheduleActions.isEmpty {
                Text("已全部隐藏，可点击顶部「自定义」恢复预约项目")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 6)
            } else {
                BalancedActionGrid(items: scheduleActions, maxColumns: 2, spacing: 8) { item in
                    let isHighlighted: Bool = {
                        switch item {
                        case .fridge: return telemetry.fridgeOn
                        case .chargeSchedule: return telemetry.chargeScheduleEnabled
                        default: return false
                        }
                    }()
                    modeChip(item.displayName, icon: item.icon, isHighlighted: isHighlighted, palette: palette) {
                        switch item {
                        case .acSchedule: isAcSchedulePresented = true
                        case .batteryPreheat: isPreheatSchedulePresented = true
                        case .chargeSchedule: isChargeSchedulePresented = true
                        case .fridge: isFridgePresented = true
                        }
                    }
                }
            }
        }
        .lingpaoCard(padding: 14)
    }

    private func climateThemeColor(mode: ClimateActiveMode, acOn: Bool, palette: LingpaoPalette) -> Color {
        guard acOn else { return palette.secondary }
        switch mode {
        case .off: return palette.good
        case .cool, .quickCool: return Color(hex: 0x287DEB)
        case .heat, .quickHeat: return Color(hex: 0xE0793A)
        case .deodorize: return palette.good
        case .defrost: return palette.warning
        }
    }

    private func isClimateActionActive(_ item: ClimateQuickAction, telemetry: VehicleTelemetry) -> Bool {
        guard telemetry.acOn else { return false }
        switch item {
        case .quickCool: return telemetry.activeClimateMode == .quickCool
        case .quickHeat: return telemetry.activeClimateMode == .quickHeat
        case .deodorize: return telemetry.activeClimateMode == .deodorize
        case .defrost: return telemetry.activeClimateMode == .defrost || telemetry.windshieldDefrostOn
        }
    }

    private func climateActionTint(_ item: ClimateQuickAction, palette: LingpaoPalette) -> Color {
        switch item {
        case .quickCool: return Color(hex: 0x287DEB)
        case .quickHeat: return Color(hex: 0xE0793A)
        case .deodorize: return palette.good
        case .defrost: return palette.warning
        }
    }

    private func bodyActionSpec(
        for item: BodyHardwareAction,
        telemetry: VehicleTelemetry,
        palette: LingpaoPalette
    ) -> (title: String, icon: String, isHighlighted: Bool, color: Color) {
        switch item {
        case .windowVent: return ("车窗通风", "car.top.door.front.left.open", false, palette.good)
        case .windowClose: return ("车窗全关", "window.ceiling.closed", false, palette.good)
        case .windowHalf: return ("车窗半开", "window.casement", false, palette.good)
        case .sunroofOpen: return ("打开天窗", "sun.max.fill", telemetry.sunroofOpening > 0, palette.good)
        case .sunroofClose: return ("关闭天窗", "moon.zzz.fill", false, palette.good)
        case .sunshadeOpen: return ("遮阳帘开", "blinds.horizontal.open", false, palette.good)
        case .sunshadeClose: return ("遮阳帘关", "blinds.horizontal.closed", false, palette.good)
        case .frunkToggle:
            return (telemetry.hoodOpen ? "关前备箱" : "开前备箱", "car.top.radiowaves.front.fill", telemetry.hoodOpen, palette.good)
        case .trunkToggle:
            return (telemetry.trunkOpen ? "关尾箱" : "开尾箱", "car.top.radiowaves.rear.right.fill", telemetry.trunkOpen, palette.good)
        case .sentryToggle:
            return (telemetry.sentryModeOn ? "关哨兵" : "开哨兵", "eye.circle.fill", telemetry.sentryModeOn, palette.good)
        case .mirrorHeatingToggle:
            return (telemetry.rearMirrorHeatingOn ? "关后视镜热" : "开后视镜热", "heat.waves", telemetry.rearMirrorHeatingOn, Color(hex: 0xE0793A))
        case .steeringWheelHeat:
            let lv = telemetry.steeringWheelHeatingLevel
            let label = lv == 0 ? "方向盘加热" : (lv == 1 ? "方向盘·弱" : "方向盘·强")
            return (label, "steeringwheel", lv > 0, Color(hex: 0xE0793A))
        case .twoRowMode: return ("二排模式", "rectangle.split.2x1", false, palette.good)
        case .threeRowMode: return ("三排模式", "rectangle.split.3x1", false, palette.good)
        case .slidingDoorLeftOpen: return ("左侧滑门开", "arrow.left.to.line", false, palette.good)
        case .slidingDoorLeftClose: return ("左侧滑门关", "arrow.right.to.line", false, palette.good)
        case .slidingDoorRightOpen: return ("右侧滑门开", "arrow.right.to.line", false, palette.good)
        case .slidingDoorRightClose: return ("右侧滑门关", "arrow.left.to.line", false, palette.good)
        }
    }

    private func executeBodyAction(_ item: BodyHardwareAction, telemetry: VehicleTelemetry) {
        switch item {
        case .windowVent: viewModel.executeControl(.window(percentCode: "2"))
        case .windowClose: viewModel.executeControl(.window(percentCode: "0"))
        case .windowHalf: viewModel.executeControl(.window(percentCode: "5"))
        case .sunroofOpen: viewModel.executeControl(.sunroof(open: true))
        case .sunroofClose: viewModel.executeControl(.sunroof(open: false))
        case .sunshadeOpen: viewModel.executeControl(.sunshade(open: true))
        case .sunshadeClose: viewModel.executeControl(.sunshade(open: false))
        case .frunkToggle: viewModel.executeControl(.frunk(open: !telemetry.hoodOpen))
        case .trunkToggle: viewModel.executeControl(.trunk(open: !telemetry.trunkOpen))
        case .sentryToggle: viewModel.executeControl(.sentryMode(on: !telemetry.sentryModeOn))
        case .mirrorHeatingToggle: viewModel.executeControl(.mirrorHeating(on: !telemetry.rearMirrorHeatingOn))
        case .steeringWheelHeat:
            let next = (telemetry.steeringWheelHeatingLevel + 1) % 3
            viewModel.executeControl(.steeringWheelHeating(level: next))
        case .twoRowMode: viewModel.executeControl(.seatRowMode(twoRow: true))
        case .threeRowMode: viewModel.executeControl(.seatRowMode(twoRow: false))
        case .slidingDoorLeftOpen: viewModel.executeControl(.slidingDoorLeft(open: true))
        case .slidingDoorLeftClose: viewModel.executeControl(.slidingDoorLeft(open: false))
        case .slidingDoorRightOpen: viewModel.executeControl(.slidingDoorRight(open: true))
        case .slidingDoorRightClose: viewModel.executeControl(.slidingDoorRight(open: false))
        }
    }

    @ViewBuilder
    private func modeChip(
        _ title: String,
        icon: String,
        isHighlighted: Bool = false,
        highlightColor: Color? = nil,
        palette: LingpaoPalette,
        action: @escaping () -> Void
    ) -> some View {
        let activeTint = highlightColor ?? palette.good
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(height: 18)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 4)
            .foregroundStyle(isHighlighted ? .white : palette.ink)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHighlighted ? activeTint : palette.background)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AcScheduleSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = true
    @State private var timeDate = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var temperature: Double = 24
    @State private var windLevel: Int = 3
    @State private var selectedWeekdays: Set<Int> = [1, 2, 3, 4, 5]

    var body: some View {
        NavigationStack {
            Form {
                Toggle("启用定时空调", isOn: $enabled)
                DatePicker("出发时间", selection: $timeDate, displayedComponents: .hourAndMinute)
                VStack(alignment: .leading) {
                    Text("设定温度：\(Int(temperature))°C")
                    Slider(value: $temperature, in: 16...32, step: 1)
                }
                Stepper("风量档位：\(windLevel) 档", value: $windLevel, in: 1...9)

                Section("重复周期") {
                    WeekdayPickerRow(selected: $selectedWeekdays)
                }

                Button("保存定时空调预约") {
                    let df = DateFormatter()
                    df.dateFormat = "HH:mm"
                    let cfg = ScheduledAcConfig(
                        enabled: enabled,
                        startTimeHHMM: df.string(from: timeDate),
                        weekdays: Array(selectedWeekdays).sorted(),
                        temperature: Int(temperature),
                        windLevel: windLevel
                    )
                    if viewModel.isDemoMode {
                        viewModel.showToast("已保存定时空调（演示模式）")
                        dismiss()
                    } else {
                        Task {
                            do {
                                try await viewModel.apiClient.setScheduledAc(config: cfg, opPassword: KeychainStore.shared.loadOpPassword())
                                viewModel.showToast("定时空调已下发")
                                dismiss()
                            } catch {
                                viewModel.showToast("设置失败：\(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("定时空调预约")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

private struct PreheatScheduleSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = true
    @State private var timeDate = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var selectedWeekdays: Set<Int> = [1, 2, 3, 4, 5]

    var body: some View {
        NavigationStack {
            Form {
                Section("立即执行") {
                    HStack {
                        Button("立即开启预热") { viewModel.executeControl(.batteryPreheat(on: true)) }
                        Spacer()
                        Button("关闭预热") { viewModel.executeControl(.batteryPreheat(on: false)) }
                    }
                }
                Section("定时预约") {
                    Toggle("启用定时电池预热", isOn: $enabled)
                    DatePicker("开始时间", selection: $timeDate, displayedComponents: .hourAndMinute)
                    WeekdayPickerRow(selected: $selectedWeekdays)
                    Button("下发电池预热预约") {
                        let df = DateFormatter()
                        df.dateFormat = "HH:mm"
                        let cfg = ScheduledBatteryPreheatConfig(
                            enabled: enabled,
                            startTimeHHMM: df.string(from: timeDate),
                            weekdays: Array(selectedWeekdays).sorted()
                        )
                        if viewModel.isDemoMode {
                            viewModel.showToast("电池预热预约已保存（演示）")
                            dismiss()
                        } else {
                            Task {
                                do {
                                    try await viewModel.apiClient.setScheduledBatteryPreheat(config: cfg, opPassword: KeychainStore.shared.loadOpPassword())
                                    viewModel.showToast("电池预热预约已下发")
                                    dismiss()
                                } catch {
                                    viewModel.showToast("设置失败：\(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("电池预热管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

private struct CabinChargeScheduleSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool = false
    @State private var startTime = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var continueFull: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Toggle("启用预约谷电充电", isOn: $enabled)
                DatePicker("开始时间", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("结束时间", selection: $endTime, displayedComponents: .hourAndMinute)
                Toggle("谷电时段外继续充满", isOn: $continueFull)
                Button("保存预约充电设置") {
                    let df = DateFormatter()
                    df.dateFormat = "HH:mm"
                    let s = df.string(from: startTime)
                    let e = df.string(from: endTime)
                    if viewModel.isDemoMode {
                        viewModel.telemetry.chargeScheduleEnabled = enabled
                        viewModel.telemetry.chargeScheduleStart = s
                        viewModel.telemetry.chargeScheduleEnd = e
                        viewModel.showToast("已保存预约充电 \(s)-\(e)（演示）")
                        dismiss()
                    } else {
                        Task {
                            do {
                                try await viewModel.apiClient.setChargeSchedule(
                                    enabled: enabled,
                                    startTime: s,
                                    endTime: e,
                                    targetSoc: viewModel.telemetry.healthyChargeTargetSoc,
                                    opPassword: KeychainStore.shared.loadOpPassword(),
                                    recharge: continueFull
                                )
                                viewModel.showToast("预约充电下发成功")
                                dismiss()
                            } catch {
                                viewModel.showToast("下发失败：\(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("预约充电")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .onAppear {
                enabled = viewModel.telemetry.chargeScheduleEnabled
            }
        }
    }
}

private struct FridgeControlSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var enable = true
    @State private var mode: FridgeMode = .cold
    @State private var temp: Double = 4
    @State private var style: FridgeStyle = .normal
    @State private var parkEnable = false

    var body: some View {
        NavigationStack {
            Form {
                Toggle("开启车载冰箱", isOn: $enable)
                Picker("模式", selection: $mode) {
                    Text("制冷 (-6~15°C)").tag(FridgeMode.cold)
                    Text("制热 (固定 50°C)").tag(FridgeMode.hot)
                }
                if mode == .cold {
                    VStack(alignment: .leading) {
                        Text("目标温度：\(Int(temp))°C")
                        Slider(value: $temp, in: -6...15, step: 1)
                    }
                }
                Picker("工作风格", selection: $style) {
                    Text("标准").tag(FridgeStyle.normal)
                    Text("急速").tag(FridgeStyle.turbo)
                }
                Toggle("离车保温供电", isOn: $parkEnable)
                Button("保存并应用冰箱设置") {
                    let req = FridgeControlRequest(
                        enable: enable,
                        mode: mode,
                        temperature: Int(temp),
                        style: style,
                        parkEnable: parkEnable
                    )
                    viewModel.executeControl(.fridge(req))
                    dismiss()
                }
            }
            .navigationTitle("车载冰箱设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

private struct WeekdayPickerRow: View {
    @Binding var selected: Set<Int>
    private let labels = [(1, "一"), (2, "二"), (3, "三"), (4, "四"), (5, "五"), (6, "六"), (7, "日")]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(labels, id: \.0) { day, text in
                let isOn = selected.contains(day)
                Button(text) {
                    if isOn { selected.remove(day) } else { selected.insert(day) }
                }
                .font(.caption.weight(.bold))
                .frame(width: 34, height: 34)
                .foregroundStyle(isOn ? .white : .primary)
                .background(Circle().fill(isOn ? Color(hex: 0x1FA463) : Color.secondary.opacity(0.15)))
                .buttonStyle(.plain)
            }
        }
    }
}
