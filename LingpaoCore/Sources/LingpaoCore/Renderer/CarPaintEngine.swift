import Foundation

/// 车模核心像素着色、W3C 皮革混色、2.5px 内部高斯羽化与包围盒扫描纯 Swift 算法引擎
/// 精确对齐 `C2210sg0`（车漆着染）与 `AbstractC1765nD`（座椅热区 & W3C Color/Screen）
public enum CarPaintEngine {
    // MARK: - 1. 金属车漆 Rec.709 分段高光保留着色算法

    /// 计算单个 RGBA 像素经金属车漆着染后的结果（`maskWeight` 取自 `paint_mask.png` 归一化到 `[0, 1]`）
    @inline(__always)
    public static func shadeMetallicPaintPixel(
        srcR: UInt8,
        srcG: UInt8,
        srcB: UInt8,
        srcA: UInt8,
        maskWeight: Float,
        targetR: UInt8,
        targetG: UInt8,
        targetB: UInt8
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        if srcA == 0 || maskWeight <= 0.0 {
            return (srcR, srcG, srcB, srcA)
        }
        let lum = (0.2126 * Float(srcR) + 0.7152 * Float(srcG) + 0.0722 * Float(srcB)) / 255.0
        let fN = min(lum / 0.65, 1.0)
        let fQ = min(max((lum - 0.65) / 0.35, 0.0), 1.0)
        let f3 = fQ * fQ * 0.65

        let outR = shadeChannel(src: srcR, target: Float(targetR) / 255.0, fN: fN, f3: f3, mask: maskWeight)
        let outG = shadeChannel(src: srcG, target: Float(targetG) / 255.0, fN: fN, f3: f3, mask: maskWeight)
        let outB = shadeChannel(src: srcB, target: Float(targetB) / 255.0, fN: fN, f3: f3, mask: maskWeight)
        return (outR, outG, outB, srcA)
    }

    @inline(__always)
    private static func shadeChannel(src: UInt8, target: Float, fN: Float, f3: Float, mask: Float) -> UInt8 {
        let base = target * fN
        let shaded = (((1.0 - base) * f3) + base) * 255.0
        let s = Float(src)
        let blended = Int((s + (shaded - s) * mask).rounded())
        return UInt8(min(max(blended, 0), 255))
    }

    /// 对整张 RGBA8888 车图执行 CPU 兜底金属车漆着染（真机主路径使用 Metal Compute Kernel 加速）
    public static func applyMetallicPaintRGBA(
        sourceRGBA: [UInt8],
        maskRGBA: [UInt8],
        paintColor: PaintColor
    ) -> [UInt8] {
        guard sourceRGBA.count == maskRGBA.count, sourceRGBA.count % 4 == 0 else {
            return sourceRGBA
        }
        let tR = UInt8((paintColor.argb >> 16) & 0xFF)
        let tG = UInt8((paintColor.argb >> 8) & 0xFF)
        let tB = UInt8(paintColor.argb & 0xFF)

        var out = sourceRGBA
        for offset in stride(from: 0, to: sourceRGBA.count, by: 4) {
            // 灰度蒙版 B/G/R 任取低通道（原版取 iArr2[i] & 255）
            let maskWeight = Float(maskRGBA[offset + 2]) / 255.0
            if maskWeight > 0 {
                let res = shadeMetallicPaintPixel(
                    srcR: sourceRGBA[offset],
                    srcG: sourceRGBA[offset + 1],
                    srcB: sourceRGBA[offset + 2],
                    srcA: sourceRGBA[offset + 3],
                    maskWeight: maskWeight,
                    targetR: tR,
                    targetG: tG,
                    targetB: tB
                )
                out[offset] = res.r
                out[offset + 1] = res.g
                out[offset + 2] = res.b
                out[offset + 3] = res.a
            }
        }
        return out
    }

    // MARK: - 2. W3C Color 混合 + Screen 高光算法（座椅加热/通风 & 空调氛围）

    public struct ThermalBlendParams: Equatable, Sendable {
        public let colorARGB: UInt32
        public let colorStrength: Float
        public let screenARGB: UInt32
        public let screenStrength: Float

