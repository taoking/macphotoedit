import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// The result of one diagnostic render stage. The diagnostic is deliberately
/// observational: a rejected decoder profile remains a reported failure rather
/// than being guessed as sRGB so a later render can continue incorrectly.
struct RAWDiagnosticOperation: Sendable, Equatable {
    let succeeded: Bool
    let detail: String?

    static let notAttempted = Self(succeeded: false, detail: "未执行")

    static func success() -> Self { Self(succeeded: true, detail: nil) }
    static func failure(_ error: Error) -> Self {
        Self(succeeded: false, detail: error.localizedDescription)
    }
}

enum RAWICCProfileMatchResult: String, Sendable, Equatable {
    case matchedRecognizedDescriptor
    case missingICCProfile
    case unrecognizedICCProfile

    var title: String {
        switch self {
        case .matchedRecognizedDescriptor: "匹配已识别的 PhotoColorDescriptor"
        case .missingICCProfile: "缺少 ICC payload"
        case .unrecognizedICCProfile: "ICC payload 未匹配当前严格契约"
        }
    }
}

struct RAWDecodedDimensions: Sendable, Equatable {
    let width: Int
    let height: Int
}

/// A text-report-friendly description of what the host RAW decoder actually
/// returned. It has no source URL or image bitmap field, so recording it never
/// copies user RAW media into Catalog or diagnostic output.
struct RAWMediaDiagnosticReport: Sendable, Equatable {
    let sourceFilename: String
    let fileExtension: String
    let fileSize: Int64?
    let cirawFilterAvailable: Bool
    let decodedDimensions: RAWDecodedDimensions?
    let decoderColorSpaceName: String?
    let decoderICCProfileMatch: RAWICCProfileMatchResult?
    let recognizedDecoderDescriptor: PhotoColorDescriptor?
    let normalizedWorkingDescriptor: PhotoColorDescriptor?
    let availableRAWControls: [String]
    let previewRender: RAWDiagnosticOperation
    let export: RAWDiagnosticOperation
    let outputICCProfileName: String?
    let outputICCMatchesRequested: Bool?
    let sourceSignatureUnchanged: Bool?

    func text() -> String {
        let dimensions = decodedDimensions.map { "\($0.width) × \($0.height)" } ?? "不可用"
        let sourceSize = fileSize.map(String.init) ?? "不可用"
        let decoderName = decoderColorSpaceName ?? "不可用"
        let profileMatch = decoderICCProfileMatch?.title ?? "不可用"
        let descriptor = recognizedDecoderDescriptor?.title ?? "未识别（保持拒绝）"
        let working = normalizedWorkingDescriptor?.title ?? "未建立"
        let controls = availableRAWControls.isEmpty ? "无" : availableRAWControls.joined(separator: "、")
        let outputProfile = outputICCProfileName ?? "不可用"
        let outputMatch = outputICCMatchesRequested.map { $0 ? "匹配请求输出" : "不匹配请求输出" } ?? "不可用"
        let sourceIntegrity = sourceSignatureUnchanged.map { $0 ? "文件大小与修改时间未变化" : "检测期间签名发生变化" } ?? "无法比较"
        return """
        Mac Photo Studio RAW Diagnostic
        Source file: \(sourceFilename)
        File extension: \(fileExtension.isEmpty ? "（无）" : fileExtension)
        File size: \(sourceSize) bytes
        CIRAWFilter availability: \(cirawFilterAvailable ? "available" : "unavailable")
        Decoded dimensions: \(dimensions)
        Decoder CIImage color space: \(decoderName)
        Decoder ICC payload match: \(profileMatch)
        App-recognized PhotoColorDescriptor: \(descriptor)
        Pipeline normalized working descriptor: \(working)
        Available RAW controls: \(controls)
        Preview render: \(previewRender.succeeded ? "PASS" : "FAIL")\(previewRender.detail.map { " — \($0)" } ?? "")
        Export: \(export.succeeded ? "PASS" : "FAIL")\(export.detail.map { " — \($0)" } ?? "")
        Output ICC profile: \(outputProfile)
        Output ICC verification: \(outputMatch)
        Source integrity after diagnostic: \(sourceIntegrity)
        """
    }

