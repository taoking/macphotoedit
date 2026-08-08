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

    /// The diagnostic report uses the same capability decision as the editor,
    /// so it never advertises a CIRAWFilter control the UI/pipeline cannot use.
    var availableControlNames: [String] {
        var names = ["曝光", "色温", "色调", "阴影偏移"]
        if luminanceNoiseReduction { names.append("亮度降噪") }
        if colorNoiseReduction { names.append("色彩降噪") }
        if sharpness { names.append("RAW 锐化") }
        if localContrast { names.append("局部对比") }
        if detail { names.append("细节") }
        if localToneMap { names.append("局部色调") }
        if lensCorrection { names.append("镜头校正") }
        if highlightRecovery { names.append("高光恢复") }
        return names
    }
}

/// The non-destructive boundary between Apple's RAW decoder and the shared
/// photo editor. `decoderOutputColor` describes what CIRAWFilter actually
/// supplied; `pipelineInputColor` describes the materialised image that enters
/// PhotoColorPipeline.
struct RAWDecodedImage {
    let image: CIImage
    let capabilities: RAWCapabilities
    let decoderOutputColor: PhotoColorDescriptor
    let pipelineInputColor: PhotoColorDescriptor
}

/// CIRAWFilter has no public output-colour-space configuration. Instead of
/// assuming that every camera decoder produces sRGB, inspect the returned
/// CIImage attachment and materialise the image once into the application's
/// explicit Extended Linear sRGB working space.
enum RAWColorPipeline {
    static func prepare(
        decoderOutput: CIImage,
        sourceURL: URL
    ) throws -> (image: CIImage, decoderOutputColor: PhotoColorDescriptor, pipelineInputColor: PhotoColorDescriptor) {
        guard let decoderColorSpace = decoderOutput.colorSpace,
              let decoderOutputColor = PhotoColorDescriptor.exactColorSyncDescriptor(for: decoderColorSpace) else {
            throw StudioError.rawColorSpaceUnsupported(
                path: sourceURL.path(percentEncoded: false),
                profileName: decoderOutput.colorSpace?.name as String?
            )
        }
        let extent = decoderOutput.extent.integral
        guard !extent.isEmpty else {
            throw StudioError.rawDecodingFailed(path: sourceURL.path(percentEncoded: false))
        }

        let workingColorSpace = PhotoColorPipeline.workingColorSpace
        let normalizationContext = CIContext(options: [
            .cacheIntermediates: true,
            .workingColorSpace: workingColorSpace,
            .outputColorSpace: workingColorSpace,
            .workingFormat: CIFormat.RGBAh.rawValue
        ])
        guard let normalizedCGImage = normalizationContext.createCGImage(
            decoderOutput,
            from: extent,
            format: .RGBAh,
            colorSpace: workingColorSpace
        ) else {
            throw StudioError.rawDecodingFailed(path: sourceURL.path(percentEncoded: false))
        }
        let normalizedImage = CIImage(
            cgImage: normalizedCGImage,
            options: [.colorSpace: workingColorSpace]
        )
        return (normalizedImage, decoderOutputColor, .linearWorking)
    }
}

enum RAWImagePipeline {
    static func capabilities(for filter: CIRAWFilter) -> RAWCapabilities {
        RAWCapabilities(
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
    }

    static func decode(
        sourceURL: URL,
        state: RAWEditState,
        maximumPixelSize: Int?,
        draft: Bool
    ) throws -> RAWDecodedImage {
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
        let capabilities = capabilities(for: filter)
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
        let prepared = try RAWColorPipeline.prepare(decoderOutput: image, sourceURL: sourceURL)
        return RAWDecodedImage(
            image: prepared.image,
            capabilities: capabilities,
            decoderOutputColor: prepared.decoderOutputColor,
            pipelineInputColor: prepared.pipelineInputColor
        )
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