        public static func seatHeating(level: Int) -> ThermalBlendParams {
            let lv = Float(min(max(level, 1), 3))
            return ThermalBlendParams(
                colorARGB: 0xFFE0793A,
                colorStrength: 0.20 + 0.08 * lv,
                screenARGB: 0xFFFF9A55,
                screenStrength: 0.05 + 0.03 * lv
            )
        }

        public static func seatVentilation(level: Int) -> ThermalBlendParams {
            let lv = Float(min(max(level, 1), 3))
            return ThermalBlendParams(
                colorARGB: 0xFF287DEB,
                colorStrength: 0.32 + 0.16 * lv,
                screenARGB: 0xFF65A9FF,
                screenStrength: 0.04 + 0.04 * lv
            )
        }

        public static let cabinCoolAirflow = ThermalBlendParams(
            colorARGB: 0xFF5E95F0,
            colorStrength: 0.38,
            screenARGB: 0xFFA9C8FF,
            screenStrength: 0.07
        )
    }

    /// 精确实现 `AbstractC1765nD.O` W3C Color + Screen 皮革着色公式
    @inline(__always)
    public static func blendW3CColorAndScreenPixel(
        srcR: UInt8,
        srcG: UInt8,
        srcB: UInt8,
        srcA: UInt8,
        featherAlpha: Float,
        params: ThermalBlendParams
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let sR = Float(srcR) / 255.0
        let sG = Float(srcG) / 255.0
        let sB = Float(srcB) / 255.0
        let lumSrc = 0.2126 * sR + 0.7152 * sG + 0.0722 * sB

        var tR = Float((params.colorARGB >> 16) & 0xFF) / 255.0
        var tG = Float((params.colorARGB >> 8) & 0xFF) / 255.0
        var tB = Float(params.colorARGB & 0xFF) / 255.0
        let lumTarget = 0.2126 * tR + 0.7152 * tG + 0.0722 * tB

        let dL = lumSrc - lumTarget
        tR += dL; tG += dL; tB += dL

        // W3C clip-color 色度裁切回缩
        let l = 0.2126 * tR + 0.7152 * tG + 0.0722 * tB
        let cMin = min(tR, min(tG, tB))
        let cMax = max(tR, max(tG, tB))
        if cMin < 0.0 && (l - cMin) > 1e-6 {
            let factor = l / (l - cMin)
            tR = l + (tR - l) * factor
            tG = l + (tG - l) * factor
            tB = l + (tB - l) * factor
        }
        if cMax > 1.0 && (cMax - l) > 1e-6 {
            let factor = (1.0 - l) / (cMax - l)
            tR = l + (tR - l) * factor
            tG = l + (tG - l) * factor
            tB = l + (tB - l) * factor
        }

        let scR = Float((params.screenARGB >> 16) & 0xFF) / 255.0
        let scG = Float((params.screenARGB >> 8) & 0xFF) / 255.0
        let scB = Float(params.screenARGB & 0xFF) / 255.0

        func mixAndScreen(_ src: Float, _ colorComp: Float, _ screenComp: Float) -> UInt8 {
            let mixed = src + (colorComp - src) * params.colorStrength
            let screened = min(max(mixed + (1.0 - mixed) * screenComp * params.screenStrength, 0.0), 1.0)
            return UInt8(min(max(Int(screened * 255.0 + 0.5), 0), 255))
        }

        let outAlpha = UInt8(min(max(Int((Float(srcA) * featherAlpha).rounded()), 0), 255))
        return (
            mixAndScreen(sR, tR, scR),
            mixAndScreen(sG, tG, scG),
            mixAndScreen(sB, tB, scB),
            outAlpha
        )
    }

    // MARK: - 3. 17×17 可分离高斯内部羽化与热区/包围盒扫描

    /// 生成标准 `sigma = 2.5`、半径 8 的 17 阶归一化高斯核权重
    public static func makeFeatherKernel(radius: Int = 8, sigma: Float = 2.5) -> [Float] {
        let twoSigmaSq = 2.0 * sigma * sigma
        var kernel = [Float]()
        var sum: Float = 0
        for d in (-radius)...radius {
            let w = exp(-(Float(d * d)) / twoSigmaSq)
            kernel.append(w)
            sum += w
        }
        return kernel.map { $0 / sum }
    }

