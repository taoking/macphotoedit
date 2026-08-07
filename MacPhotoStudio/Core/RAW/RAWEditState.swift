import Foundation

/// RAW controls intentionally remain separate from `PhotoEditState`. They map
/// only to `CIRAWFilter` capabilities and are applied before standard edits.
struct RAWEditState: Codable, Sendable, Equatable {
    var version = 1
    var exposure: Double = 0
    var temperature: Double?
    var tint: Double?
    var shadowBias: Double = 0
    var boostAmount: Double?
    var boostShadowAmount: Double?
    var luminanceNoiseReduction: Double?
    var colorNoiseReduction: Double?
    var sharpness: Double?
    var localContrast: Double?
    var detail: Double?
    var localToneMap: Double?
    var lensCorrectionEnabled: Bool?
    var highlightRecoveryEnabled: Bool?

    static let identity = RAWEditState()
}

enum RAWFormat {
    static let extensions: Set<String> = ["arw", "dng"]

    static func isRAW(_ fileExtension: String) -> Bool {
        extensions.contains(fileExtension.lowercased())
    }
}
