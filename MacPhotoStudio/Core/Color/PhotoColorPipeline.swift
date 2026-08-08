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

    static func inferred(fromProfileName profileName: String?) -> Self {
        let profile = profileName?.lowercased() ?? ""
        let transfer: PhotoTransferFunction
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
        return Self(colorSpace: colorSpace, transferFunction: transfer)
    }
}

enum PhotoDynamicRange: String, Codable, Sendable, CaseIterable, Identifiable {
    case sdr
    case hdr

    var id: String { rawValue }
    var title: String { self == .sdr ? "SDR" : "HDR（扩展动态范围）" }
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
    /// The app has a real extended-range preview path (half-float CI rendering
    /// plus an EDR-capable AppKit layer). Actual luminance/headroom is still a
    /// property of the user's display and is therefore manually verified.
    static let supportsExtendedRangePreview = true

    /// ImageIO's portable still-image APIs used by this app do not expose a
    /// reliable HDR gain-map writer on every supported macOS release. Returning
    /// false is deliberate: callers must tone-map to SDR rather than label an
    /// ordinary 8-bit HEIC/TIFF/JPEG as HDR.
    static let supportsHDRExport = false
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
    /// Core Image preserves the source ICC attachment through the processing
    /// graph. The render boundary below supplies the explicit output CGColorSpace
    /// to ColorSync; this function defines the non-destructive stage ordering.
    static func apply(
        source: CIImage,
        state: PhotoEditState,
        sourceColor: PhotoColorDescriptor,
        technicalLUT: CubeLUT?,
        creativeLUT: CubeLUT?,
        settings: PhotoColorPipelineSettings? = nil
    ) throws -> (image: CIImage, plan: ColorPipelinePlan) {
        let effectiveSettings = settings ?? state.colorPipeline
        let plan = try ColorPipelinePlan.make(
            source: sourceColor,
            settings: effectiveSettings,
            technicalLUT: technicalLUT,
            creativeLUT: creativeLUT
        )

        // Source → Working Color Space. Core Image keeps the source profile and
        // ColorSync resolves it when the renderer requests the explicit target.
        var image = source

        // Working → Technical Transform. The metadata validation above makes an
        // S-Log3→Rec.709 LUT impossible to accidentally apply to an sRGB JPEG.
        if let technicalLUT, let application = state.technicalLUT {
            image = LUTProcessor.apply(technicalLUT, to: image, strength: application.clampedStrength)
        }

        // Creative adjustments → Creative LUT → Output Transform.
        image = PhotoImagePipeline.applyCreativeAdjustments(state, to: image)
        image = PhotoImagePipeline.applyLocalMasks(state.localMasks, to: image)
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
