import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation

struct PhotoImagePipeline {
    static func previewImage(from source: CIImage, maximumPixelSize: Int) -> CIImage {
        let extent = source.extent.integral
        let largestSide = max(extent.width, extent.height)
        guard largestSide > CGFloat(maximumPixelSize) else { return source }
        let scale = CGFloat(maximumPixelSize) / largestSide
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = source
        filter.scale = Float(scale)
        filter.aspectRatio = 1
        return filter.outputImage ?? source
    }

    static func apply(_ state: PhotoEditState, to source: CIImage, lut: CubeLUT? = nil) -> CIImage {
        var image = applyCreativeAdjustments(state, to: source)
        image = applyLocalMasks(state.localMasks, to: image)
        if let lut, let application = state.lut { image = LUTProcessor.apply(lut, to: image, strength: application.clampedStrength) }
        return applyTransform(image, using: state.transform)
    }

    /// Phase 7 composes this stage between a validated technical transform and
    /// a validated creative LUT. It stays public within the module so the old
    /// `apply` API remains source-compatible for Phase 3–6 callers and tests.
    static func applyCreativeAdjustments(_ state: PhotoEditState, to source: CIImage) -> CIImage {
        var image = source
        if state.light.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: state.light.exposure])
        }
        if state.light.highlights != 0 || state.light.shadows != 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": max(0, 1 - state.light.highlights),
                "inputShadowAmount": max(0, 1 + state.light.shadows)
            ])
        }
        if state.color.temperature != 0 || state.color.tint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500 + state.color.temperature * 2500, y: state.color.tint * 100),
                "inputTargetNeutral": CIVector(x: 6500, y: 0)
            ])
        }
        if state.light.contrast != 0 || state.color.saturation != 0 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: max(0, 1 + state.light.contrast),
                kCIInputSaturationKey: max(0, 1 + state.color.saturation)
            ])
        }
        if state.color.vibrance != 0 { image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": state.color.vibrance]) }
        if state.detail.sharpness != 0 { image = image.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: state.detail.sharpness]) }
        if state.detail.noiseReduction != 0 { image = image.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": state.detail.noiseReduction]) }
        if state.effects.vignette != 0 { image = image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: state.effects.vignette, kCIInputRadiusKey: max(image.extent.width, image.extent.height) * 0.6]) }
        if state.light.whites != 0 || state.light.blacks != 0 || state.hsl.hasAdjustments {
            image = ColorAdjustmentCube.apply(
                image,
                whites: state.light.whites,
                blacks: state.light.blacks,
                hsl: state.hsl
            )
        }
        if state.curves.hasAdjustments {
            image = ToneCurveCube.apply(image, curves: state.curves)
        }
        return image
    }

    /// Internal instrumentation for deterministic cache tests. It measures
    /// generated cube payloads, not GPU render time, so it remains valid on
    /// machines with different Metal devices.
    static func cubeCacheDiagnostics() -> PhotoCubeCacheDiagnostics {
        PhotoCubeCacheDiagnostics(
            color: ColorAdjustmentCube.diagnostics,
            toneCurve: ToneCurveCube.diagnostics
        )
    }

    static func resetCubeCachesForTesting() {
        ColorAdjustmentCube.resetCacheForTesting()
        ToneCurveCube.resetCacheForTesting()
    }

    /// Applies every mask sequentially to the pre-transform image. Sequential
    /// composition makes mask ordering deterministic and keeps preview/export
    /// identical at every resolution.
    static func applyLocalMasks(_ masks: [LocalMask], to source: CIImage) -> CIImage {
        masks.reduce(source) { image, mask in
            guard mask.isRenderable else { return image }
            let adjusted = apply(mask.adjustments, to: image)
            let maskImage = LocalMaskRenderer.image(for: mask, source: image)
            guard let maskImage else { return image }
            return adjusted.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: maskImage
            ])
        }
    }

    static func applyTransform(_ image: CIImage, using transform: TransformAdjustments) -> CIImage {
        let crop = transform.crop.clamped
        let extent = image.extent
        let cropped = image.cropped(to: CGRect(x: extent.minX + extent.width * crop.x, y: extent.minY + extent.height * crop.y, width: extent.width * crop.width, height: extent.height * crop.height))
        var affine = CGAffineTransform.identity
        if transform.flipHorizontal { affine = affine.scaledBy(x: -1, y: 1) }
        if transform.flipVertical { affine = affine.scaledBy(x: 1, y: -1) }
        let radians = (transform.rotationDegrees + transform.straightenDegrees) * .pi / 180
        if radians != 0 { affine = affine.rotated(by: radians) }
        return cropped.transformed(by: affine)
    }

    private static func apply(_ adjustments: LocalMaskAdjustments, to source: CIImage) -> CIImage {
        var image = source
        if adjustments.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: adjustments.exposure])
        }
        if adjustments.contrast != 0 || adjustments.saturation != 0 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: max(0, 1 + adjustments.contrast),
                kCIInputSaturationKey: max(0, 1 + adjustments.saturation)
            ])
        }
        return image
    }
}

