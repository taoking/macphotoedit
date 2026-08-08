import CoreGraphics
import Foundation

struct PhotoEditState: Codable, Sendable, Equatable {
    var version = 4
    var light = LightAdjustments()
    var color = ColorAdjustments()
    var detail = DetailAdjustments()
    var effects = EffectAdjustments()
    var transform = TransformAdjustments()
    var hsl = HSLAdjustments()
    var curves = ToneCurves()
    /// Creative LUT retained under its original property name for persisted
    /// Phase 3–6 edit states and presets.
    var lut: LUTApplication?
    /// Technical transforms are intentionally separate from creative looks.
    /// A repository LUT must carry matching input/output metadata before the
    /// renderer permits it to run.
    var technicalLUT: LUTApplication?
    var colorPipeline = PhotoColorPipelineSettings.sdr
    /// Local masks remain per-asset edit state. They are intentionally not part
    /// of reusable presets because their geometry belongs to one photo.
    var localMasks: [LocalMask] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, light, color, detail, effects, transform, hsl, curves, lut, technicalLUT, colorPipeline, localMasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        light = try container.decodeIfPresent(LightAdjustments.self, forKey: .light) ?? LightAdjustments()
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? ColorAdjustments()
        detail = try container.decodeIfPresent(DetailAdjustments.self, forKey: .detail) ?? DetailAdjustments()
        effects = try container.decodeIfPresent(EffectAdjustments.self, forKey: .effects) ?? EffectAdjustments()
        transform = try container.decodeIfPresent(TransformAdjustments.self, forKey: .transform) ?? TransformAdjustments()
        hsl = try container.decodeIfPresent(HSLAdjustments.self, forKey: .hsl) ?? HSLAdjustments()
        curves = try container.decodeIfPresent(ToneCurves.self, forKey: .curves) ?? ToneCurves()
        lut = try container.decodeIfPresent(LUTApplication.self, forKey: .lut)
        technicalLUT = try container.decodeIfPresent(LUTApplication.self, forKey: .technicalLUT)
        colorPipeline = try container.decodeIfPresent(PhotoColorPipelineSettings.self, forKey: .colorPipeline) ?? .sdr
        localMasks = try container.decodeIfPresent([LocalMask].self, forKey: .localMasks) ?? []
    }

    static let identity = PhotoEditState()
}

struct LightAdjustments: Codable, Sendable, Equatable {
    var exposure: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
}

struct ColorAdjustments: Codable, Sendable, Equatable {
    var temperature: Double = 0
    var tint: Double = 0
    var saturation: Double = 0
    var vibrance: Double = 0
}

struct DetailAdjustments: Codable, Sendable, Equatable {
    var sharpness: Double = 0
    var noiseReduction: Double = 0
}

struct EffectAdjustments: Codable, Sendable, Equatable {
    var vignette: Double = 0
}

enum LocalMaskKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case linearGradient
    case radialGradient
    case brush

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linearGradient: "线性渐变"
        case .radialGradient: "径向渐变"
        case .brush: "画笔"
        }
    }
}

struct LocalMaskAdjustments: Codable, Sendable, Equatable {
    var exposure: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0

    var hasAdjustments: Bool {
        exposure != 0 || contrast != 0 || saturation != 0
    }
}

/// One normalized point in a non-destructive brush stroke. Points remain in
/// the pre-transform image coordinate system, so they are independent of the
/// preview resolution and can be rasterized again for full-resolution export.
struct BrushPoint: Codable, Sendable, Equatable, Hashable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    var clamped: BrushPoint {
        BrushPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}

/// A vector stroke is persisted instead of a source-resolution mask bitmap.
/// `hardness` is the inner solid fraction of `radius`; the remaining outer
/// radius is rasterized as the feathered edge. `opacity` is per-stroke flow.
struct BrushStroke: Codable, Sendable, Equatable, Hashable, Identifiable {
    let id: UUID
    var points: [BrushPoint]
    var radius: Double
    var hardness: Double
    var opacity: Double
    var erase: Bool

    init(
        id: UUID = UUID(),
        points: [BrushPoint],
        radius: Double,
        hardness: Double,
        opacity: Double,
        erase: Bool
    ) {
        self.id = id
        self.points = points
        self.radius = radius
        self.hardness = hardness
        self.opacity = opacity
        self.erase = erase
    }

