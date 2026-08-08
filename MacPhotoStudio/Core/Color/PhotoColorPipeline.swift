import CoreGraphics
import CoreImage
import Foundation

/// A stable, serializable description of a colour encoding. It intentionally
/// records primaries and transfer separately: a technical LUT is only safe when
/// both match its declared input, not merely when a filename looks familiar.
enum PhotoColorSpace: String, Codable, Sendable, CaseIterable, Identifiable {
    case sRGB
    case displayP3
    case rec709
    case rec2020
    case linearSRGB
    case extendedLinearSRGB

    var id: String { rawValue }

    static let outputSpaces: [PhotoColorSpace] = [.sRGB, .displayP3, .rec709, .rec2020]

    var title: String {
        switch self {
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        case .rec709: "Rec.709"
        case .rec2020: "Rec.2020"
        case .linearSRGB: "Linear sRGB"
        case .extendedLinearSRGB: "Extended Linear sRGB"
        }
    }

    /// The explicit ColorSync profile used at the renderer boundary. These are
    /// deliberately *not* allowed to fall back to sRGB: exporting a Rec.709 or
    /// Rec.2020 image with an sRGB profile would make the file's colour contract
    /// false even if its edit state still mentioned the requested output.
    var cgColorSpace: CGColorSpace {
        let name: CFString = switch self {
        case .sRGB: CGColorSpace.sRGB
        case .displayP3: CGColorSpace.displayP3
        case .rec709: CGColorSpace.itur_709
        case .rec2020: CGColorSpace.itur_2020
        case .linearSRGB: CGColorSpace.linearSRGB
        case .extendedLinearSRGB: CGColorSpace.extendedLinearSRGB
        }
        guard let colorSpace = CGColorSpace(name: name) else {
            preconditionFailure("当前 macOS 无法提供 \(title) ColorSync profile；拒绝回退为错误的色彩空间。")
        }
        return colorSpace
    }

    /// Rec.2020 SDR uses the BT.709 transfer curve. HDR transfer functions are
    /// represented separately and are not claimed by this SDR output setting.
    var defaultTransferFunction: PhotoTransferFunction {
        switch self {
        case .sRGB, .displayP3:
            .sRGB
        case .rec709, .rec2020:
            .rec709
        case .linearSRGB, .extendedLinearSRGB:
            .linear
        }
    }

    /// Checks the actual embedded ICC payload rather than a display name. This
    /// is used after ImageIO writes an export so a destination that silently
    /// discarded or substituted the requested profile is rejected.
    func matchesEmbeddedProfile(of colorSpace: CGColorSpace) -> Bool {
        guard let expected = cgColorSpace.copyICCData(),
              let actual = colorSpace.copyICCData()
        else { return false }
        return expected == actual
    }
}

enum PhotoTransferFunction: String, Codable, Sendable, CaseIterable, Identifiable {
    case sRGB
    case linear
    case rec709
    case sLog3
    case hlg
    case pq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sRGB: "sRGB"
        case .linear: "Linear"
        case .rec709: "Rec.709"
        case .sLog3: "S-Log3"
        case .hlg: "HLG"
        case .pq: "PQ"
        }
    }
}

struct PhotoColorDescriptor: Codable, Sendable, Equatable, Hashable {
    var colorSpace: PhotoColorSpace
    var transferFunction: PhotoTransferFunction

    static let sRGB = Self(colorSpace: .sRGB, transferFunction: .sRGB)
    static let displayP3 = Self(colorSpace: .displayP3, transferFunction: .sRGB)
    static let rec709 = Self(colorSpace: .rec709, transferFunction: .rec709)
    static let linearWorking = Self(colorSpace: .extendedLinearSRGB, transferFunction: .linear)

    var title: String { "\(colorSpace.title) · \(transferFunction.title)" }

