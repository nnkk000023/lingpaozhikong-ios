import Foundation
import ImageIO
import LingpaoCore
import Metal
import UIKit

/// 车轮归一化位置点
public struct WheelAnchor: Equatable, Hashable, Sendable {
    public let label: String
    public let nx: Double
    public let ny: Double
}

/// 单车型加载与着色后的完整渲染资产包
public final class LoadedCarAssets: @unchecked Sendable {
    public let modelId: String
    public let layout: SeatLayout
    public let paintColor: PaintColor
    public let exteriorImage: UIImage?
    public let exteriorFoldedMirrorsImage: UIImage?
    public let interiorImage: UIImage?
    public let lightsGlowImage: UIImage?
    public let wheelHeatImage: UIImage?
    public let cabinCoolOverlay: UIImage?
    public let cabinWarmOverlay: UIImage?
    public let airflowMaskImage: UIImage?
    public let seatOverlays: [SeatRole: SeatRenderLayer]
    public let seatRects: [SeatRole: NormalizedRect]
    public let steeringWheelRect: NormalizedRect?
    public let leftMirrorRect: NormalizedRect?
    public let rightMirrorRect: NormalizedRect?
    public let wheels: [WheelAnchor]
    public let normalizeTransform: CarNormalizeTransform

    public init(
        modelId: String,
        layout: SeatLayout,
        paintColor: PaintColor,
        exteriorImage: UIImage?,
        exteriorFoldedMirrorsImage: UIImage?,
        interiorImage: UIImage?,
        lightsGlowImage: UIImage?,
        wheelHeatImage: UIImage?,
        cabinCoolOverlay: UIImage?,
        cabinWarmOverlay: UIImage? = nil,
        airflowMaskImage: UIImage? = nil,
        seatOverlays: [SeatRole: SeatRenderLayer],
        seatRects: [SeatRole: NormalizedRect],
        steeringWheelRect: NormalizedRect? = nil,
        leftMirrorRect: NormalizedRect? = nil,
        rightMirrorRect: NormalizedRect? = nil,
        wheels: [WheelAnchor],
        normalizeTransform: CarNormalizeTransform
    ) {
        self.modelId = modelId
        self.layout = layout
        self.paintColor = paintColor
        self.exteriorImage = exteriorImage
        self.exteriorFoldedMirrorsImage = exteriorFoldedMirrorsImage
        self.interiorImage = interiorImage
        self.lightsGlowImage = lightsGlowImage
        self.wheelHeatImage = wheelHeatImage
        self.cabinCoolOverlay = cabinCoolOverlay
        self.cabinWarmOverlay = cabinWarmOverlay
        self.airflowMaskImage = airflowMaskImage
        self.seatOverlays = seatOverlays
        self.seatRects = seatRects
        self.steeringWheelRect = steeringWheelRect
        self.leftMirrorRect = leftMirrorRect
        self.rightMirrorRect = rightMirrorRect
        self.wheels = wheels
        self.normalizeTransform = normalizeTransform
    }
}

/// 单个座椅预渲染状态贴图组（选中轮廓 + 加热 1~3 档 + 通风 1~3 档）
public struct SeatRenderLayer: @unchecked Sendable {
    public let outlineImage: UIImage?
    public let heatingImages: [Int: UIImage]
    public let ventilationImages: [Int: UIImage]
}

/// GPU（Metal Compute Shader）+ CPU 兜底车模资产加载与动态着染引擎（带内存缓存）
public final class CarAssetLoader: @unchecked Sendable {
    public static let shared = CarAssetLoader()

    private let cache = NSCache<NSString, LoadedCarAssets>()
    private let heroThumbCache = NSCache<NSString, UIImage>()
    private let mtlDevice: MTLDevice?
    private let mtlQueue: MTLCommandQueue?
    private let paintPipeline: MTLComputePipelineState?

    private init() {
        cache.countLimit = 8
        heroThumbCache.countLimit = 32
        let device = MTLCreateSystemDefaultDevice()
        self.mtlDevice = device
        self.mtlQueue = device?.makeCommandQueue()
        if let device,
           let lib = device.makeDefaultLibrary(),
           let fn = lib.makeFunction(name: "metallicPaintTint") {
            self.paintPipeline = try? device.makeComputePipelineState(function: fn)
        } else {
            self.paintPipeline = nil
        }
    }