    /// 对二值座椅蒙版执行 **严格限制在标签内部** 的可分离高斯羽化（外部像素强置 `0`）
    public static func applyInteriorGaussianFeather(
        mask: [Float],
        width: Int,
        height: Int,
        radius: Int = 8,
        sigma: Float = 2.5
    ) -> [Float] {
        guard width > 0, height > 0, mask.count == width * height else { return mask }
        let kernel = makeFeatherKernel(radius: radius, sigma: sigma)
        var horiz = [Float](repeating: 0, count: mask.count)

        for y in 0..<height {
            let rowStart = y * width
            for x in 0..<width {
                if mask[rowStart + x] <= 0 { continue }
                var acc: Float = 0
                for k in (-radius)...radius {
                    let sx = min(max(x + k, 0), width - 1)
                    acc += mask[rowStart + sx] * kernel[k + radius]
                }
                horiz[rowStart + x] = acc
            }
        }

        var out = [Float](repeating: 0, count: mask.count)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if mask[idx] <= 0 {
                    out[idx] = 0
                    continue
                }
                var acc: Float = 0
                for k in (-radius)...radius {
                    let sy = min(max(y + k, 0), height - 1)
                    acc += horiz[sy * width + x] * kernel[k + radius]
                }
                out[idx] = min(max(acc, 0), 1)
            }
        }
        return out
    }

    /// 扫描图像 RGBA 缓冲获取非透明（`alpha > 0`）最小外接像素矩形
    public static func scanNonTransparentBounds(rgba: [UInt8], width: Int, height: Int) -> NormalizedRect? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let alpha = rgba[(y * width + x) * 4 + 3]
                if alpha > 0 {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return NormalizedRect(
            x: Double(minX),
            y: Double(minY),
            width: Double(maxX - minX + 1),
            height: Double(maxY - minY + 1)
        )
    }

    /// 从 `seat_labels*.png` 的单通道/RGBA 像素缓冲扫描座椅 `1..8` 像素矩形与逻辑画布映射热区
    public static func scanSeatRegions(
        labelRGBA: [UInt8],
        width: Int,
        height: Int,
        transform: CarNormalizeTransform
    ) -> [SeatRole: (pixelBounds: (minX: Int, minY: Int, maxX: Int, maxY: Int), logicalRect: NormalizedRect)] {
        guard width > 0, height > 0, labelRGBA.count >= width * height * 4 else { return [:] }
        var minXs = [Int](repeating: width, count: 9)
        var minYs = [Int](repeating: height, count: 9)
        var maxXs = [Int](repeating: 0, count: 9)
        var maxYs = [Int](repeating: 0, count: 9)

        for y in 0..<height {
            for x in 0..<width {
                // label PNG 可能为灰度图或 RGB，取红色通道（灰度 R=G=B）且仅统计 alpha > 0 或非背景
                let idx = (y * width + x) * 4
                let label = Int(labelRGBA[idx])
                if label >= 1 && label < 9 {
                    if x < minXs[label] { minXs[label] = x }
                    if y < minYs[label] { minYs[label] = y }
                    if x + 1 > maxXs[label] { maxXs[label] = x + 1 }
                    if y + 1 > maxYs[label] { maxYs[label] = y + 1 }
                }
            }
        }

        var result: [SeatRole: (pixelBounds: (minX: Int, minY: Int, maxX: Int, maxY: Int), logicalRect: NormalizedRect)] = [:]
        for role in SeatRole.allCases {
            let tag = role.rawValue
            if maxXs[tag] > minXs[tag] && maxYs[tag] > minYs[tag] {
                let rawRect = NormalizedRect(
                    x: Double(minXs[tag]) * CarCanvasMetrics.logicalWidth / Double(width),
                    y: Double(minYs[tag]) * CarCanvasMetrics.logicalHeight / Double(height),
                    width: Double(maxXs[tag] - minXs[tag]) * CarCanvasMetrics.logicalWidth / Double(width),
                    height: Double(maxYs[tag] - minYs[tag]) * CarCanvasMetrics.logicalHeight / Double(height)
                )
                result[role] = (
                    pixelBounds: (minXs[tag], minYs[tag], maxXs[tag], maxYs[tag]),
                    logicalRect: transform.apply(to: rawRect)
                )
            }
        }
        return result
    }
}