    /// A descriptor is safe for the Phase 12.3 Technical LUT bridge only when
    /// its transfer function is represented by an Apple-provided ColorSync
    /// profile. S-Log3, PQ and HLG need a different, explicitly validated
    /// colour-management implementation and must not be approximated here.
    var colorSyncColorSpace: CGColorSpace? {
        guard transferFunction == colorSpace.defaultTransferFunction else { return nil }
        return colorSpace.cgColorSpace
    }

    var supportsColorSyncTechnicalWorkflow: Bool {
        colorSyncColorSpace != nil
    }

    /// Resolves a CI/ImageIO colour attachment only when its ICC payload is an
    /// exact match for a profile the app has an explicit pipeline contract for.
    /// Callers must not infer sRGB from an absent or unfamiliar attachment.
    static func exactColorSyncDescriptor(for colorSpace: CGColorSpace) -> Self? {
        for candidate in PhotoColorSpace.allCases where candidate.matchesEmbeddedProfile(of: colorSpace) {
            return Self(colorSpace: candidate, transferFunction: candidate.defaultTransferFunction)
        }
        return nil
    }

    static func inferred(fromProfileName profileName: String?) -> Self {
        let profile = profileName?.lowercased() ?? ""
        var transfer: PhotoTransferFunction
        if profile.contains("s-log3") || profile.contains("slog3") {
            transfer = .sLog3
        } else if profile.contains("hlg") {
            transfer = .hlg
        } else if profile.contains("pq") || profile.contains("st 2084") {
            transfer = .pq
        } else if profile.contains("rec. 709") || profile.contains("rec709") || profile.contains("bt.709") {
            transfer = .rec709
        } else if profile.contains("linear") {
            transfer = .linear
        } else {
            transfer = .sRGB
        }

        let colorSpace: PhotoColorSpace
        if profile.contains("display p3") {
            colorSpace = .displayP3
        } else if profile.contains("2020") || profile.contains("bt.2020") {
            colorSpace = .rec2020
        } else if transfer == .rec709 {
            colorSpace = .rec709
        } else if transfer == .linear {
            colorSpace = .linearSRGB
        } else {
            colorSpace = .sRGB
        }
        // SDR BT.2020 uses the BT.709 transfer curve. Image profile names often
        // only mention "Rec.2020", so normalize that otherwise ambiguous case
        // instead of tagging the source as Rec.2020 primaries with sRGB gamma.
        if colorSpace == .rec2020, transfer == .sRGB {
            transfer = .rec709
        }
        return Self(colorSpace: colorSpace, transferFunction: transfer)
    }
}

enum PhotoDynamicRange: String, Codable, Sendable, CaseIterable, Identifiable {
    case sdr
    case hdr

    var id: String { rawValue }
    /// `.hdr` is a persisted name retained for compatibility. The current
    /// product only offers an extended-range *preview* request; it does not
    /// claim HDR mastering or an HDR still-image export format.
    var title: String { self == .sdr ? "SDR" : "扩展范围预览（非 HDR 导出）" }
}

struct PhotoColorPipelineSettings: Codable, Sendable, Equatable {
    var outputColorSpace: PhotoColorSpace = .sRGB
    var dynamicRange: PhotoDynamicRange = .sdr

    static let sdr = Self()
}

/// Required metadata for a technical LUT. A `.cube` file does not contain a
/// universal, trustworthy colour contract, so the import flow requires this
/// information instead of guessing from its filename.
struct TechnicalLUTMetadata: Codable, Sendable, Equatable, Hashable {
    var input: PhotoColorDescriptor
    var output: PhotoColorDescriptor

    init(input: PhotoColorDescriptor, output: PhotoColorDescriptor) {
        self.input = input
        self.output = output
    }
}

struct ColorPipelinePlan: Sendable, Equatable {
    let source: PhotoColorDescriptor
    let working: PhotoColorDescriptor
    let technicalTransform: TechnicalLUTMetadata?
    let creativeLUTIdentifier: UUID?
    let output: PhotoColorDescriptor
    let dynamicRange: PhotoDynamicRange