    /// 加载登录页 3/4 主车图（可选按车漆 ID 动态着染）
    public func loadHero3QImage(for carType: String?, paintId: String? = nil) -> UIImage? {
        let profile = CarModelCatalog.profile(for: carType)
        if let cg = decodeHero3QCGImage(for: profile, paintId: paintId, maxDimension: 1200) {
            return UIImage(cgImage: cg)
        }
        if let fallback = assetURL(subpath: "hero/c16_3q.webp"),
           let cg = decodeCGImage(at: fallback, maxDimension: 1200) {
            return UIImage(cgImage: cg)
        }
        return nil
    }

    /// 异步加载并着染 3/4 实车缩略图（带 32 条内存缓存，专用于多车车库与 12 款展厅列表）
    public func loadHeroThumbnail(for carType: String?, paintId: String? = nil) async -> UIImage? {
        let profile = CarModelCatalog.profile(for: carType)
        let resolvedPaintId: String = {
            guard let paintId, !paintId.isEmpty else { return "default" }
            return PaintCatalog.resolvePaint(id: paintId, carTypeOrId: profile.displayName).id
        }()
        let cacheKey = "\(profile.id)|\(resolvedPaintId)" as NSString
        if let cached = heroThumbCache.object(forKey: cacheKey) {
            return cached
        }

        let image = await Task.detached(priority: .utility) { [weak self] () -> UIImage? in
            guard let self,
                  let cg = self.decodeHero3QCGImage(for: profile, paintId: paintId, maxDimension: 360) else {
                return nil
            }
            return UIImage(cgImage: cg)
        }.value

        if let image {
            heroThumbCache.setObject(image, forKey: cacheKey)
        }
        return image
    }

    private func decodeHero3QCGImage(
        for profile: CarModelProfile,
        paintId: String?,
        maxDimension: CGFloat
    ) -> CGImage? {
        guard let url = assetURL(subpath: "\(profile.id)/hero_3q_transparent.webp"),
              let cg = decodeCGImage(at: url, maxDimension: maxDimension) else {
            return nil
        }

        if let paintId, !paintId.isEmpty {
            let paint = PaintCatalog.resolvePaint(id: paintId, carTypeOrId: profile.displayName)
            if paint.id != "default",
               let maskURL = assetURL(subpath: "\(profile.id)/paint_mask.png"),
               let maskCG = decodeCGImage(at: maskURL, maxDimension: maxDimension),
               let tinted = tintExteriorImage(source: cg, mask: maskCG, paint: paint) {
                return tinted
            }
        }
        return cg
    }

    /// 异步装载并着染整套车模图层（车漆使用 Metal Compute 并行计算）
    public func loadAssets(
        carType: String,
        paintId: String,
        seatLayout: SeatLayout?
    ) async -> LoadedCarAssets {
        let profile = CarModelCatalog.profile(for: carType)
        let layout = seatLayout ?? profile.defaultLayout
        let paint = PaintCatalog.resolvePaint(id: paintId, carTypeOrId: profile.displayName)
        let cacheKey = "\(profile.id)|\(layout.rawValue)|\(paint.id)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let assets = await Task.detached(priority: .userInitiated) { [weak self] () -> LoadedCarAssets in
            guard let self else {
                return LoadedCarAssets(
                    modelId: profile.id, layout: layout, paintColor: paint,
                    exteriorImage: nil, exteriorFoldedMirrorsImage: nil, interiorImage: nil,
                    lightsGlowImage: nil, wheelHeatImage: nil, cabinCoolOverlay: nil,
                    seatOverlays: [:], seatRects: [:], wheels: [], normalizeTransform: .identity
                )
            }
            return self.buildAssetsSynchronously(profile: profile, layout: layout, paint: paint)
        }.value