    /// Diagnostic reports belong to the disposable app log area, never beside
    /// the inspected RAW file. The report is small UTF-8 text, not a bitmap.
    func write(to logsDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let stem = URL(filePath: sourceFilename).deletingPathExtension().lastPathComponent
        let safeStem = stem.isEmpty ? "raw" : stem
        let destination = logsDirectory
            .appending(path: "raw-diagnostic-\(safeStem)-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        try Data(text().utf8).write(to: destination, options: .atomic)
        return destination
    }
}

/// Reusable developer diagnostic for a user-authorised ARW/DNG. It reads the
/// source through Core Image, writes any test export only into a temporary
/// directory, then removes it. The only retained artefact is an optional text
/// report chosen by the caller under Application Support/logs.
enum RAWMediaDiagnosticService {
    static func inspect(
        sourceURL: URL,
        rawState: RAWEditState = .identity,
        photoState: PhotoEditState = .identity,
        outputColorSpace: PhotoColorSpace = .sRGB,
        previewMaximumPixelSize: Int = 2_048
    ) async -> RAWMediaDiagnosticReport {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard RAWFormat.isRAW(fileExtension) else {
            let sourceSignature = SourceSignature(url: sourceURL)
            return RAWMediaDiagnosticReport(
                sourceFilename: sourceURL.lastPathComponent,
                fileExtension: fileExtension,
                fileSize: sourceSignature.fileSize,
                cirawFilterAvailable: false,
                decodedDimensions: nil,
                decoderColorSpaceName: nil,
                decoderICCProfileMatch: nil,
                recognizedDecoderDescriptor: nil,
                normalizedWorkingDescriptor: nil,
                availableRAWControls: [],
                previewRender: RAWDiagnosticOperation(succeeded: false, detail: "仅支持 ARW 和 DNG。"),
                export: RAWDiagnosticOperation(succeeded: false, detail: "仅支持 ARW 和 DNG。"),
                outputICCProfileName: nil,
                outputICCMatchesRequested: nil,
                sourceSignatureUnchanged: sourceSignature.matches(SourceSignature(url: sourceURL))
            )
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let beforeSignature = SourceSignature(url: sourceURL)

        guard let filter = CIRAWFilter(imageURL: sourceURL) else {
            return unavailableReport(
                sourceURL: sourceURL,
                beforeSignature: beforeSignature,
                detail: "系统无法为该文件创建 CIRAWFilter。"
            )
        }

        let capabilities = RAWImagePipeline.capabilities(for: filter)
        guard let decoderOutput = filter.outputImage else {
            return unavailableReport(
                sourceURL: sourceURL,
                beforeSignature: beforeSignature,
                capabilities: capabilities,
                cirawFilterAvailable: true,
                detail: "CIRAWFilter 未返回 outputImage。"
            )
        }

        let decoderColorSpace = decoderOutput.colorSpace
        let recognizedDescriptor = decoderColorSpace.flatMap(PhotoColorDescriptor.exactColorSyncDescriptor(for:))
        let iccMatch: RAWICCProfileMatchResult = if decoderColorSpace == nil {
            .missingICCProfile
        } else if recognizedDescriptor == nil {
            .unrecognizedICCProfile
        } else {
            .matchedRecognizedDescriptor
        }
        let dimensions = RAWDecodedDimensions(
            width: Int(decoderOutput.extent.width.rounded()),
            height: Int(decoderOutput.extent.height.rounded())
        )

        var previewResult: RAWDiagnosticOperation = .notAttempted
        do {
            _ = try await RAWPreviewRenderer().render(
                sourceURL: sourceURL,
                rawState: rawState,
                photoState: photoState,
                lut: nil,
                maximumPixelSize: max(128, previewMaximumPixelSize)
            )
            previewResult = .success()
        } catch {
            previewResult = .failure(error)
        }

        var exportResult: RAWDiagnosticOperation = .notAttempted
        var outputICCProfileName: String?
        var outputICCMatchesRequested: Bool?
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MacPhotoStudio-RAW-Diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            let temporaryExport = temporaryDirectory.appending(path: "diagnostic-export").appendingPathExtension("jpg")
            var exportedPhotoState = photoState
            exportedPhotoState.colorPipeline.outputColorSpace = outputColorSpace
            exportedPhotoState.colorPipeline.dynamicRange = .sdr
            try await RAWExportRenderer().export(
                sourceURL: sourceURL,
                rawState: rawState,
                photoState: exportedPhotoState,
                lut: nil,
                destinationURL: temporaryExport,
                options: PhotoExportOptions(
                    format: .jpeg,
                    keepsMetadata: false,
                    outputColorSpace: outputColorSpace,
                    dynamicRange: .sdr
                )
            )
            guard let embeddedOutputColorSpace = embeddedColorSpace(at: temporaryExport) else {
                throw StudioError.exportFailed(message: "诊断临时导出无法重新读取 ICC profile。")
            }
            outputICCProfileName = embeddedOutputColorSpace.name as String?
            outputICCMatchesRequested = outputColorSpaceMatchesRequested(
                embeddedOutputColorSpace,
                requested: outputColorSpace
            )
            exportResult = .success()
        } catch {
            exportResult = .failure(error)
        }

        return RAWMediaDiagnosticReport(
            sourceFilename: sourceURL.lastPathComponent,
            fileExtension: fileExtension,
            fileSize: beforeSignature.fileSize,
            cirawFilterAvailable: true,
            decodedDimensions: dimensions,
            decoderColorSpaceName: decoderColorSpace?.name as String?,
            decoderICCProfileMatch: iccMatch,
            recognizedDecoderDescriptor: recognizedDescriptor,
            normalizedWorkingDescriptor: previewResult.succeeded ? .linearWorking : nil,
            availableRAWControls: capabilities.availableControlNames,
            previewRender: previewResult,
            export: exportResult,
            outputICCProfileName: outputICCProfileName,
            outputICCMatchesRequested: outputICCMatchesRequested,
            sourceSignatureUnchanged: beforeSignature.matches(SourceSignature(url: sourceURL))
        )
    }

