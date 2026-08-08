import CoreGraphics
import Foundation
import ImageIO

/// File types accepted by the Phase 16.5 validation command. They describe
/// user-selected *sources*; exports continue to use the product's supported
/// still-image encoders (JPEG, HEIF/HEIC and TIFF).
enum StillImageColorInputFormat: String, Sendable, Equatable {
    case jpeg
    case heic
    case png
    case tiff

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": self = .jpeg
        case "heic", "heif": self = .heic
        case "png": self = .png
        case "tif", "tiff": self = .tiff
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .heic: "HEIC/HEIF"
        case .png: "PNG"
        case .tiff: "TIFF"
        }
    }
}

enum StillImageColorProfileStatus: String, Sendable, Equatable {
    case matchedKnownDescriptor
    case missingICCProfile
    case unrecognizedICCProfile

    var title: String {
        switch self {
        case .matchedKnownDescriptor: "匹配已识别的 PhotoColorDescriptor"
        case .missingICCProfile: "缺少 ICC profile"
        case .unrecognizedICCProfile: "ICC profile 未匹配当前严格契约"
        }
    }
}

struct StillImageColorProfileInspection: Sendable, Equatable {
    let colorSpaceName: String?
    let descriptor: PhotoColorDescriptor?
    let status: StillImageColorProfileStatus

    static func inspect(_ colorSpace: CGColorSpace?) -> Self {
        guard let colorSpace else {
            return Self(colorSpaceName: nil, descriptor: nil, status: .missingICCProfile)
        }
        let descriptor = PhotoColorDescriptor.exactColorSyncDescriptor(for: colorSpace)
        return Self(
            colorSpaceName: colorSpace.name as String?,
            descriptor: descriptor,
            status: descriptor == nil ? .unrecognizedICCProfile : .matchedKnownDescriptor
        )
    }
}

struct StillImageColorPreviewValidation: Sendable, Equatable {
    let requestedColorSpace: PhotoColorSpace
    let succeeded: Bool
    let actualColorSpaceName: String?
    let matchesRequestedProfile: Bool?
    let detail: String?
}

struct StillImageColorExportValidation: Sendable, Equatable {
    let format: PhotoExportFormat
    let requestedColorSpace: PhotoColorSpace
    let filename: String
    let succeeded: Bool
    let actualColorSpaceName: String?
    let matchesRequestedProfile: Bool?
    let detail: String?
}

/// A retained text report plus a user-visible directory of new exports. The
/// report intentionally contains no copied source bitmap; the directory only
/// contains newly rendered validation output selected by the user.
struct StillImageColorDiagnosticReport: Sendable, Equatable {
    let sourceFilename: String
    let sourceFileExtension: String
    let sourceFormat: StillImageColorInputFormat?
    let sourceDimensions: RAWDecodedDimensions?
    let sourceProfile: StillImageColorProfileInspection?
    let validationDirectoryURL: URL?
    let previews: [StillImageColorPreviewValidation]
    let exports: [StillImageColorExportValidation]
    let sourceSignatureUnchanged: Bool?