    static func make(
        source: PhotoColorDescriptor,
        settings: PhotoColorPipelineSettings,
        technicalLUT: CubeLUT?,
        creativeLUT: CubeLUT?
    ) throws -> Self {
        if let technicalLUT {
            guard technicalLUT.kind == .technical,
                  let metadata = technicalLUT.technicalMetadata else {
                throw StudioError.invalidLUT(message: "Technical LUT 缺少输入/输出色彩元数据。")
            }
            guard metadata.input == source else {
                throw StudioError.invalidLUT(message: "Technical LUT 期望 \(metadata.input.title)，当前源为 \(source.title)。")
            }
            guard metadata.input.supportsColorSyncTechnicalWorkflow,
                  metadata.output.supportsColorSyncTechnicalWorkflow else {
                throw StudioError.invalidLUT(
                    message: "Technical LUT 的 \(metadata.input.title) → \(metadata.output.title) 编码无法由当前 ColorSync bridge 可靠转换；已拒绝套用，避免错误调色。"
                )
            }
        }
        if let creativeLUT, creativeLUT.kind != .creative {
            throw StudioError.invalidLUT(message: "Technical LUT 必须在“Technical Transform”槽位中使用，不能作为创意 LUT。")
        }
        return Self(
            source: source,
            working: .linearWorking,
            technicalTransform: technicalLUT?.technicalMetadata,
            creativeLUTIdentifier: creativeLUT?.id,
            output: PhotoColorDescriptor(
                colorSpace: settings.outputColorSpace,
                transferFunction: settings.dynamicRange == .hdr
                    ? .linear
                    : settings.outputColorSpace.defaultTransferFunction
            ),
            dynamicRange: settings.dynamicRange
        )
    }
}

enum HDRPhotoCapabilities {
    /// The app contains a real half-float TIFF + AppKit EDR preview path. It is
    /// deliberately separate from whether the window's current screen has EDR
    /// headroom, which must be checked at the AppKit boundary.
    static let hasExtendedRangePreviewPath = true

    /// `NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue` is
    /// greater than one only when the display is capable of EDR. Keeping this
    /// pure makes the capability policy testable without claiming that the CI
    /// host or an arbitrary external display is HDR-capable.
    static func supportsExtendedRangePreview(potentialHeadroom: CGFloat) -> Bool {
        hasExtendedRangePreviewPath && potentialHeadroom > 1.0
    }

    /// ImageIO's portable still-image APIs used by this app do not expose a
    /// reliable HDR gain-map writer on every supported macOS release. Returning
    /// false is deliberate: callers must tone-map to SDR rather than label an
    /// ordinary 8-bit HEIC/TIFF/JPEG as HDR.
    static let supportsHDRGainMapExport = false
    static let supportsHDRExport = false
}

/// AVFoundation can natively play detected HDR sources, but the editing,
/// proxy and export pipeline is SDR-only. Keep these capability declarations
/// central so labels such as HLG, PQ or Rec.2020 cannot be mistaken for HDR
/// production support.
enum HDRVideoCapabilities {
    static let supportsNativePlayback = true
    static let supportsEditing = false
    static let supportsExport = false
    static let supportsProxy = false
}

enum HDRToneMapper {
    static func toneMapToSDR(_ image: CIImage) -> CIImage {
        if let filter = CIFilter(name: "CIToneMapHeadroom") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(1.0, forKey: "inputTargetHeadroom")
            if let output = filter.outputImage { return output }
        }
        // The fallback remains an actual highlight-compression operation rather
        // than silently clipping extended values when the modern filter is not
        // present on an older host.
        return image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": 0.35,
            "inputShadowAmount": 1.0
        ])
    }
}