        cache.setObject(assets, forKey: cacheKey)
        return assets
    }

    private func buildAssetsSynchronously(
        profile: CarModelProfile,
        layout: SeatLayout,
        paint: PaintColor
    ) -> LoadedCarAssets {
        let suffix = profile.assetSuffix(for: layout)
        // 为兼顾手机内存，外饰主图按最大长边 1400px 解码（对应 700×1400 -> ~3.9MB RGBA）
        let maxDim: CGFloat = 1400

        let rawExtCG = assetURL(subpath: "\(profile.id)/exterior.webp").flatMap { decodeCGImage(at: $0, maxDimension: maxDim) }
        // 俯视车图 `exterior.webp` 必须配对 `paint_mask_top.png`（600×1400）；`paint_mask.png` 仅用于 3/4 主图
        let topMaskCG = assetURL(subpath: "\(profile.id)/paint_mask_top.png").flatMap { decodeCGImage(at: $0, maxDimension: maxDim) }

        let tintedExtCG: CGImage? = {
            guard let src = rawExtCG else { return nil }
            if paint.id == "default" { return src }
            guard let mask = topMaskCG else { return src }
            return tintExteriorImage(source: src, mask: mask, paint: paint) ?? src
        }()

        // 折叠后视镜补丁局部换色（仅保留差异部分叠加）
        let foldedCG = assetURL(subpath: "\(profile.id)/fx/exterior_mirrors_folded.webp").flatMap { decodeCGImage(at: $0, maxDimension: maxDim) }
        let tintedFoldedCG: CGImage? = {
            guard let baseExt = rawExtCG, let folded = foldedCG else { return nil }
            if paint.id == "default" { return folded }
            if let topMask = topMaskCG,
               let diffPatched = buildFoldedMirrorTint(baseExt: baseExt, foldedExt: folded, topMask: topMask, paint: paint) {
                return diffPatched
            }
            if let topMask = topMaskCG {
                return tintExteriorImage(source: folded, mask: topMask, paint: paint)
            }
            return folded
        }()

        // 内饰底图与边缘漆面着色
        let interiorName = suffix.isEmpty ? "interior.webp" : "interior\(suffix).webp"
        let rawIntCG = (assetURL(subpath: "\(profile.id)/\(interiorName)") ?? assetURL(subpath: "\(profile.id)/interior.webp"))
            .flatMap { decodeCGImage(at: $0, maxDimension: maxDim) }
        let intMaskName = suffix.isEmpty ? "paint_mask_interior.png" : "paint_mask_interior\(suffix).png"
        let intMaskCG = (assetURL(subpath: "\(profile.id)/\(intMaskName)") ?? assetURL(subpath: "\(profile.id)/paint_mask_interior.png"))
            .flatMap { decodeCGImage(at: $0, maxDimension: maxDim) }
        let tintedIntCG: CGImage? = {
            guard let src = rawIntCG else { return nil }
            if paint.id == "default" { return src }
            guard let mask = intMaskCG else { return src }
            return tintExteriorImage(source: src, mask: mask, paint: paint) ?? src
        }()

        // 计算非透明包围盒与规范变换矩阵
        var transform: CarNormalizeTransform = .identity
        if let refCG = tintedExtCG ?? tintedIntCG,
           let (rgba, w, h) = extractRGBA(refCG),
           let bounds = CarPaintEngine.scanNonTransparentBounds(rgba: rgba, width: w, height: h) {
            transform = CarNormalizeTransform.compute(nonTransparentPixelBounds: bounds, imagePixelWidth: w, imagePixelHeight: h)
        }

        // 解析车轮坐标 wheels.json
        let wheels = loadWheels(modelId: profile.id)

        // 加载 FX 特效（车灯 / 方向盘）
        let lightsImg = assetURL(subpath: "\(profile.id)/fx/lights_glow_only.webp")
            .flatMap { decodeCGImage(at: $0, maxDimension: maxDim) }.map { UIImage(cgImage: $0) }
        let wheelHeatImg = assetURL(subpath: "\(profile.id)/fx/wheel_heat.webp")
            .flatMap { decodeCGImage(at: $0, maxDimension: maxDim) }.map { UIImage(cgImage: $0) }

        // 解析座椅点击热区与 2.5px 内部羽化 W3C 加热/通风高亮图层（零插值最近邻读取原始离散标号，杜绝锯齿窜号）
        let seatRenderDim = 700
        let labelFile = suffix.isEmpty ? "seat_labels.png" : "seat_labels\(suffix).png"
        let labelURL = assetURL(subpath: "\(profile.id)/\(labelFile)") ?? assetURL(subpath: "\(profile.id)/seat_labels.png")

        var seatRects: [SeatRole: NormalizedRect] = [:]
        var seatOverlays: [SeatRole: SeatRenderLayer] = [:]

        if let labelURL,
           let (labelRGBA, lw, lh) = extractSeatLabelNearestRGBA(at: labelURL, targetMaxHeight: seatRenderDim) {
            let scanned = CarPaintEngine.scanSeatRegions(labelRGBA: labelRGBA, width: lw, height: lh, transform: transform)
            let intForSeatCG = rawIntCG.flatMap { resizeCGImage($0, targetWidth: lw, targetHeight: lh) }
            let intRGBA = intForSeatCG.flatMap { extractRGBA($0)?.0 }

            for (role, info) in scanned {
                seatRects[role] = info.logicalRect
                seatOverlays[role] = buildSeatRenderLayer(
                    role: role,
                    pixelBounds: info.pixelBounds,
                    labelRGBA: labelRGBA,
                    interiorRGBA: intRGBA,
                    width: lw,
                    height: lh
                )
            }
        }

        // 全舱空调氛围冷/暖双色图 + 流体出风口动画遮罩
        let cabinName = suffix.isEmpty ? "cabin_mask.png" : "cabin_mask\(suffix).png"
        let cabinMaskCG = (assetURL(subpath: "\(profile.id)/\(cabinName)") ?? assetURL(subpath: "\(profile.id)/cabin_mask.png"))
            .flatMap { decodeCGImage(at: $0, maxDimension: 560) }
        let cabinCoolOverlay = buildCabinTintOverlay(cabinMaskCG: cabinMaskCG, rgb: (94, 149, 240), strength: 0.42)
        let cabinWarmOverlay = buildCabinTintOverlay(cabinMaskCG: cabinMaskCG, rgb: (235, 139, 69), strength: 0.40)

        let airflowName = suffix.isEmpty ? "airflow_mask.png" : "airflow_mask\(suffix).png"
        let airflowCG = (assetURL(subpath: "\(profile.id)/\(airflowName)") ?? assetURL(subpath: "\(profile.id)/airflow_mask.png"))
            .flatMap { decodeCGImage(at: $0, maxDimension: 560) }
        let airflowMaskImage = buildAirflowAlphaImage(airflowMaskCG: airflowCG)

        // 方向盘与外后视镜点击热区扫描（按归一化矩阵映射至 240×560 逻辑画布）
        let wheelHeatCG = assetURL(subpath: "\(profile.id)/fx/wheel_heat.webp")
            .flatMap { decodeCGImage(at: $0, maxDimension: 560) }
        let steeringRect = scanSteeringWheelRect(wheelHeatCG: wheelHeatCG, transform: transform)
        let mirrorRects = scanMirrorRects(baseExt: rawExtCG, foldedExt: foldedCG, transform: transform)

        return LoadedCarAssets(
            modelId: profile.id,
            layout: layout,
            paintColor: paint,
            exteriorImage: tintedExtCG.map { UIImage(cgImage: $0) },
            exteriorFoldedMirrorsImage: tintedFoldedCG.map { UIImage(cgImage: $0) },
            interiorImage: tintedIntCG.map { UIImage(cgImage: $0) },
            lightsGlowImage: lightsImg,
            wheelHeatImage: wheelHeatImg,
            cabinCoolOverlay: cabinCoolOverlay,
            cabinWarmOverlay: cabinWarmOverlay,
            airflowMaskImage: airflowMaskImage,
            seatOverlays: seatOverlays,
            seatRects: seatRects,
            steeringWheelRect: steeringRect,
            leftMirrorRect: mirrorRects.left,
            rightMirrorRect: mirrorRects.right,
            wheels: wheels,
            normalizeTransform: transform
        )
    }

    // MARK: - Metal GPU 着色与 CPU 回退

    private func tintExteriorImage(source: CGImage, mask: CGImage, paint: PaintColor) -> CGImage? {
        guard source.width == mask.width, source.height == mask.height else {
            return tintExteriorCPU(source: source, mask: mask, paint: paint)
        }
        guard let pipeline = paintPipeline,
              let queue = mtlQueue,
              let srcTex = makeTexture(from: source),
              let maskTex = makeTexture(from: mask),
              let outTex = makeEmptyWritableTexture(width: source.width, height: source.height),
              let cmdBuf = queue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else {
            return tintExteriorCPU(source: source, mask: mask, paint: paint)
        }

        var rgb = SIMD3<Float>(Float(paint.red), Float(paint.green), Float(paint.blue))
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(srcTex, index: 0)
        encoder.setTexture(maskTex, index: 1)
        encoder.setTexture(outTex, index: 2)
        encoder.setBytes(&rgb, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)

        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        let tgSize = MTLSize(width: w, height: h, depth: 1)
        let tgCount = MTLSize(
            width: (source.width + w - 1) / w,
            height: (source.height + h - 1) / h,
            depth: 1
        )
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        return makeCGImage(from: outTex)
    }

    private func tintExteriorCPU(source: CGImage, mask: CGImage, paint: PaintColor) -> CGImage? {
        let alignedMask = (source.width == mask.width && source.height == mask.height)
            ? mask
            : resizeCGImage(mask, targetWidth: source.width, targetHeight: source.height)
        guard let alignedMask,
              let (srcBytes, w, h) = extractRGBA(source),
              let (maskBytes, _, _) = extractRGBA(alignedMask) else {
            return nil
        }
        let shaded = CarPaintEngine.applyMetallicPaintRGBA(sourceRGBA: srcBytes, maskRGBA: maskBytes, paintColor: paint)
        return cgImageFromRGBA(shaded, width: w, height: h)
    }

    private func buildFoldedMirrorTint(
        baseExt: CGImage,
        foldedExt: CGImage,
        topMask: CGImage,
        paint: PaintColor
    ) -> CGImage? {
        guard baseExt.width == foldedExt.width, baseExt.height == foldedExt.height else { return nil }
        guard let alignedMask = (topMask.width == foldedExt.width && topMask.height == foldedExt.height)
            ? topMask
            : resizeCGImage(topMask, targetWidth: foldedExt.width, targetHeight: foldedExt.height),
              let (baseBytes, w, h) = extractRGBA(baseExt),
              let (foldedBytes, _, _) = extractRGBA(foldedExt),
              let (maskBytes, _, _) = extractRGBA(alignedMask) else {
            return nil
        }

        // 根据差异门限提取折叠后视镜与原图差异蒙版并与 `paint_mask_top.png` 合并着染
        var combinedMask = [UInt8](repeating: 0, count: maskBytes.count)
        let pixelCount = w * h
        for i in 0..<pixelCount {
            let p = i * 4
            let a = foldedBytes[p + 3]
            if a >= 128 {
                let dR = abs(Int(foldedBytes[p]) - Int(baseBytes[p]))
                let dG = abs(Int(foldedBytes[p + 1]) - Int(baseBytes[p + 1]))
                let dB = abs(Int(foldedBytes[p + 2]) - Int(baseBytes[p + 2]))
                if max(dR, max(dG, dB)) > 24 {
                    let m = maskBytes[p + 2]
                    combinedMask[p] = m
                    combinedMask[p + 1] = m
                    combinedMask[p + 2] = m
                    combinedMask[p + 3] = 255
                }
            }
        }
        // 同时叠加 base mask 保障车身其他漆面一致
        if let baseTint = tintExteriorImage(source: foldedExt, mask: topMask, paint: paint),
           let (baseTintBytes, _, _) = extractRGBA(baseTint) {
            let mirrorTinted = CarPaintEngine.applyMetallicPaintRGBA(sourceRGBA: foldedBytes, maskRGBA: combinedMask, paintColor: paint)
            var merged = baseTintBytes
            for i in 0..<pixelCount {
                let p = i * 4
                if combinedMask[p + 2] > 0 {
                    merged[p] = mirrorTinted[p]
                    merged[p + 1] = mirrorTinted[p + 1]
                    merged[p + 2] = mirrorTinted[p + 2]
                    merged[p + 3] = mirrorTinted[p + 3]
                }
            }
            return cgImageFromRGBA(merged, width: w, height: h)
        }
        return nil
    }

    private func buildSeatRenderLayer(
        role: SeatRole,
        pixelBounds: (minX: Int, minY: Int, maxX: Int, maxY: Int),
        labelRGBA: [UInt8],
        interiorRGBA: [UInt8]?,
        width: Int,
        height: Int
    ) -> SeatRenderLayer {
        // 先提取整张图单座二值 mask 再仅在局部计算 2.5px 内部羽化
        let tag = UInt8(role.rawValue)
        var rawMask = [Float](repeating: 0, count: width * height)
        for y in pixelBounds.minY..<pixelBounds.maxY {
            for x in pixelBounds.minX..<pixelBounds.maxX {
                let idx = y * width + x
                if labelRGBA[idx * 4] == tag {
                    rawMask[idx] = 1.0
                }
            }
        }
        let feathered = CarPaintEngine.applyInteriorGaussianFeather(mask: rawMask, width: width, height: height, radius: 6, sigma: 2.5)

        // 选中白光轮廓（0.58 不透明度 * 羽化 Alpha）
        var outlineBytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) where feathered[i] > 0.001 {
            let p = i * 4
            let a = UInt8(min(max(Int((feathered[i] * 0.58 * 255.0).rounded()), 0), 255))
            outlineBytes[p] = 255
            outlineBytes[p + 1] = 255
            outlineBytes[p + 2] = 255
            outlineBytes[p + 3] = a
        }
        let outlineImage = cgImageFromRGBA(outlineBytes, width: width, height: height).map { UIImage(cgImage: $0) }

        var heatDict: [Int: UIImage] = [:]
        var ventDict: [Int: UIImage] = [:]
        if let interiorRGBA, interiorRGBA.count == width * height * 4 {
            for lv in 1...3 {
                let hParams = CarPaintEngine.ThermalBlendParams.seatHeating(level: lv)
                if let img = renderSeatThermal(interiorRGBA: interiorRGBA, feathered: feathered, width: width, height: height, params: hParams) {
                    heatDict[lv] = img
                }
                if role.controlPosition != nil {
                    let vParams = CarPaintEngine.ThermalBlendParams.seatVentilation(level: lv)
                    if let img = renderSeatThermal(interiorRGBA: interiorRGBA, feathered: feathered, width: width, height: height, params: vParams) {
                        ventDict[lv] = img
                    }
                }
            }
        }
        return SeatRenderLayer(outlineImage: outlineImage, heatingImages: heatDict, ventilationImages: ventDict)
    }

    private func renderSeatThermal(
        interiorRGBA: [UInt8],
        feathered: [Float],
        width: Int,
        height: Int,
        params: CarPaintEngine.ThermalBlendParams
    ) -> UIImage? {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let alpha = feathered[i]
            if alpha <= 0.001 { continue }
            let p = i * 4
            let res = CarPaintEngine.blendW3CColorAndScreenPixel(
                srcR: interiorRGBA[p],
                srcG: interiorRGBA[p + 1],
                srcB: interiorRGBA[p + 2],
                srcA: interiorRGBA[p + 3],
                featherAlpha: alpha,
                params: params
            )
            out[p] = res.r
            out[p + 1] = res.g
            out[p + 2] = res.b
            out[p + 3] = res.a
        }
        return cgImageFromRGBA(out, width: width, height: height).map { UIImage(cgImage: $0) }
    }

    private func buildCabinTintOverlay(
        cabinMaskCG: CGImage?,
        rgb: (UInt8, UInt8, UInt8),
        strength: Float
    ) -> UIImage? {
        guard let cabinMaskCG, let (bytes, w, h) = extractRGBA(cabinMaskCG) else { return nil }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let p = i * 4
            let weight = bytes[p + 2]
            if weight == 0 { continue }
            out[p] = rgb.0
            out[p + 1] = rgb.1
            out[p + 2] = rgb.2
            out[p + 3] = UInt8(min(255, Int(Float(weight) * strength)))
        }
        return cgImageFromRGBA(out, width: w, height: h).map { UIImage(cgImage: $0) }
    }

    /// 将单通道空调出风口流向遮罩转为纯白透明通道图层，以驱动 `cabinAirflowEffect` Metal 着色器
    private func buildAirflowAlphaImage(airflowMaskCG: CGImage?) -> UIImage? {
        guard let airflowMaskCG, let (bytes, w, h) = extractRGBA(airflowMaskCG) else { return nil }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let p = i * 4
            let luma = bytes[p]
            if luma < 4 { continue }
            out[p] = 255
            out[p + 1] = 255
            out[p + 2] = 255
            out[p + 3] = luma
        }
        return cgImageFromRGBA(out, width: w, height: h).map { UIImage(cgImage: $0) }
    }

    private func scanSteeringWheelRect(wheelHeatCG: CGImage?, transform: CarNormalizeTransform) -> NormalizedRect {
        let fallback = NormalizedRect(x: 62, y: 134, width: 40, height: 36)
        guard let wheelHeatCG,
              let (rgba, w, h) = extractRGBA(wheelHeatCG),
              let bounds = CarPaintEngine.scanNonTransparentBounds(rgba: rgba, width: w, height: h) else {
            return fallback
        }
        let raw = NormalizedRect(
            x: bounds.x * CarCanvasMetrics.logicalWidth / Double(w),
            y: bounds.y * CarCanvasMetrics.logicalHeight / Double(h),
            width: bounds.width * CarCanvasMetrics.logicalWidth / Double(w),
            height: bounds.height * CarCanvasMetrics.logicalHeight / Double(h)
        )
        return transform.apply(to: raw)
    }

    private func scanMirrorRects(
        baseExt: CGImage?,
        foldedExt: CGImage?,
        transform: CarNormalizeTransform
    ) -> (left: NormalizedRect, right: NormalizedRect) {
        let fallbackLeft = NormalizedRect(x: 14, y: 136, width: 32, height: 31)
        let fallbackRight = NormalizedRect(x: 194, y: 136, width: 32, height: 31)
        let w = 240
        let h = 560
        guard let baseExt, let foldedExt,
              let smallBase = resizeCGImage(baseExt, targetWidth: w, targetHeight: h),
              let smallFold = resizeCGImage(foldedExt, targetWidth: w, targetHeight: h),
              let (bBytes, _, _) = extractRGBA(smallBase),
              let (fBytes, _, _) = extractRGBA(smallFold) else {
            return (fallbackLeft, fallbackRight)
        }

        var lMinX = w, lMinY = h, lMaxX = -1, lMaxY = -1
        var rMinX = w, rMinY = h, rMaxX = -1, rMaxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let p = (y * w + x) * 4
                let a = max(bBytes[p + 3], fBytes[p + 3])
                guard a > 96 else { continue }
                let diff = max(
                    abs(Int(bBytes[p]) - Int(fBytes[p])),
                    max(abs(Int(bBytes[p + 1]) - Int(fBytes[p + 1])), abs(Int(bBytes[p + 2]) - Int(fBytes[p + 2])))
                )
                if diff > 28 {
                    if x < w / 2 {
                        lMinX = min(lMinX, x); lMinY = min(lMinY, y)
                        lMaxX = max(lMaxX, x); lMaxY = max(lMaxY, y)
                    } else {
                        rMinX = min(rMinX, x); rMinY = min(rMinY, y)
                        rMaxX = max(rMaxX, x); rMaxY = max(rMaxY, y)
                    }
                }
            }
        }

        let leftRect: NormalizedRect = (lMaxX >= lMinX && lMaxY >= lMinY)
            ? transform.apply(to: NormalizedRect(x: Double(lMinX), y: Double(lMinY), width: Double(lMaxX - lMinX + 1), height: Double(lMaxY - lMinY + 1)))
            : fallbackLeft
        let rightRect: NormalizedRect = (rMaxX >= rMinX && rMaxY >= rMinY)
            ? transform.apply(to: NormalizedRect(x: Double(rMinX), y: Double(rMinY), width: Double(rMaxX - rMinX + 1), height: Double(rMaxY - rMinY + 1)))
            : fallbackRight
        return (leftRect, rightRect)
    }

    // MARK: - 底层图片与 Metal 纹理编解码

    private func assetURL(subpath: String) -> URL? {
        let components = subpath.split(separator: "/").map(String.init)
        guard let fileName = components.last else { return nil }
        let dir = (["car"] + components.dropLast()).joined(separator: "/")
        if let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: dir) {
            return bundleURL
        }
        return nil
    }

    private func loadWheels(modelId: String) -> [WheelAnchor] {
        guard let url = assetURL(subpath: "\(modelId)/wheels.json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map = json["wheels"] as? [String: [Double]] else {
            return []
        }
        let order = ["左前", "右前", "左后", "右后"]
        return order.compactMap { key in
            guard let coords = map[key], coords.count >= 2 else { return nil }
            return WheelAnchor(label: key, nx: coords[0], ny: coords[1])
        }
    }

    private func decodeCGImage(at url: URL, maxDimension: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// 零插值最近邻提取离散座椅标号图（绕开 CoreGraphics 缩略图滤波与 Gamma 转换，避免产生跨区伪标号）
    private func extractSeatLabelNearestRGBA(at url: URL, targetMaxHeight: Int) -> ([UInt8], Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let rawCG = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let rawW = rawCG.width
        let rawH = rawCG.height
        guard rawW > 0, rawH > 0 else { return nil }

        let scale = min(1.0, Double(targetMaxHeight) / Double(max(rawW, rawH)))
        let dstW = max(1, Int((Double(rawW) * scale).rounded()))
        let dstH = max(1, Int((Double(rawH) * scale).rounded()))
        var outRGBA = [UInt8](repeating: 0, count: dstW * dstH * 4)

        // 优先路径：8-bit 单通道灰度标签图直接读取 DataProvider 裸字节，彻底跳过色彩空间转换与抗锯齿插值
        if rawCG.bitsPerComponent == 8,
           rawCG.bitsPerPixel == 8,
           let cfData = rawCG.dataProvider?.data,
           let ptr = CFDataGetBytePtr(cfData) {
            let totalLen = CFDataGetLength(cfData)
            let bpr = rawCG.bytesPerRow
            for y in 0..<dstH {
                let srcY = min(rawH - 1, ((2 * y + 1) * rawH) / (2 * dstH))
                let rowOffset = srcY * bpr
                for x in 0..<dstW {
                    let srcX = min(rawW - 1, ((2 * x + 1) * rawW) / (2 * dstW))
                    let byteIdx = rowOffset + srcX
                    let label: UInt8 = byteIdx < totalLen ? ptr[byteIdx] : 0
                    let dstIdx = (y * dstW + x) * 4
                    outRGBA[dstIdx] = label
                    outRGBA[dstIdx + 1] = label
                    outRGBA[dstIdx + 2] = label
                    outRGBA[dstIdx + 3] = 255
                }
            }
            return (outRGBA, dstW, dstH)
        }

        // 兜底路径：以原图色彩空间配合 .none 最近邻绘制重采样
        var rawBytes = [UInt8](repeating: 0, count: dstW * dstH * 4)
        guard let ctx = CGContext(
            data: &rawBytes,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: dstW * 4,
            space: rawCG.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .none
        ctx.draw(rawCG, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        return (rawBytes, dstW, dstH)
    }

    private func resizeCGImage(_ image: CGImage, targetWidth: Int, targetHeight: Int) -> CGImage? {
        guard targetWidth > 0, targetHeight > 0 else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return ctx.makeImage()
    }

    private func extractRGBA(_ image: CGImage) -> ([UInt8], Int, Int)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &bytes,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // 反预乘恢复直通 RGB，确保亮度与换色数学计算无黑边失真
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let a = Int(bytes[i + 3])
            if a > 0 && a < 255 {
                bytes[i] = UInt8(min(255, (Int(bytes[i]) * 255) / a))
                bytes[i + 1] = UInt8(min(255, (Int(bytes[i + 1]) * 255) / a))
                bytes[i + 2] = UInt8(min(255, (Int(bytes[i + 2]) * 255) / a))
            }
        }
        return (bytes, w, h)
    }

    private func cgImageFromRGBA(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard bytes.count == width * height * 4 else { return nil }
        var premul = bytes
        for i in stride(from: 0, to: premul.count, by: 4) {
            let a = Int(premul[i + 3])
            if a < 255 {
                premul[i] = UInt8((Int(premul[i]) * a) / 255)
                premul[i + 1] = UInt8((Int(premul[i + 1]) * a) / 255)
                premul[i + 2] = UInt8((Int(premul[i + 2]) * a) / 255)
            }
        }
        let data = Data(premul)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private func makeTexture(from cgImage: CGImage) -> MTLTexture? {
        guard let device = mtlDevice, let (rgba, w, h) = extractRGBA(cgImage) else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        rgba.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                tex.replace(
                    region: MTLRegionMake2D(0, 0, w, h),
                    mipmapLevel: 0,
                    withBytes: base,
                    bytesPerRow: w * 4
                )
            }
        }
        return tex
    }

    private func makeEmptyWritableTexture(width: Int, height: Int) -> MTLTexture? {
        guard let device = mtlDevice else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderWrite, .shaderRead]
        return device.makeTexture(descriptor: desc)
    }

    private func makeCGImage(from texture: MTLTexture) -> CGImage? {
        let w = texture.width, h = texture.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { ptr in
            if let base = ptr.baseAddress {
                texture.getBytes(
                    base,
                    bytesPerRow: w * 4,
                    from: MTLRegionMake2D(0, 0, w, h),
                    mipmapLevel: 0
                )
            }
        }
        return cgImageFromRGBA(bytes, width: w, height: h)
    }
}