private enum LocalMaskRenderer {
    static func image(for mask: LocalMask, source: CIImage) -> CIImage? {
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let maskImage: CIImage
        switch mask.kind {
        case .linearGradient:
            let start = CGPoint(
                x: extent.minX + extent.width * mask.clampedStartX,
                y: extent.minY + extent.height * mask.clampedStartY
            )
            let end = CGPoint(
                x: extent.minX + extent.width * mask.clampedEndX,
                y: extent.minY + extent.height * mask.clampedEndY
            )
            guard start != end else { return nil }
            maskImage = CIImage(
                color: .black
            ).cropped(to: extent).applyingFilter("CILinearGradient", parameters: [
                "inputPoint0": CIVector(cgPoint: start),
                "inputPoint1": CIVector(cgPoint: end),
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ])
        case .radialGradient:
            let center = CGPoint(
                x: extent.minX + extent.width * mask.clampedCenterX,
                y: extent.minY + extent.height * mask.clampedCenterY
            )
            let scale = min(extent.width, extent.height)
            let radius0 = max(1, scale * mask.clampedRadius)
            let radius1 = radius0 + max(1, scale * mask.clampedFeather)
            maskImage = CIImage(color: .black).cropped(to: extent).applyingFilter("CIRadialGradient", parameters: [
                "inputCenter": CIVector(cgPoint: center),
                "inputRadius0": radius0,
                "inputRadius1": radius1,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ])
        case .brush:
            guard let brushMask = BrushMaskRenderer.image(for: mask.brushStrokes, extent: extent) else { return nil }
            maskImage = brushMask
        case .subject:
            guard let subjectMask = VisionSubjectMaskRenderer.image(for: source) else { return nil }
            maskImage = subjectMask
        }
        guard mask.clampedOpacity < 1 else { return maskImage.cropped(to: extent) }
        return maskImage.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: mask.clampedOpacity, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: mask.clampedOpacity, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: mask.clampedOpacity, w: 0)
        ]).cropped(to: extent)
    }
}

private enum ColorAdjustmentCube {
    // A 33^3 cube makes the eight hue regions continuous. A generated cube is
    // 574,992 bytes (33 * 33 * 33 * RGBA Float), so it is retained by a small,
    // parameter-keyed cache instead of allocating an array and copying it to
    // Data for every preview render.
    private static let dimension = 33
    private static let cache = BoundedCubeDataCache<ColorAdjustmentCubeKey>(capacity: 8)

    static func apply(_ image: CIImage, whites: Double, blacks: Double, hsl: HSLAdjustments) -> CIImage {
        let key = ColorAdjustmentCubeKey(whites: whites, blacks: blacks, hsl: hsl)
        let cube = cache.data(for: key) {
            makeCube(whites: whites, blacks: blacks, hsl: hsl)
        }
        return applyCube(cube, dimension: dimension, to: image)
    }

    private static func makeCube(whites: Double, blacks: Double, hsl: HSLAdjustments) -> Data {
        var data = Data(count: dataByteCount)
        data.withUnsafeMutableBytes { rawBuffer in
            let values = rawBuffer.bindMemory(to: Float.self)
            var index = 0
            for blue in 0..<dimension {
                for green in 0..<dimension {
                    for red in 0..<dimension {
                        var color = SIMD3<Double>(
                            Double(red) / Double(dimension - 1),
                            Double(green) / Double(dimension - 1),
                            Double(blue) / Double(dimension - 1)
                        )
                        color = adjustHSL(color, adjustments: hsl)
                        let luminance = color.x * 0.2126 + color.y * 0.7152 + color.z * 0.0722
                        let shadowWeight = 1 - smoothstep(0, 0.5, luminance)
                        let highlightWeight = smoothstep(0.5, 1, luminance)
                        color += SIMD3<Double>(repeating: blacks * shadowWeight * 0.25 + whites * highlightWeight * 0.25)
                        values[index] = Float(clamp(color.x))
                        values[index + 1] = Float(clamp(color.y))
                        values[index + 2] = Float(clamp(color.z))
                        values[index + 3] = 1
                        index += 4
                    }
                }
            }
        }
        return data
    }