    var clampedRadius: Double { min(max(radius, 0.002), 1) }
    var clampedHardness: Double { min(max(hardness, 0), 1) }
    var clampedOpacity: Double { min(max(opacity, 0), 1) }
    var hasPoints: Bool { !points.isEmpty }

    /// Coalesces very close pointer updates while retaining the latest point.
    /// This bounds JSON growth by geometric distance rather than by display
    /// refresh rate, without discarding the end of a dragged stroke.
    mutating func append(_ point: BrushPoint) {
        let point = point.clamped
        guard let last = points.last else {
            points.append(point)
            return
        }
        let minimumDistance = max(0.0005, clampedRadius * 0.08)
        if hypot(point.x - last.x, point.y - last.y) < minimumDistance {
            points[points.count - 1] = point
        } else {
            points.append(point)
        }
    }
}

/// Geometry is normalized to the pre-transform image extent. This lets the
/// edit state survive preview downsampling and full-resolution export without
/// copying or editing the referenced original.
struct LocalMask: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var kind: LocalMaskKind
    var isEnabled: Bool
    var opacity: Double
    var adjustments: LocalMaskAdjustments
    /// Linear gradient: white at `start`, black at `end`.
    var startX: Double
    var startY: Double
    var endX: Double
    var endY: Double
    /// Radial gradient: white inside `radius`, feathered to black by
    /// `radius + feather`.
    var centerX: Double
    var centerY: Double
    var radius: Double
    var feather: Double
    /// Brush masks retain portable vector strokes, never an image-sized mask
    /// bitmap. These settings are copied into each newly painted stroke.
    var brushStrokes: [BrushStroke]
    var brushSize: Double
    var brushFeather: Double
    var brushFlow: Double

    init(
        id: UUID = UUID(),
        kind: LocalMaskKind,
        isEnabled: Bool = true,
        opacity: Double = 1,
        adjustments: LocalMaskAdjustments = .init(),
        startX: Double = 0.5,
        startY: Double = 1,
        endX: Double = 0.5,
        endY: Double = 0,
        centerX: Double = 0.5,
        centerY: Double = 0.5,
        radius: Double = 0.28,
        feather: Double = 0.20,
        brushStrokes: [BrushStroke] = [],
        brushSize: Double = 0.06,
        brushFeather: Double = 0.45,
        brushFlow: Double = 1
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.opacity = opacity
        self.adjustments = adjustments
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.centerX = centerX
        self.centerY = centerY
        self.radius = radius
        self.feather = feather
        self.brushStrokes = brushStrokes
        self.brushSize = brushSize
        self.brushFeather = brushFeather
        self.brushFlow = brushFlow
    }

    var clampedOpacity: Double { min(max(opacity, 0), 1) }
    var clampedStartX: Double { min(max(startX, 0), 1) }
    var clampedStartY: Double { min(max(startY, 0), 1) }
    var clampedEndX: Double { min(max(endX, 0), 1) }
    var clampedEndY: Double { min(max(endY, 0), 1) }
    var clampedCenterX: Double { min(max(centerX, 0), 1) }
    var clampedCenterY: Double { min(max(centerY, 0), 1) }
    var clampedRadius: Double { min(max(radius, 0.01), 1) }
    var clampedFeather: Double { min(max(feather, 0.001), 1) }
    var clampedBrushSize: Double { min(max(brushSize, 0.002), 1) }
    var clampedBrushFeather: Double { min(max(brushFeather, 0), 1) }
    var clampedBrushFlow: Double { min(max(brushFlow, 0), 1) }

    var isRenderable: Bool {
        guard isEnabled && clampedOpacity > 0 && adjustments.hasAdjustments else { return false }
        if case .brush = kind {
            return brushStrokes.contains(where: \.hasPoints)
        }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, isEnabled, opacity, adjustments
        case startX, startY, endX, endY
        case centerX, centerY, radius, feather
        case brushStrokes, brushSize, brushFeather, brushFlow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(LocalMaskKind.self, forKey: .kind)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        adjustments = try container.decodeIfPresent(LocalMaskAdjustments.self, forKey: .adjustments) ?? .init()
        startX = try container.decodeIfPresent(Double.self, forKey: .startX) ?? 0.5
        startY = try container.decodeIfPresent(Double.self, forKey: .startY) ?? 1
        endX = try container.decodeIfPresent(Double.self, forKey: .endX) ?? 0.5
        endY = try container.decodeIfPresent(Double.self, forKey: .endY) ?? 0
        centerX = try container.decodeIfPresent(Double.self, forKey: .centerX) ?? 0.5
        centerY = try container.decodeIfPresent(Double.self, forKey: .centerY) ?? 0.5
        radius = try container.decodeIfPresent(Double.self, forKey: .radius) ?? 0.28
        feather = try container.decodeIfPresent(Double.self, forKey: .feather) ?? 0.20
        brushStrokes = try container.decodeIfPresent([BrushStroke].self, forKey: .brushStrokes) ?? []
        brushSize = try container.decodeIfPresent(Double.self, forKey: .brushSize) ?? 0.06
        brushFeather = try container.decodeIfPresent(Double.self, forKey: .brushFeather) ?? 0.45
        brushFlow = try container.decodeIfPresent(Double.self, forKey: .brushFlow) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(adjustments, forKey: .adjustments)
        try container.encode(startX, forKey: .startX)
        try container.encode(startY, forKey: .startY)
        try container.encode(endX, forKey: .endX)
        try container.encode(endY, forKey: .endY)
        try container.encode(centerX, forKey: .centerX)
        try container.encode(centerY, forKey: .centerY)
        try container.encode(radius, forKey: .radius)
        try container.encode(feather, forKey: .feather)
        try container.encode(brushStrokes, forKey: .brushStrokes)
        try container.encode(brushSize, forKey: .brushSize)
        try container.encode(brushFeather, forKey: .brushFeather)
        try container.encode(brushFlow, forKey: .brushFlow)
    }
}