    private static func unavailableReport(
        sourceURL: URL,
        beforeSignature: SourceSignature,
        capabilities: RAWCapabilities = RAWCapabilities(),
        cirawFilterAvailable: Bool = false,
        detail: String
    ) -> RAWMediaDiagnosticReport {
        RAWMediaDiagnosticReport(
            sourceFilename: sourceURL.lastPathComponent,
            fileExtension: sourceURL.pathExtension.lowercased(),
            fileSize: beforeSignature.fileSize,
            cirawFilterAvailable: cirawFilterAvailable,
            decodedDimensions: nil,
            decoderColorSpaceName: nil,
            decoderICCProfileMatch: nil,
            recognizedDecoderDescriptor: nil,
            normalizedWorkingDescriptor: nil,
            availableRAWControls: capabilities.availableControlNames,
            previewRender: RAWDiagnosticOperation(succeeded: false, detail: detail),
            export: RAWDiagnosticOperation(succeeded: false, detail: detail),
            outputICCProfileName: nil,
            outputICCMatchesRequested: nil,
            sourceSignatureUnchanged: beforeSignature.matches(SourceSignature(url: sourceURL))
        )
    }

    private static func embeddedColorSpace(at url: URL) -> CGColorSpace? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image.colorSpace
    }

    private static func outputColorSpaceMatchesRequested(
        _ output: CGColorSpace,
        requested: PhotoColorSpace
    ) -> Bool {
        requested.matchesEmbeddedProfile(of: output)
    }
}

private struct SourceSignature: Equatable {
    let fileSize: Int64?
    let modificationDate: Date?

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        fileSize = values?.fileSize.map(Int64.init)
        modificationDate = values?.contentModificationDate
    }

    func matches(_ other: SourceSignature) -> Bool? {
        guard fileSize != nil || modificationDate != nil,
              other.fileSize != nil || other.modificationDate != nil else { return nil }
        return fileSize == other.fileSize && modificationDate == other.modificationDate
    }
}