    private static func adjustHSL(_ rgb: SIMD3<Double>, adjustments: HSLAdjustments) -> SIMD3<Double> {
        var hslValue = rgbToHSL(rgb)
        guard hslValue.y > 0.000_01 else { return rgb }
        var hueShift = 0.0
        var saturationShift = 0.0
        var luminanceShift = 0.0
        var totalWeight = 0.0
        for color in HSLColor.allCases {
            let adjustment = adjustments[color]
            guard adjustment.hue != 0 || adjustment.saturation != 0 || adjustment.luminance != 0 else { continue }
            let weight = hueWeight(hslValue.x, center: color.hueCenter)
            hueShift += adjustment.hue * weight
            saturationShift += adjustment.saturation * weight
            luminanceShift += adjustment.luminance * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return rgb }
        hslValue.x = positiveModulo(hslValue.x + hueShift * 0.1, 1)
        hslValue.y = clamp(hslValue.y * (1 + saturationShift))
        hslValue.z = clamp(hslValue.z + luminanceShift * 0.25)
        return hslToRGB(hslValue)
    }

    private static func hueWeight(_ hue: Double, center: Double) -> Double {
        let distance = min(abs(hue - center), 1 - abs(hue - center))
        return max(0, 1 - distance / 0.125)
    }

    static var diagnostics: CubeCacheDiagnostics {
        cache.diagnostics(dataByteCount: dataByteCount)
    }

    static func resetCacheForTesting() {
        cache.reset()
    }

    private static var dataByteCount: Int {
        dimension * dimension * dimension * 4 * MemoryLayout<Float>.stride
    }
}

private enum ToneCurveCube {
    private static let dimension = 33
    private static let cache = BoundedCubeDataCache<ToneCurveCubeKey>(capacity: 8)

    static func apply(_ image: CIImage, curves: ToneCurves) -> CIImage {
        let key = ToneCurveCubeKey(curves: curves)
        let cube = cache.data(for: key) {
            makeCube(curves: curves)
        }
        return applyCube(cube, dimension: dimension, to: image)
    }

    private static func makeCube(curves: ToneCurves) -> Data {
        // Tone curves are channel-separable: each cube channel depends only on
        // its matching input coordinate. Evaluate the piecewise curves for the
        // 33 discrete inputs once, then use those tables in the 3D layout.
        let channelValues = CurveChannel.allCases.reduce(into: [CurveChannel: [Float]]()) { values, channel in
            values[channel] = (0..<dimension).map { index in
                let input = Double(index) / Double(dimension - 1)
                let master = curves.value(at: input, channel: .master)
                return Float(clamp(curves.value(at: master, channel: channel)))
            }
        }
        let redValues = channelValues[.red] ?? []
        let greenValues = channelValues[.green] ?? []
        let blueValues = channelValues[.blue] ?? []

        var data = Data(count: dataByteCount)
        data.withUnsafeMutableBytes { rawBuffer in
            let values = rawBuffer.bindMemory(to: Float.self)
            var index = 0
            for blue in 0..<dimension {
                for green in 0..<dimension {
                    for red in 0..<dimension {
                        values[index] = redValues[red]
                        values[index + 1] = greenValues[green]
                        values[index + 2] = blueValues[blue]
                        values[index + 3] = 1
                        index += 4
                    }
                }
            }
        }
        return data
    }

    static var diagnostics: CubeCacheDiagnostics {
        cache.diagnostics(dataByteCount: dataByteCount)
    }

    static func resetCacheForTesting() {
        cache.reset()
    }

    private static var dataByteCount: Int {
        dimension * dimension * dimension * 4 * MemoryLayout<Float>.stride
    }
}

struct PhotoCubeCacheDiagnostics: Sendable, Equatable {
    let color: CubeCacheDiagnostics
    let toneCurve: CubeCacheDiagnostics
}

struct CubeCacheDiagnostics: Sendable, Equatable {
    let generationCount: Int
    let entryCount: Int
    let dataByteCount: Int
}

private struct ColorAdjustmentCubeKey: Hashable {
    private let values: [UInt64]

    init(whites: Double, blacks: Double, hsl: HSLAdjustments) {
        var values = [whites.bitPattern, blacks.bitPattern]
        values.reserveCapacity(2 + HSLColor.allCases.count * 3)
        for color in HSLColor.allCases {
            let adjustment = hsl[color]
            values.append(adjustment.hue.bitPattern)
            values.append(adjustment.saturation.bitPattern)
            values.append(adjustment.luminance.bitPattern)
        }
        self.values = values
    }
}

private struct ToneCurveCubeKey: Hashable {
    private let values: [UInt64]

    init(curves: ToneCurves) {
        var values: [UInt64] = []
        for channel in CurveChannel.allCases {
            let points = curves[channel]
            values.append(UInt64(points.count))
            for point in points {
                values.append(point.x.bitPattern)
                values.append(point.y.bitPattern)
            }
        }
        self.values = values
    }
}