    func text() -> String {
        let dimensions = sourceDimensions.map { "\($0.width) × \($0.height)" } ?? "不可用"
        let sourceProfileName = sourceProfile?.colorSpaceName ?? "不可用"
        let sourceDescriptor = sourceProfile?.descriptor?.title ?? "未识别（验证保持拒绝）"
        let profileStatus = sourceProfile?.status.title ?? "不可用"
        let validationDirectory = validationDirectoryURL?.path(percentEncoded: false) ?? "未创建"
        let sourceIntegrity = sourceSignatureUnchanged.map {
            $0 ? "文件大小与修改时间未变化" : "检测期间签名发生变化"
        } ?? "无法比较"
        let previewRows = previews.map { preview in
            let actual = preview.actualColorSpaceName ?? "不可用"
            let match = preview.matchesRequestedProfile.map { $0 ? "匹配请求输出" : "不匹配请求输出" } ?? "不可用"
            return "Preview \(preview.requestedColorSpace.title): \(preview.succeeded ? "PASS" : "FAIL") — actual ICC: \(actual); verification: \(match)\(preview.detail.map { "; \($0)" } ?? "")"
        }
        let exportRows = exports.map { export in
            let actual = export.actualColorSpaceName ?? "不可用"
            let match = export.matchesRequestedProfile.map { $0 ? "匹配请求输出" : "不匹配请求输出" } ?? "不可用"
            return "Export \(export.format.title) / \(export.requestedColorSpace.title) [\(export.filename)]: \(export.succeeded ? "PASS" : "FAIL") — actual ICC: \(actual); verification: \(match)\(export.detail.map { "; \($0)" } ?? "")"
        }
        return ([
            "Mac Photo Studio Still Image Color Validation",
            "Source file: \(sourceFilename)",
            "Source extension: \(sourceFileExtension.isEmpty ? "（无）" : sourceFileExtension)",
            "Source format: \(sourceFormat?.title ?? "不受支持")",
            "Source dimensions: \(dimensions)",
            "Source ImageIO color space: \(sourceProfileName)",
            "Source ICC status: \(profileStatus)",
            "Source PhotoColorDescriptor: \(sourceDescriptor)",
            "Validation exports directory: \(validationDirectory)",
            "",
            "Preview validation:"
        ] + previewRows + ["", "Export validation (reopened through ImageIO):"] + exportRows + [
            "",
            "Source integrity after validation: \(sourceIntegrity)",
            "Rec.2020 validation is SDR only: it uses Rec.2020 primaries with the BT.709 SDR transfer function and does not claim HDR or gain-map output."
        ]).joined(separator: "\n")
    }