struct TransformAdjustments: Codable, Sendable, Equatable {
    var crop = NormalizedCrop.identity
    var rotationDegrees: Double = 0
    var straightenDegrees: Double = 0
    var flipHorizontal = false
    var flipVertical = false
}

struct NormalizedCrop: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let identity = NormalizedCrop(x: 0, y: 0, width: 1, height: 1)

    var clamped: NormalizedCrop {
        let safeX = min(max(x, 0), 1)
        let safeY = min(max(y, 0), 1)
        return NormalizedCrop(
            x: safeX,
            y: safeY,
            width: min(max(width, 0.01), 1 - safeX),
            height: min(max(height, 0.01), 1 - safeY)
        )
    }
}

enum HSLColor: String, Codable, Sendable, CaseIterable, Identifiable {
    case red, orange, yellow, green, aqua, blue, purple, magenta

    var id: String { rawValue }
}

struct HSLAdjustment: Codable, Sendable, Equatable {
    var hue: Double = 0
    var saturation: Double = 0
    var luminance: Double = 0
}

struct HSLAdjustments: Codable, Sendable, Equatable {
    private var values: [HSLColor: HSLAdjustment] = [:]

    subscript(_ color: HSLColor) -> HSLAdjustment {
        get { values[color] ?? HSLAdjustment() }
        set { values[color] = newValue }
    }
}

enum CurveChannel: String, Codable, Sendable, CaseIterable, Identifiable {
    case master, red, green, blue

    var id: String { rawValue }
}

struct CurvePoint: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var x: Double
    var y: Double

    init(id: UUID = UUID(), x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }

    var clamped: CurvePoint {
        CurvePoint(id: id, x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}

struct ToneCurves: Codable, Sendable, Equatable {
    private var values: [CurveChannel: [CurvePoint]] = [:]

    subscript(_ channel: CurveChannel) -> [CurvePoint] {
        get { values[channel] ?? Self.identityPoints }
        set { values[channel] = Self.normalized(newValue) }
    }

    mutating func reset(_ channel: CurveChannel) {
        values[channel] = Self.identityPoints
    }

    static let identityPoints = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]

    private static func normalized(_ points: [CurvePoint]) -> [CurvePoint] {
        let clamped = points.map(\.clamped).sorted { $0.x < $1.x }
        guard clamped.count >= 2 else { return identityPoints }
        return clamped
    }
}

struct LUTApplication: Codable, Sendable, Equatable {
    var identifier: UUID
    var strength: Double = 1

    var clampedStrength: Double { min(max(strength, 0), 1) }
}