enum PhotoColorPipeline {
    /// All photo render contexts explicitly use this extended, linear ColorSync
    /// space. Core Image then matches every source image into it before any
    /// filter kernel runs, and matches from it to the requested output at the
    /// render boundary.
    static let workingColorSpace = PhotoColorSpace.extendedLinearSRGB.cgColorSpace

    /// Core Image preserves the source ICC attachment through the processing
    /// graph. The render boundary below supplies the explicit output CGColorSpace
    /// to ColorSync; this function defines the non-destructive stage ordering.
    static func apply(
        source: CIImage,
        state: PhotoEditState,
        sourceColor: PhotoColorDescriptor,
        technicalLUT: CubeLUT?,
        creativeLUT: CubeLUT?,
        settings: PhotoColorPipelineSettings? = nil,
        subjectMaskProvider: SubjectMaskProvider? = nil,
        subjectMaskCacheKey: SubjectMaskCacheKey? = nil
    ) throws -> (image: CIImage, plan: ColorPipelinePlan) {
        let effectiveSettings = settings ?? state.colorPipeline
        let plan = try ColorPipelinePlan.make(
            source: sourceColor,
            settings: effectiveSettings,
            technicalLUT: technicalLUT,
            creativeLUT: creativeLUT
        )

        // Source → Working Color Space is performed by the explicit
        // `CIContext.workingColorSpace` used by every photo renderer. This
        // graph deliberately starts with the original, profile-attached source;
        // Core Image color-matches it into `workingColorSpace` before executing
        // the filters below.
        // Subject segmentation always sees this decoded, orientation-applied
        // source. Keeping it outside the global-edit sequence means exposure,
        // white balance, HSL and curve changes reuse the same valid mask.
        let subjectSegmentationSource = source
        var image = source

        // Technical LUTs are a specialised bridge: materialise the original
        // source into the declared input encoding, evaluate the cube without
        // implicit colour matching, attach the declared output ICC, then let
        // the normal renderer match that output into the shared working space.
        if let technicalLUT, let application = state.technicalLUT {
            guard let metadata = technicalLUT.technicalMetadata else {
                throw StudioError.invalidLUT(message: "Technical LUT 缺少输入/输出色彩元数据。")
            }
            image = try TechnicalLUTProcessor.apply(
                technicalLUT,
                to: image,
                metadata: metadata,
                strength: application.clampedStrength
            )
        }

        // Creative adjustments → Creative LUT → Output Transform.
        image = PhotoImagePipeline.applyCreativeAdjustments(state, to: image)
        image = PhotoImagePipeline.applyLocalMasks(
            state.localMasks,
            to: image,
            subjectSegmentationSource: subjectSegmentationSource,
            subjectMaskProvider: subjectMaskProvider,
            subjectMaskCacheKey: subjectMaskCacheKey
        )
        if let creativeLUT, let application = state.lut {
            image = LUTProcessor.apply(creativeLUT, to: image, strength: application.clampedStrength)
        }
        image = PhotoImagePipeline.applyTransform(image, using: state.transform)

        if plan.dynamicRange == .sdr {
            image = HDRToneMapper.toneMapToSDR(image)
        }
        return (image, plan)
    }
}