    /// The retained artefact is a small UTF-8 text log. Validation image output
    /// stays only in the explicitly user-selected destination directory.
    func write(to logsDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let stem = URL(filePath: sourceFilename).deletingPathExtension().lastPathComponent
        let safeStem = stem.isEmpty ? "image" : stem
        let destination = logsDirectory
            .appending(path: "still-image-color-validation-\(safeStem)-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        try Data(text().utf8).write(to: destination, options: .atomic)
        return destination
    }
}

/// Runs a real preview and full-resolution export matrix for an authorised
/// still image. It deliberately validates source profiles exactly, so an
/// absent or unfamiliar source ICC is reported rather than guessed as sRGB.
enum StillImageColorDiagnosticService {
    static func validate(
        sourceURL: URL,
        outputRootURL: URL,
        previewMaximumPixelSize: Int = 2_048
    ) async -> StillImageColorDiagnosticReport {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard let sourceFormat = StillImageColorInputFormat(fileExtension: fileExtension) else {
            let signature = StillImageSourceSignature(url: sourceURL)
            return StillImageColorDiagnosticReport(
                sourceFilename: sourceURL.lastPathComponent,
                sourceFileExtension: fileExtension,
                sourceFormat: nil,
                sourceDimensions: nil,
                sourceProfile: nil,
                validationDirectoryURL: nil,
                previews: unsupportedPreviewResults(detail: "仅支持 JPEG、HEIC/HEIF、PNG 和 TIFF 源文件。"),
                exports: unsupportedExportResults(detail: "仅支持 JPEG、HEIC/HEIF、PNG 和 TIFF 源文件。"),
                sourceSignatureUnchanged: signature.matches(StillImageSourceSignature(url: sourceURL))
            )
        }

        let sourceAccessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if sourceAccessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let outputAccessed = outputRootURL.startAccessingSecurityScopedResource()
        defer {
            if outputAccessed { outputRootURL.stopAccessingSecurityScopedResource() }
        }

        let beforeSignature = StillImageSourceSignature(url: sourceURL)
        guard let sourceImage = image(at: sourceURL) else {
            return unavailableReport(
                sourceURL: sourceURL,
                sourceFormat: sourceFormat,
                beforeSignature: beforeSignature,
                detail: "ImageIO 无法读取此图像。"
            )
        }

        let sourceProfile = StillImageColorProfileInspection.inspect(sourceImage.colorSpace)
        let dimensions = RAWDecodedDimensions(width: sourceImage.width, height: sourceImage.height)
        guard let sourceDescriptor = sourceProfile.descriptor else {
            return StillImageColorDiagnosticReport(
                sourceFilename: sourceURL.lastPathComponent,
                sourceFileExtension: fileExtension,
                sourceFormat: sourceFormat,
                sourceDimensions: dimensions,
                sourceProfile: sourceProfile,
                validationDirectoryURL: nil,
                previews: unsupportedPreviewResults(detail: "源 ICC 未匹配严格 ColorSync 契约；未假定为 sRGB。"),
                exports: unsupportedExportResults(detail: "源 ICC 未匹配严格 ColorSync 契约；未创建验证导出。"),
                sourceSignatureUnchanged: beforeSignature.matches(StillImageSourceSignature(url: sourceURL))
            )
        }

        let validationDirectory = outputRootURL.appending(
            path: "MacPhotoStudio-Still-Color-Validation-\(safeStem(for: sourceURL))-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        do {
            try FileManager.default.createDirectory(at: validationDirectory, withIntermediateDirectories: false)
        } catch {
            return StillImageColorDiagnosticReport(
                sourceFilename: sourceURL.lastPathComponent,
                sourceFileExtension: fileExtension,
                sourceFormat: sourceFormat,
                sourceDimensions: dimensions,
                sourceProfile: sourceProfile,
                validationDirectoryURL: nil,
                previews: unsupportedPreviewResults(detail: "无法创建验证输出目录：\(error.localizedDescription)"),
                exports: unsupportedExportResults(detail: "无法创建验证输出目录：\(error.localizedDescription)"),
                sourceSignatureUnchanged: beforeSignature.matches(StillImageSourceSignature(url: sourceURL))
            )
        }

        let previewRenderer = PreviewRenderer()
        let exportRenderer = PhotoFileExportRenderer()
        var previews: [StillImageColorPreviewValidation] = []
        var exports: [StillImageColorExportValidation] = []

        for outputColorSpace in PhotoColorSpace.outputSpaces {
            var state = PhotoEditState.identity
            state.colorPipeline = PhotoColorPipelineSettings(
                outputColorSpace: outputColorSpace,
                dynamicRange: .sdr
            )
            do {
                let preview = try await previewRenderer.render(
                    sourceURL: sourceURL,
                    state: state,
                    lut: nil,
                    sourceColor: sourceDescriptor,
                    maximumPixelSize: max(128, previewMaximumPixelSize)
                )
                let previewImage = image(from: preview.imageData)
                let inspection = StillImageColorProfileInspection.inspect(previewImage?.colorSpace)
                let matches = previewImage?.colorSpace.map { outputColorSpace.matchesEmbeddedProfile(of: $0) }
                previews.append(
                    StillImageColorPreviewValidation(
                        requestedColorSpace: outputColorSpace,
                        succeeded: matches == true,
                        actualColorSpaceName: inspection.colorSpaceName,
                        matchesRequestedProfile: matches,
                        detail: inspection.colorSpaceName == nil ? "无法重新读取预览 ICC profile。" : nil
                    )
                )
            } catch {
                previews.append(
                    StillImageColorPreviewValidation(
                        requestedColorSpace: outputColorSpace,
                        succeeded: false,
                        actualColorSpaceName: nil,
                        matchesRequestedProfile: nil,
                        detail: error.localizedDescription
                    )
                )
            }

            for format in PhotoExportFormat.allCases {
                let filename = "\(outputColorSpace.rawValue).\(format.filenameExtension)"
                guard format.isSupported else {
                    exports.append(
                        StillImageColorExportValidation(
                            format: format,
                            requestedColorSpace: outputColorSpace,
                            filename: filename,
                            succeeded: false,
                            actualColorSpaceName: nil,
                            matchesRequestedProfile: nil,
                            detail: "当前 macOS ImageIO 不支持 \(format.title) 编码。"
                        )
                    )
                    continue
                }
                let destinationURL = validationDirectory.appending(path: filename)
                do {
                    try await exportRenderer.export(
                        sourceURL: sourceURL,
                        state: state,
                        lut: nil,
                        sourceColor: sourceDescriptor,
                        destinationURL: destinationURL,
                        options: PhotoExportOptions(
                            format: format,
                            keepsMetadata: false,
                            outputColorSpace: outputColorSpace,
                            dynamicRange: .sdr
                        ),
                        allowsOverwrite: false
                    )
                    let inspection = StillImageColorProfileInspection.inspect(image(at: destinationURL)?.colorSpace)
                    let matches = image(at: destinationURL)?.colorSpace.map { outputColorSpace.matchesEmbeddedProfile(of: $0) }
                    exports.append(
                        StillImageColorExportValidation(
                            format: format,
                            requestedColorSpace: outputColorSpace,
                            filename: filename,
                            succeeded: matches == true,
                            actualColorSpaceName: inspection.colorSpaceName,
                            matchesRequestedProfile: matches,
                            detail: matches == nil ? "无法重新读取导出文件的 ICC profile。" : nil
                        )
                    )
                } catch {
                    exports.append(
                        StillImageColorExportValidation(
                            format: format,
                            requestedColorSpace: outputColorSpace,
                            filename: filename,
                            succeeded: false,
                            actualColorSpaceName: nil,
                            matchesRequestedProfile: nil,
                            detail: error.localizedDescription
                        )
                    )
                }
            }
        }

        return StillImageColorDiagnosticReport(
            sourceFilename: sourceURL.lastPathComponent,
            sourceFileExtension: fileExtension,
            sourceFormat: sourceFormat,
            sourceDimensions: dimensions,
            sourceProfile: sourceProfile,
            validationDirectoryURL: validationDirectory,
            previews: previews,
            exports: exports,
            sourceSignatureUnchanged: beforeSignature.matches(StillImageSourceSignature(url: sourceURL))
        )
    }

