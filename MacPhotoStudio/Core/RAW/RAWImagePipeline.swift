import CoreImage
import CoreGraphics
import Foundation

struct RAWCapabilities: Sendable, Equatable {
    var lensCorrection = false
    var luminanceNoiseReduction = false
    var colorNoiseReduction = false
    var sharpness = false
    var localContrast = false
    var detail = false
    var localToneMap = false
    var highlightRecovery = false
}

enum RAWImagePipeline {
    static func decode(
        sourceURL: URL,
        state: RAWEditState,
        maximumPixelSize: Int?,
        draft: Bool
    ) throws -> (image: CIImage, capabilities: RAWCapabilities) {
        guard RAWFormat.isRAW(sourceURL.pathExtension), let filter = CIRAWFilter(imageURL: sourceURL) else {
            throw StudioError.rawDecodingFailed(path: sourceURL.path(percentEncoded: false))
        }
        filter.isDraftModeEnabled = draft
        if let maximumPixelSize {
            let longestSide = max(filter.nativeSize.width, filter.nativeSize.height)
            filter.scaleFactor = Float(min(1, max(CGFloat(maximumPixelSize) / max(longestSide, 1), 0.01)))
        } else {
            filter.scaleFactor = 1
        }
        let capabilities = RAWCapabilities(
            lensCorrection: filter.isLensCorrectionSupported,
            luminanceNoiseReduction: filter.isLuminanceNoiseReductionSupported,
            colorNoiseReduction: filter.isColorNoiseReductionSupported,
            sharpness: filter.isSharpnessSupported,
            localContrast: filter.isContrastSupported,
            detail: filter.isDetailSupported,
            localToneMap: filter.isLocalToneMapSupported,
            highlightRecovery: {
                if #available(macOS 26.0, *) { return filter.isHighlightRecoverySupported }
                return false
            }()
        )
        filter.exposure = Float(state.exposure)
        filter.shadowBias = Float(state.shadowBias)
        if let temperature = state.temperature { filter.neutralTemperature = Float(temperature) }
        if let tint = state.tint { filter.neutralTint = Float(tint) }
        if let value = state.boostAmount { filter.boostAmount = Float(clamp(value, 0...1)) }
        if let value = state.boostShadowAmount { filter.boostShadowAmount = Float(clamp(value, 0...2)) }
        if capabilities.luminanceNoiseReduction, let value = state.luminanceNoiseReduction { filter.luminanceNoiseReductionAmount = Float(clamp(value, 0...1)) }
        if capabilities.colorNoiseReduction, let value = state.colorNoiseReduction { filter.colorNoiseReductionAmount = Float(clamp(value, 0...1)) }
        if capabilities.sharpness, let value = state.sharpness { filter.sharpnessAmount = Float(clamp(value, 0...1)) }
        if capabilities.localContrast, let value = state.localContrast { filter.contrastAmount = Float(clamp(value, 0...1)) }
        if capabilities.detail, let value = state.detail { filter.detailAmount = Float(clamp(value, 0...3)) }
        if capabilities.localToneMap, let value = state.localToneMap { filter.localToneMapAmount = Float(clamp(value, 0...1)) }
        if capabilities.lensCorrection, let enabled = state.lensCorrectionEnabled { filter.isLensCorrectionEnabled = enabled }
        if #available(macOS 26.0, *), capabilities.highlightRecovery, let enabled = state.highlightRecoveryEnabled {
            filter.isHighlightRecoveryEnabled = enabled
        }
        guard let image = filter.outputImage else { throw StudioError.rawDecodingFailed(path: sourceURL.path(percentEncoded: false)) }
        return (image, capabilities)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
