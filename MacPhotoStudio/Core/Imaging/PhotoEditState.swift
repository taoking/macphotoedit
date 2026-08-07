import CoreGraphics
import Foundation

struct PhotoEditState: Codable, Sendable, Equatable {
    var version = 2
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

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, light, color, detail, effects, transform, hsl, curves, lut, technicalLUT, colorPipeline
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
