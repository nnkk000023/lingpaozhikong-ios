import XCTest
@testable import LingpaoCore

final class CarPaintEngineTests: XCTestCase {
    func testMetallicPaintPreservesTransparentPixelsAndBrightHighlights() {
        let trans = CarPaintEngine.shadeMetallicPaintPixel(
            srcR: 255, srcG: 255, srcB: 255, srcA: 0,
            maskWeight: 1.0, targetR: 40, targetG: 60, targetB: 120
        )
        XCTAssertEqual(trans.a, 0)
        XCTAssertEqual(trans.r, 255)

        // 纯白色高光区域（lum = 1.0），即使选深黑车漆也应保留约 0.65 高光反射
        let blackHighlight = CarPaintEngine.shadeMetallicPaintPixel(
            srcR: 255, srcG: 255, srcB: 255, srcA: 255,
            maskWeight: 1.0, targetR: 37, targetG: 40, targetB: 45
        )
        XCTAssertGreaterThan(blackHighlight.r, 150)

        // 蓝色涂装上色应偏向目标蓝色通道
        let blueMid = CarPaintEngine.shadeMetallicPaintPixel(
            srcR: 150, srcG: 150, srcB: 150, srcA: 255,
            maskWeight: 1.0, targetR: 54, targetG: 91, targetB: 145
        )
        XCTAssertGreaterThan(blueMid.b, blueMid.r)
    }

    func testInteriorFeatherRestrictsBlurStrictlyInsideMask() {
        let w = 9, h = 9
        var mask = [Float](repeating: 0, count: w * h)
        // 中间 3x3 为 1，外圈全部为 0
        for y in 3...5 {
            for x in 3...5 {
                mask[y * w + x] = 1.0
            }
        }
        let feathered = CarPaintEngine.applyInteriorGaussianFeather(mask: mask, width: w, height: h, radius: 4, sigma: 2.5)
        // 标签外部必须严格保持 0
        XCTAssertEqual(feathered[0], 0)
        XCTAssertEqual(feathered[2 * w + 4], 0)
        // 内部中心平滑后 > 0 且 <= 1
        XCTAssertGreaterThan(feathered[4 * w + 4], 0)
        XCTAssertLessThanOrEqual(feathered[4 * w + 4], 1.0)
    }

    func testW3CColorAndScreenHeatingShiftsHueWarm() {
        let params = CarPaintEngine.ThermalBlendParams.seatHeating(level: 3)
        let res = CarPaintEngine.blendW3CColorAndScreenPixel(
            srcR: 120, srcG: 120, srcB: 120, srcA: 255,
            featherAlpha: 0.8, params: params
        )
        XCTAssertGreaterThan(res.r, res.b)
        XCTAssertEqual(res.a, 204)
    }

    func testCarNormalizeTransformAndSeatRegionScan() {
        let w = 100, h = 200
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        // 写入居中车体非透明区域 (x: 10..<90, y: 10..<190) 和主驾 label=1 (x: 20..<40, y: 80..<120)
        for y in 10..<190 {
            for x in 10..<90 {
                let idx = (y * w + x) * 4
                rgba[idx] = (x >= 20 && x < 40 && y >= 80 && y < 120) ? 1 : 0
                rgba[idx + 3] = 255
            }
        }
        let bounds = CarPaintEngine.scanNonTransparentBounds(rgba: rgba, width: w, height: h)
        XCTAssertEqual(bounds, NormalizedRect(x: 10, y: 10, width: 80, height: 180))

        let tf = CarNormalizeTransform.compute(nonTransparentPixelBounds: bounds!, imagePixelWidth: w, imagePixelHeight: h)
        let seats = CarPaintEngine.scanSeatRegions(labelRGBA: rgba, width: w, height: h, transform: tf)
        XCTAssertNotNil(seats[.driver])
        XCTAssertEqual(seats[.driver]?.pixelBounds.minX, 20)
        XCTAssertEqual(seats[.driver]?.pixelBounds.maxX, 40)
    }

    func testCarPoseMatchesC16ControlSpecialCase() {
        let c16Car = CarPose.pose(for: .car, modelId: "C16")
        XCTAssertEqual(c16Car.x, 75)
        XCTAssertEqual(c16Car.y, 18.4)
        XCTAssertEqual(c16Car.scale, 1.0)
        XCTAssertEqual(c16Car.interiorAlpha, 1.0)

        let c11Car = CarPose.pose(for: .car, modelId: "C11")
        XCTAssertEqual(c11Car.x, 63)
        XCTAssertEqual(c11Car.y, -30)
        XCTAssertEqual(c11Car.scale, 1.10)
    }
}