/// Applies a Technical LUT in its declared input/output encodings. A normal
/// `CIColorCube` in the app's linear working context would otherwise ignore
/// the metadata and evaluate the LUT against the wrong code values.
enum TechnicalLUTProcessor {
    static func apply(
        _ lut: CubeLUT,
        to source: CIImage,
        metadata: TechnicalLUTMetadata,
        strength: Double
    ) throws -> CIImage {
        let normalizedStrength = min(max(strength, 0), 1)
        guard let inputColorSpace = metadata.input.colorSyncColorSpace,
              let outputColorSpace = metadata.output.colorSyncColorSpace else {
            throw StudioError.invalidLUT(
                message: "Technical LUT 的输入或输出编码未得到当前 ColorSync bridge 支持。"
            )
        }
        let extent = source.extent.integral
        guard !extent.isEmpty else {
            throw StudioError.invalidLUT(message: "Technical LUT 没有可处理的图像范围。")
        }

        // This first render performs a genuine ColorSync conversion from the
        // source attachment into the LUT's declared input encoding.
        let inputContext = CIContext(options: [
            .workingColorSpace: inputColorSpace,
            .workingFormat: CIFormat.RGBAh.rawValue
        ])
        guard let inputImage = inputContext.createCGImage(
            source,
            from: extent,
            format: .RGBAh,
            colorSpace: inputColorSpace
        ) else {
            throw StudioError.invalidLUT(message: "无法转换 Technical LUT 的输入色彩空间。")
        }

        let encodedInput = CIImage(cgImage: inputImage, options: [.colorSpace: inputColorSpace])

        // The untouched branch must make the same input → output encoding
        // conversion as the LUT branch before a partial-strength blend. Mixing
        // input-encoded RGB with output-encoded RGB and then labelling it as
        // output would be colourimetrically invalid.
        func convertedUntouchedOutput() throws -> CIImage {
            let outputContext = CIContext(options: [
                .workingColorSpace: outputColorSpace,
                .workingFormat: CIFormat.RGBAh.rawValue
            ])
            guard let untouchedOutputImage = outputContext.createCGImage(
                encodedInput,
                from: extent,
                format: .RGBAh,
                colorSpace: outputColorSpace
            ) else {
                throw StudioError.invalidLUT(message: "无法转换 Technical LUT 的未处理输出色彩空间。")
            }
            return CIImage(cgImage: untouchedOutputImage, options: [.colorSpace: outputColorSpace])
        }

        // Zero strength still crosses the declared input → output bridge; it
        // must not return the source attachment. It intentionally avoids the
        // expensive cube evaluation while doing so.
        if normalizedStrength == 0 {
            return try convertedUntouchedOutput()
        }

        // A cube maps encoded RGB numbers. Disable implicit working/output
        // matching for this exact operation. Both branches below are then
        // explicitly materialised and tagged with the same output profile
        // before their numeric values are blended.
        let rawContext = CIContext(options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .workingFormat: CIFormat.RGBAh.rawValue
        ])
        let encodedLUTOutput = LUTProcessor.apply(lut, to: encodedInput, strength: 1)
        guard let fullLUTOutputImage = rawContext.createCGImage(
            encodedLUTOutput,
            from: extent,
            format: .RGBAh,
            colorSpace: outputColorSpace
        ) else {
            throw StudioError.invalidLUT(message: "无法写入 Technical LUT 的输出色彩空间。")
        }

        let fullLUTOutput = CIImage(cgImage: fullLUTOutputImage, options: [.colorSpace: outputColorSpace])
        if normalizedStrength == 1 {
            return fullLUTOutput
        }
        let untouchedOutput = try convertedUntouchedOutput()
        let blendedOutput = fullLUTOutput.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: untouchedOutput,
            kCIInputMaskImageKey: CIImage(color: CIColor(
                red: CGFloat(normalizedStrength),
                green: CGFloat(normalizedStrength),
                blue: CGFloat(normalizedStrength),
                alpha: 1
            )).cropped(to: extent)
        ])

        guard let outputImage = rawContext.createCGImage(
            blendedOutput,
            from: extent,
            format: .RGBAh,
            colorSpace: outputColorSpace
        ) else {
            throw StudioError.invalidLUT(message: "无法混合 Technical LUT 的输出色彩空间。")
        }
        // `rawContext` intentionally leaves the cube's RGB code values
        // untouched after the two branches have become output-encoded.
        // Re-attaching the declared output profile tells the next renderer how
        // to interpret the result, so its normal working/output ColorSync
        // conversion is based on LUT metadata rather than the original source
        // profile.
        return CIImage(cgImage: outputImage, options: [.colorSpace: outputColorSpace])
    }
}
