import LingpaoCore
import SwiftUI

/// 页面间共享车模舞台视图（支持 800ms 位移缩放、横竖平滑切换、流体冷暖空调气流、座椅/方向盘/后视镜精准热区交互）
public struct InteractiveCarStageView: View {
    public let assets: LoadedCarAssets?
    public let telemetry: VehicleTelemetry
    public let stage: AppStageRoute
    public let selectedTarget: CabinInteractiveTarget?
    public let lightFlashOpacity: Double
    public let isInteractiveCabin: Bool
    public let isCabinLandscape: Bool
    public let onSelectTarget: (CabinInteractiveTarget) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var shaderTimeStart = Date()

    public init(
        assets: LoadedCarAssets?,
        telemetry: VehicleTelemetry,
        stage: AppStageRoute,
        selectedTarget: CabinInteractiveTarget? = nil,
        lightFlashOpacity: Double = 0,
        isInteractiveCabin: Bool = false,
        isCabinLandscape: Bool = false,
        onSelectTarget: @escaping (CabinInteractiveTarget) -> Void = { _ in }
    ) {
        self.assets = assets
        self.telemetry = telemetry
        self.stage = stage
        self.selectedTarget = selectedTarget
        self.lightFlashOpacity = lightFlashOpacity
        self.isInteractiveCabin = isInteractiveCabin
        self.isCabinLandscape = isCabinLandscape
        self.onSelectTarget = onSelectTarget
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let modelId = assets?.modelId ?? "c16"
        let pose = CarPose.pose(for: stage, modelId: modelId)
        let transform = assets?.normalizeTransform ?? .identity

        GeometryReader { geo in
            // 以原版 412dp 手机宽度为基准映射到 iPhone 屏幕逻辑宽度
            let designWidth: CGFloat = 412.0
            let uiScale = geo.size.width / designWidth
            let logicalW = CarCanvasMetrics.logicalWidth * uiScale
            let logicalH = CarCanvasMetrics.logicalHeight * uiScale

            // 控车面板整体上滑展开时，车模平滑缩小并向左横旋转 -90° 居于顶部空域
            let useLandscape = (stage == .car && isCabinLandscape)
            let targetScale: CGFloat = useLandscape ? 0.58 : CGFloat(pose.scale)
            let targetAngle: Double = useLandscape ? -90.0 : 0.0
            let centerX: CGFloat = useLandscape
                ? geo.size.width * 0.5
                : (CGFloat(pose.x) + CarCanvasMetrics.logicalWidth * CGFloat(pose.scale) * 0.5) * uiScale
            let centerY: CGFloat = useLandscape
                ? 144.0 * uiScale
                : (CGFloat(pose.y) + CarCanvasMetrics.logicalHeight * CGFloat(pose.scale) * 0.5) * uiScale

            ZStack(alignment: .topLeading) {
                // 主车舞台容器（遵循中心锚点缩放、横竖旋转与位姿平滑转换）
                ZStack(alignment: .topLeading) {
                    // 1. 车外层（带归一化内偏移矩阵）
                    exteriorLayer(assets: assets, logicalW: logicalW, logicalH: logicalH, uiScale: uiScale)
                        .frame(width: logicalW, height: logicalH)
                        .scaleEffect(transform.scale, anchor: .topLeading)
                        .offset(x: transform.offsetX * uiScale, y: transform.offsetY * uiScale)
                        .opacity(pose.exteriorAlpha)
                        .animation(.easeInOut(duration: 0.55), value: pose.exteriorAlpha)

                    // 2. 车内座舱交互层（含流体空调、热舒适与部件高亮）
                    interiorLayer(assets: assets, logicalW: logicalW, logicalH: logicalH, uiScale: uiScale)
                        .frame(width: logicalW, height: logicalH)
                        .scaleEffect(transform.scale, anchor: .topLeading)
                        .offset(x: transform.offsetX * uiScale, y: transform.offsetY * uiScale)
                        .opacity(pose.interiorAlpha)
                        .animation(.easeInOut(duration: 0.55), value: pose.interiorAlpha)

                    // 3. 车外态胎压悬浮徽章
                    if stage == .home && pose.exteriorAlpha > 0.5, let assets, !assets.wheels.isEmpty {
                        tirePressureBadges(assets: assets, transform: transform, logicalW: logicalW, logicalH: logicalH, uiScale: uiScale, palette: palette)
                    }

                    // 4. 归一化后视镜加热微光与选中边框
                    if let assets {
                        mirrorStatusOverlay(assets: assets, uiScale: uiScale, palette: palette)
                    }

                    // 5. 座舱可交互点击热区（包含全部座椅 + 方向盘 + 左右外后视镜）
                    if isInteractiveCabin, let assets {
                        cabinHitTargets(assets: assets, logicalW: logicalW, logicalH: logicalH, uiScale: uiScale)
                    }
                }
                .frame(width: logicalW, height: logicalH, alignment: .topLeading)
                .scaleEffect(targetScale, anchor: .center)
                .rotationEffect(.degrees(targetAngle), anchor: .center)
                .position(x: centerX, y: centerY)
                .animation(.spring(response: 0.52, dampingFraction: 0.84), value: useLandscape)
                .animation(.interpolatingSpring(mass: 1.0, stiffness: 90, damping: 16), value: pose.x)
                .animation(.interpolatingSpring(mass: 1.0, stiffness: 90, damping: 16), value: pose.y)
                .animation(.interpolatingSpring(mass: 1.0, stiffness: 90, damping: 16), value: pose.scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(isInteractiveCabin)
    }

    @ViewBuilder
    private func exteriorLayer(
        assets: LoadedCarAssets?,
        logicalW: CGFloat,
        logicalH: CGFloat,
        uiScale: CGFloat
    ) -> some View {
        ZStack {
            let baseExt: UIImage? = telemetry.mirrorsFolded
                ? (assets?.exteriorFoldedMirrorsImage ?? assets?.exteriorImage)
                : assets?.exteriorImage

            if let baseExt {
                Image(uiImage: baseExt)
                    .resizable()
                    .scaledToFit()
            }

            if let glow = assets?.lightsGlowImage, lightFlashOpacity > 0.005 {
                Image(uiImage: glow)
                    .resizable()
                    .scaledToFit()
                    .opacity(lightFlashOpacity)
                    .blendMode(.screen)
            }
        }
    }

    @ViewBuilder
    private func interiorLayer(
        assets: LoadedCarAssets?,
        logicalW: CGFloat,
        logicalH: CGFloat,
        uiScale: CGFloat
    ) -> some View {
        let isWarmClimate = telemetry.acOn && (telemetry.activeClimateMode == .heat || telemetry.activeClimateMode == .quickHeat)
        let isCoolClimate = telemetry.acOn && !isWarmClimate

        ZStack {
            if let interior = assets?.interiorImage {
                Image(uiImage: interior)
                    .resizable()
                    .scaledToFit()
            }

            // 空调全舱冷/暖基础氛围渐变叠加（随模式丝滑淡入淡出）
            if isCoolClimate, let coolOverlay = assets?.cabinCoolOverlay {
                Image(uiImage: coolOverlay)
                    .resizable()
                    .scaledToFit()
                    .opacity(telemetry.activeClimateMode == .quickCool ? 1.0 : 0.78)
                    .transition(.opacity)
            }
            if isWarmClimate, let warmOverlay = assets?.cabinWarmOverlay {
                Image(uiImage: warmOverlay)
                    .resizable()
                    .scaledToFit()
                    .opacity(telemetry.activeClimateMode == .quickHeat ? 1.0 : 0.78)
                    .transition(.opacity)
            }

            // Metal `cabinAirflowEffect` 实时流动冷暖气流波纹动画
            if telemetry.acOn, let airflowImg = assets?.airflowMaskImage {
                TimelineView(.animation(paused: !telemetry.acOn)) { timeline in
                    let t = Float(timeline.date.timeIntervalSince(shaderTimeStart))
                    Image(uiImage: airflowImg)
                        .resizable()
                        .scaledToFit()
                        .colorEffect(
                            ShaderLibrary.cabinAirflowEffect(
                                .float(Float(logicalH)),
                                .float(airflowModeFloat),
                                .float(t)
                            )
                        )
                        .blendMode(.screen)
                }
                .transition(.opacity)
            }

            // 各座椅加热/通风 W3C Color/Screen 高亮 + 呼吸微光 Shader
            if let seatOverlays = assets?.seatOverlays {
                TimelineView(.animation(paused: !hasActiveSeatThermal)) { timeline in
                    let t = Float(timeline.date.timeIntervalSince(shaderTimeStart))
                    ZStack {
                        ForEach(SeatRole.allCases) { role in
                            if let layer = seatOverlays[role] {
                                let heatLv = telemetry.heatingLevel(for: role)
                                let ventLv = telemetry.ventilationLevel(for: role)
                                if heatLv > 0, let hImg = layer.heatingImages[heatLv] {
                                    Image(uiImage: hImg)
                                        .resizable()
                                        .scaledToFit()
                                        .colorEffect(ShaderLibrary.seatThermalGlow(.float(1.0), .float(Float(heatLv) / 3.0), .float(t)))
                                } else if ventLv > 0, let vImg = layer.ventilationImages[ventLv] {
                                    Image(uiImage: vImg)
                                        .resizable()
                                        .scaledToFit()
                                        .colorEffect(ShaderLibrary.seatThermalGlow(.float(0.0), .float(Float(ventLv) / 3.0), .float(t)))
                                }

                                if case .seat(let selRole) = selectedTarget,
                                   selRole == role,
                                   let outline = layer.outlineImage {
                                    Image(uiImage: outline)
                                        .resizable()
                                        .scaledToFit()
                                }
                            }
                        }
                    }
                }
            }

            // 方向盘加热柔光呼吸叠加与选中框
            if telemetry.steeringWheelHeatingLevel > 0, let wheelHeat = assets?.wheelHeatImage {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(shaderTimeStart)
                    let baseAlpha: Double = telemetry.steeringWheelHeatingLevel >= 2 ? 0.92 : 0.60
                    let pulse = 0.85 + 0.15 * sin(elapsed * 2.8)
                    Image(uiImage: wheelHeat)
                        .resizable()
                        .scaledToFit()
                        .opacity(baseAlpha * pulse)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: telemetry.acOn)
        .animation(.easeInOut(duration: 0.45), value: telemetry.activeClimateMode)
        .animation(.easeInOut(duration: 0.30), value: telemetry.steeringWheelHeatingLevel)
    }

    /// 归一化坐标系内的方向盘选中框 + 左右外后视镜加热热晕与选中框
    @ViewBuilder
    private func mirrorStatusOverlay(
        assets: LoadedCarAssets,
        uiScale: CGFloat,
        palette: LingpaoPalette
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if case .steeringWheel = selectedTarget,
               let wheelRect = assets.steeringWheelRect {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.good, lineWidth: 1.8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.good.opacity(0.12))
                    )
                    .frame(width: (wheelRect.width + 6) * uiScale, height: (wheelRect.height + 6) * uiScale)
                    .position(x: wheelRect.midX * uiScale, y: wheelRect.midY * uiScale)
            }

            let mirrorRects = [assets.leftMirrorRect, assets.rightMirrorRect].compactMap { $0 }
            if !mirrorRects.isEmpty && (telemetry.rearMirrorHeatingOn || selectedTarget == .mirrors) {
                TimelineView(.animation(paused: !telemetry.rearMirrorHeatingOn)) { timeline in
                    let pulse = telemetry.rearMirrorHeatingOn
                        ? (0.72 + 0.28 * sin(timeline.date.timeIntervalSince(shaderTimeStart) * 3.0))
                        : 1.0
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(mirrorRects.enumerated()), id: \.offset) { _, mRect in
                            ZStack {
                                if telemetry.rearMirrorHeatingOn {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            RadialGradient(
                                                colors: [Color(hex: 0xFF8A38).opacity(0.70), Color(hex: 0xE06020).opacity(0.05)],
                                                center: .center,
                                                startRadius: 2,
                                                endRadius: 20 * uiScale
                                            )
                                        )
                                        .opacity(pulse)
                                }

                                if selectedTarget == .mirrors {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(palette.good, lineWidth: 1.6)
                                }
                            }
                            .frame(width: max((mRect.width + 6) * uiScale, 26), height: max((mRect.height + 6) * uiScale, 24))
                            .position(x: mRect.midX * uiScale, y: mRect.midY * uiScale)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var airflowModeFloat: Float {
        switch telemetry.activeClimateMode {
        case .off, .cool: return 0.0
        case .quickCool: return 1.0
        case .heat, .quickHeat: return 2.0
        case .deodorize: return 3.0
        case .defrost: return 4.0
        }
    }

    private var hasActiveSeatThermal: Bool {
        telemetry.driverSeatHeating > 0 || telemetry.driverSeatVentilation > 0
            || telemetry.passengerSeatHeating > 0 || telemetry.passengerSeatVentilation > 0
            || telemetry.leftRearSeatHeating > 0 || telemetry.leftRearSeatVentilation > 0
            || telemetry.rightRearSeatHeating > 0 || telemetry.rightRearSeatVentilation > 0
    }

    /// 精确对齐并带 44pt+ 安全触控容错的座舱多部件热区（座椅 + 方向盘 + 左右后视镜）
    @ViewBuilder
    private func cabinHitTargets(
        assets: LoadedCarAssets,
        logicalW: CGFloat,
        logicalH: CGFloat,
        uiScale: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(assets.seatRects.keys).sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { role in
                if let rect = assets.seatRects[role] {
                    let hitW = max(rect.width * uiScale + 4, 44)
                    let hitH = max(rect.height * uiScale + 4, 44)
                    Button {
                        onSelectTarget(.seat(role))
                    } label: {
                        Color.white.opacity(0.001)
                            .frame(width: hitW, height: hitH)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: rect.midX * uiScale, y: rect.midY * uiScale)
                    .accessibilityLabel("选择\(role.displayName)")
                    .accessibilityIdentifier("hit_seat_\(role.rawValue)")
                }
            }

            if let wheelRect = assets.steeringWheelRect {
                let hitW = max(wheelRect.width * uiScale + 10, 44)
                let hitH = max(wheelRect.height * uiScale + 10, 44)
                Button {
                    onSelectTarget(.steeringWheel)
                } label: {
                    Color.white.opacity(0.001)
                        .frame(width: hitW, height: hitH)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: wheelRect.midX * uiScale, y: wheelRect.midY * uiScale)
                .accessibilityLabel("选择方向盘")
                .accessibilityIdentifier("hit_steering_wheel")
            }

            if let leftMirror = assets.leftMirrorRect {
                let hitW = max(leftMirror.width * uiScale + 14, 44)
                let hitH = max(leftMirror.height * uiScale + 14, 44)
                Button {
                    onSelectTarget(.mirrors)
                } label: {
                    Color.white.opacity(0.001)
                        .frame(width: hitW, height: hitH)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: leftMirror.midX * uiScale, y: leftMirror.midY * uiScale)
                .accessibilityLabel("选择左后视镜")
                .accessibilityIdentifier("hit_mirror_left")
            }

            if let rightMirror = assets.rightMirrorRect {
                let hitW = max(rightMirror.width * uiScale + 14, 44)
                let hitH = max(rightMirror.height * uiScale + 14, 44)
                Button {
                    onSelectTarget(.mirrors)
                } label: {
                    Color.white.opacity(0.001)
                        .frame(width: hitW, height: hitH)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: rightMirror.midX * uiScale, y: rightMirror.midY * uiScale)
                .accessibilityLabel("选择右后视镜")
                .accessibilityIdentifier("hit_mirror_right")
            }
        }
        .frame(width: logicalW, height: logicalH, alignment: .topLeading)
    }

    @ViewBuilder
    private func tirePressureBadges(
        assets: LoadedCarAssets,
        transform: CarNormalizeTransform,
        logicalW: CGFloat,
        logicalH: CGFloat,
        uiScale: CGFloat,
        palette: LingpaoPalette
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(assets.wheels, id: \.label) { wheel in
                let pressureInfo = tireValueAndAlert(for: wheel.label)
                if let kpa = pressureInfo.kpa {
                    let normX = (wheel.nx * CarCanvasMetrics.logicalWidth) * transform.scale + transform.offsetX
                    let normY = (wheel.ny * CarCanvasMetrics.logicalHeight) * transform.scale + transform.offsetY
                    let isLeft = wheel.label.contains("左")
                    // 依据屏幕内外安全边距约束中心点，防止左压指标卡或右越出画布
                    let centerX = isLeft
                        ? max(12.0, normX - 8.0) * uiScale
                        : min(CarCanvasMetrics.logicalWidth - 24.0, normX) * uiScale

                    Text("\(Int(kpa.rounded()))")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(pressureInfo.alert ? palette.danger : palette.secondary)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(palette.card.opacity(0.92))
                                .overlay(
                                    Capsule()
                                        .stroke(palette.line.opacity(0.9), lineWidth: 0.8)
                                )
                        )
                        .fixedSize()
                        .position(x: centerX, y: normY * uiScale)
                }
            }
        }
        .frame(width: logicalW, height: logicalH, alignment: .topLeading)
    }

    private func tireValueAndAlert(for label: String) -> (kpa: Double?, alert: Bool) {
        switch label {
        case "左前": return (telemetry.leftFrontTirePressure, telemetry.leftFrontTireAlert)
        case "右前": return (telemetry.rightFrontTirePressure, telemetry.rightFrontTireAlert)
        case "左后": return (telemetry.leftRearTirePressure, telemetry.leftRearTireAlert)
        case "右后": return (telemetry.rightRearTirePressure, telemetry.rightRearTireAlert)
        default: return (nil, false)
        }
    }
}
