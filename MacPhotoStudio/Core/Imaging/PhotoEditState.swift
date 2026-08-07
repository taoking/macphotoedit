import CoreGraphics
import Foundation

struct PhotoEditState: Codable, Sendable, Equatable {
    var version = 3
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linearGradient: "线性渐变"
        case .radialGradient: "径向渐变"
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
        feather: Double = 0.20
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

    var isRenderable: Bool {
        isEnabled && clampedOpacity > 0 && adjustments.hasAdjustments
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