    private static func unavailableReport(
        sourceURL: URL,
        sourceFormat: StillImageColorInputFormat,
        beforeSignature: StillImageSourceSignature,
        detail: String
    ) -> StillImageColorDiagnosticReport {
        StillImageColorDiagnosticReport(
            sourceFilename: sourceURL.lastPathComponent,
            sourceFileExtension: sourceURL.pathExtension.lowercased(),
            sourceFormat: sourceFormat,
            sourceDimensions: nil,
            sourceProfile: nil,
            validationDirectoryURL: nil,
            previews: unsupportedPreviewResults(detail: detail),
            exports: unsupportedExportResults(detail: detail),
            sourceSignatureUnchanged: beforeSignature.matches(StillImageSourceSignature(url: sourceURL))
        )
    }

    private static func unsupportedPreviewResults(detail: String) -> [StillImageColorPreviewValidation] {
        PhotoColorSpace.outputSpaces.map {
            StillImageColorPreviewValidation(
                requestedColorSpace: $0,
                succeeded: false,
                actualColorSpaceName: nil,
                matchesRequestedProfile: nil,
                detail: detail
            )
        }
    }

    private static func unsupportedExportResults(detail: String) -> [StillImageColorExportValidation] {
        PhotoColorSpace.outputSpaces.flatMap { colorSpace in
            PhotoExportFormat.allCases.map { format in
                StillImageColorExportValidation(
                    format: format,
                    requestedColorSpace: colorSpace,
                    filename: "\(colorSpace.rawValue).\(format.filenameExtension)",
                    succeeded: false,
                    actualColorSpaceName: nil,
                    matchesRequestedProfile: nil,
                    detail: detail
                )
            }
        }
    }

    private static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func safeStem(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "image" : stem
    }
}

private struct StillImageSourceSignature: Equatable {
    let fileSize: Int64?
    let modificationDate: Date?

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        fileSize = values?.fileSize.map(Int64.init)
        modificationDate = values?.contentModificationDate
    }

    func matches(_ other: StillImageSourceSignature) -> Bool? {
        guard fileSize != nil || modificationDate != nil,
              other.fileSize != nil || other.modificationDate != nil else { return nil }
        return fileSize == other.fileSize && modificationDate == other.modificationDate
    }
}
