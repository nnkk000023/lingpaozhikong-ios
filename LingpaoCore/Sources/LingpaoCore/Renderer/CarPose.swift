import Foundation

/// 车模舞台逻辑画布与归一化变换参数（精确对齐 `CarPose` / `C2535wf` / `C0657Ze`）
public enum CarCanvasMetrics {
    public static let logicalWidth: Double = 240.0
    public static let logicalHeight: Double = 560.0
    public static let targetX: Double = 13.3
    public static let targetY: Double = 9.6
    public static let targetWidth: Double = 213.4
    public static let targetHeight: Double = 547.0
    public static let horizontalCenter: Double = 120.0
}

/// 主导航/二级页状态
public enum AppStageRoute: String, Codable, CaseIterable, Hashable, Sendable {
    case home
    case car
    case route
    case user
    case charge
}

/// 逻辑矩形（不依赖 CoreGraphics，便于纯 Swift 跨平台计算与测试）
public struct NormalizedRect: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2.0 }
    public var midY: Double { y + height / 2.0 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= maxX && py >= y && py <= maxY
    }
}

/// 车模归一化偏移与缩放矩阵（精确对齐 `C0657Ze`）
public struct CarNormalizeTransform: Equatable, Sendable {
    public var offsetX: Double
    public var offsetY: Double
    public var scale: Double

    public static let identity = CarNormalizeTransform(offsetX: 0, offsetY: 0, scale: 1)

    public init(offsetX: Double, offsetY: Double, scale: Double) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
    }

    public func apply(to rect: NormalizedRect) -> NormalizedRect {
        NormalizedRect(
            x: rect.x * scale + offsetX,
            y: rect.y * scale + offsetY,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// 根据图像像素非透明包围盒计算归一化到 `213.4 × 547.0` 逻辑画布的 `CarNormalizeTransform`
    public static func compute(
        nonTransparentPixelBounds: NormalizedRect,
        imagePixelWidth: Int,
        imagePixelHeight: Int
    ) -> CarNormalizeTransform {
        guard imagePixelWidth > 0, imagePixelHeight > 0,
              nonTransparentPixelBounds.width > 0, nonTransparentPixelBounds.height > 0 else {
            return .identity
        }
        let pw = Double(imagePixelWidth)
        let ph = Double(imagePixelHeight)
        let logicalBoundsW = (nonTransparentPixelBounds.width * CarCanvasMetrics.logicalWidth) / pw
        let logicalBoundsH = (nonTransparentPixelBounds.height * CarCanvasMetrics.logicalHeight) / ph
        let logicalBoundsX = (nonTransparentPixelBounds.x * CarCanvasMetrics.logicalWidth) / pw
        let logicalBoundsY = (nonTransparentPixelBounds.y * CarCanvasMetrics.logicalHeight) / ph

        let scale = min(CarCanvasMetrics.targetWidth / logicalBoundsW, CarCanvasMetrics.targetHeight / logicalBoundsH)
        let offsetX = CarCanvasMetrics.horizontalCenter - (((logicalBoundsW / 2.0) + logicalBoundsX) * scale)
        let offsetY = CarCanvasMetrics.targetY - (logicalBoundsY * scale)
        return CarNormalizeTransform(offsetX: offsetX, offsetY: offsetY, scale: scale)
    }
}

/// 页面共享车模姿态参数（精确对应 `C2535wf`）
public struct CarPose: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var scale: Double
    public var exteriorAlpha: Double
    public var interiorAlpha: Double
    public var chargeBarAlpha: Double

    public init(
        x: Double,
        y: Double,
        scale: Double,
        exteriorAlpha: Double,
        interiorAlpha: Double,
        chargeBarAlpha: Double
    ) {
        self.x = x
        self.y = y
        self.scale = scale
        self.exteriorAlpha = exteriorAlpha
        self.interiorAlpha = interiorAlpha
        self.chargeBarAlpha = chargeBarAlpha
    }

    /// 根据当前页面与车型返回标准共享姿态（与安卓原版保持一致，包含 C16 专属控车位姿）
    public static func pose(for stage: AppStageRoute, modelId: String) -> CarPose {
        let lowerModel = modelId.lowercased()
        switch stage {
        case .home:
            // 向左微收并缩放至 0.93，完整露出车身右侧及四轮胎压胶囊
            return CarPose(x: 196, y: 92, scale: 0.93, exteriorAlpha: 1, interiorAlpha: 0, chargeBarAlpha: 0)
        case .car:
            if lowerModel == "c16" {
                return CarPose(x: 75, y: 18.4, scale: 1.0, exteriorAlpha: 0, interiorAlpha: 1, chargeBarAlpha: 0)
            }
            return CarPose(x: 63, y: -30, scale: 1.10, exteriorAlpha: 0, interiorAlpha: 1, chargeBarAlpha: 0)
        case .charge:
            // 上半区紧凑缩放 0.70 完整露出充电姿态车辆，去掉侧边竖向绿条
            return CarPose(x: 214, y: 74, scale: 0.70, exteriorAlpha: 1, interiorAlpha: 0, chargeBarAlpha: 0)
        case .route:
            return CarPose(x: 239, y: 176, scale: 0.075, exteriorAlpha: 1, interiorAlpha: 0, chargeBarAlpha: 0)
        case .user:
            return CarPose(x: 430, y: 94, scale: 0.97, exteriorAlpha: 1, interiorAlpha: 0, chargeBarAlpha: 0)
        }
    }
}
