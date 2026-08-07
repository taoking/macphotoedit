import Foundation

/// The adjustment groups intentionally eligible for copy/paste and presets.
/// Transform is omitted so a preset can never overwrite an asset's crop.
enum PhotoEditComponent: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case color
    case hsl
    case curves
    case detail
    case effects
    case lut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "光线"
        case .color: "颜色"
        case .hsl: "HSL"
        case .curves: "曲线"
        case .detail: "细节"
        case .effects: "效果"
        case .lut: "LUT"
        }
    }

    static let allPresetComponents = Set(allCases)
}

struct PhotoPresetContent: Codable, Sendable, Equatable {
    var light: LightAdjustments
    var color: ColorAdjustments
    var detail: DetailAdjustments
    var effects: EffectAdjustments
    var hsl: HSLAdjustments
    var curves: ToneCurves
    var lut: LUTApplication?

    init(state: PhotoEditState) {
        light = state.light
        color = state.color
        detail = state.detail
        effects = state.effects
        hsl = state.hsl
        curves = state.curves
        lut = state.lut
    }
}

struct PhotoPreset: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var content: PhotoPresetContent
    var isFavorite: Bool
    let createdAt: Date
    var updatedAt: Date
}

struct PhotoPresetExchange: Codable, Sendable, Equatable {
    static let currentVersion = 1

    let version: Int
    var name: String
    var content: PhotoPresetContent
    var isFavorite: Bool

    init(preset: PhotoPreset) {
        version = Self.currentVersion
        name = preset.name
        content = preset.content
        isFavorite = preset.isFavorite
    }
}

extension PhotoEditState {
    var presetContent: PhotoPresetContent { PhotoPresetContent(state: self) }

    func applying(
        _ content: PhotoPresetContent,
        components: Set<PhotoEditComponent> = PhotoEditComponent.allPresetComponents
    ) -> PhotoEditState {
        var result = self
        if components.contains(.light) { result.light = content.light }
        if components.contains(.color) { result.color = content.color }
        if components.contains(.hsl) { result.hsl = content.hsl }
        if components.contains(.curves) { result.curves = content.curves }
        if components.contains(.detail) { result.detail = content.detail }
        if components.contains(.effects) { result.effects = content.effects }
        if components.contains(.lut) { result.lut = content.lut }
        return result
    }
}