private final class BoundedCubeDataCache<Key: Hashable>: @unchecked Sendable {
    private let capacity: Int
    private let lock = NSLock()
    private var values: [Key: Data] = [:]
    private var recency: [Key] = []
    private var generationCount = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func data(for key: Key, make: () -> Data) -> Data {
        lock.lock()
        defer { lock.unlock() }

        if let existing = values[key] {
            touch(key)
            return existing
        }

        let generated = make()
        generationCount += 1
        values[key] = generated
        recency.append(key)
        if recency.count > capacity, let evicted = recency.first {
            recency.removeFirst()
            values[evicted] = nil
        }
        return generated
    }

    func diagnostics(dataByteCount: Int) -> CubeCacheDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return CubeCacheDiagnostics(
            generationCount: generationCount,
            entryCount: values.count,
            dataByteCount: dataByteCount
        )
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll(keepingCapacity: false)
        recency.removeAll(keepingCapacity: false)
        generationCount = 0
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

private extension HSLColor {
    var hueCenter: Double {
        switch self {
        case .red: 0
        case .orange: 1.0 / 12.0
        case .yellow: 2.0 / 12.0
        case .green: 4.0 / 12.0
        case .aqua: 6.0 / 12.0
        case .blue: 8.0 / 12.0
        case .purple: 9.0 / 12.0
        case .magenta: 11.0 / 12.0
        }
    }
}

private extension ToneCurves {
    var hasAdjustments: Bool {
        CurveChannel.allCases.contains { channel in
            self[channel].map(\.clamped) != ToneCurves.identityPoints
        }
    }

    func value(at input: Double, channel: CurveChannel) -> Double {
        let points = self[channel]
        guard let first = points.first, let last = points.last else { return clamp(input) }
        let x = clamp(input)
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        for pair in zip(points, points.dropFirst()) where x <= pair.1.x {
            let span = max(pair.1.x - pair.0.x, 0.000_001)
            let progress = (x - pair.0.x) / span
            return pair.0.y + (pair.1.y - pair.0.y) * progress
        }
        return last.y
    }
}

private extension HSLAdjustments {
    var hasAdjustments: Bool {
        HSLColor.allCases.contains {
            let value = self[$0]
            return value.hue != 0 || value.saturation != 0 || value.luminance != 0
        }
    }
}

private func applyCube(_ data: Data, dimension: Int, to image: CIImage) -> CIImage {
    guard let filter = CIFilter(name: "CIColorCube") else { return image }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(dimension, forKey: "inputCubeDimension")
    filter.setValue(data, forKey: "inputCubeData")
    return filter.outputImage ?? image
}

private func rgbToHSL(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
    let maximum = max(rgb.x, rgb.y, rgb.z)
    let minimum = min(rgb.x, rgb.y, rgb.z)
    let delta = maximum - minimum
    let lightness = (maximum + minimum) / 2
    guard delta > 0.000_001 else { return SIMD3<Double>(0, 0, lightness) }
    let saturation = delta / (1 - abs(2 * lightness - 1))
    let hue: Double
    if maximum == rgb.x {
        hue = positiveModulo((rgb.y - rgb.z) / delta, 6) / 6
    } else if maximum == rgb.y {
        hue = ((rgb.z - rgb.x) / delta + 2) / 6
    } else {
        hue = ((rgb.x - rgb.y) / delta + 4) / 6
    }
    return SIMD3<Double>(hue, saturation, lightness)
}

private func hslToRGB(_ hsl: SIMD3<Double>) -> SIMD3<Double> {
    let chroma = (1 - abs(2 * hsl.z - 1)) * hsl.y
    let h = positiveModulo(hsl.x, 1) * 6
    let secondary = chroma * (1 - abs(positiveModulo(h, 2) - 1))
    let base: SIMD3<Double>
    switch h {
    case 0..<1: base = SIMD3<Double>(chroma, secondary, 0)
    case 1..<2: base = SIMD3<Double>(secondary, chroma, 0)
    case 2..<3: base = SIMD3<Double>(0, chroma, secondary)
    case 3..<4: base = SIMD3<Double>(0, secondary, chroma)
    case 4..<5: base = SIMD3<Double>(secondary, 0, chroma)
    default: base = SIMD3<Double>(chroma, 0, secondary)
    }
    return base + SIMD3<Double>(repeating: hsl.z - chroma / 2)
}

private func smoothstep(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
    let t = clamp((value - lower) / (upper - lower))
    return t * t * (3 - 2 * t)
}

private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
private func positiveModulo(_ value: Double, _ modulus: Double) -> Double {
    let remainder = value.truncatingRemainder(dividingBy: modulus)
    return remainder >= 0 ? remainder : remainder + modulus
}
