import AVFoundation
import CoreMedia
import Foundation
import ImageIO

struct MediaMetadataExtractor: Sendable {
    func extractPhoto(from url: URL) throws -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            throw StudioError.metadataExtractionFailed(path: url.path(percentEncoded: false))
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let isoValues = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber]

        return PhotoMetadata(
            width: integer(properties[kCGImagePropertyPixelWidth]),
            height: integer(properties[kCGImagePropertyPixelHeight]),
            captureDate: captureDate(
                exif[kCGImagePropertyExifDateTimeOriginal] as? String
                    ?? tiff[kCGImagePropertyTIFFDateTime] as? String
            ),
            cameraMake: string(tiff[kCGImagePropertyTIFFMake]),
            cameraModel: string(tiff[kCGImagePropertyTIFFModel]),
            lensModel: string(exif[kCGImagePropertyExifLensModel]),
            focalLength: number(exif[kCGImagePropertyExifFocalLength]),
            aperture: number(exif[kCGImagePropertyExifFNumber]),
            shutterSpeed: number(exif[kCGImagePropertyExifExposureTime]),
            iso: isoValues?.first?.intValue,
            orientation: integer(properties[kCGImagePropertyOrientation]),
            colorProfile: string(properties[kCGImagePropertyProfileName]),
            gpsLatitude: coordinate(
                gps[kCGImagePropertyGPSLatitude],
                reference: string(gps[kCGImagePropertyGPSLatitudeRef])
            ),
            gpsLongitude: coordinate(
                gps[kCGImagePropertyGPSLongitude],
                reference: string(gps[kCGImagePropertyGPSLongitudeRef])
            )
        )
    }

    func extractVideo(from url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let creationDateItem = try await asset.load(.creationDate)
        let creationDate: Date?
        if let creationDateItem {
            creationDate = try await creationDateItem.load(.dateValue)
        } else {
            creationDate = nil
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let videoTrack = tracks.first

        let naturalSize = try await videoTrack?.load(.naturalSize)
        let frameRate = try await videoTrack?.load(.nominalFrameRate)
        let formatDescriptions = try await videoTrack?.load(.formatDescriptions)
        let codec = formatDescriptions?.first.map { formatDescription in
            fourCharacterCode(CMFormatDescriptionGetMediaSubType(formatDescription))
        }

        return VideoMetadata(
            width: naturalSize.map { Int(abs($0.width)) },
            height: naturalSize.map { Int(abs($0.height)) },
            duration: duration.isNumeric ? CMTimeGetSeconds(duration) : nil,
            frameRate: frameRate.map(Double.init),
            codec: codec,
            creationDate: creationDate
        )
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private func integer(_ value: Any?) -> Int? {
        number(value).map(Int.init)
    }

    private func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSString:
            return value as String
        default:
            return nil
        }
    }

    private func captureDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }

    private func coordinate(_ value: Any?, reference: String?) -> Double? {
        guard let coordinate = number(value) else { return nil }
        switch reference?.uppercased() {
        case "S", "W": return -abs(coordinate)
        default: return coordinate
        }
    }

    private func fourCharacterCode(_ code: FourCharCode) -> String {
        let bigEndianCode = code.bigEndian
        let bytes = withUnsafeBytes(of: bigEndianCode) { Array($0) }
        let text = String(bytes: bytes, encoding: .ascii) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(format: "%08X", code)
            : text
    }
}
