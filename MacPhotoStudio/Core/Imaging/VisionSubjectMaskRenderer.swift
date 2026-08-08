import CoreGraphics
import CoreImage
import ImageIO
import Vision

/// The target SDK exposes a local, on-device foreground-instance request on
/// macOS 14 and later. It is intentionally described as a foreground subject
/// mask: Vision can return salient people, animals, and objects, but this app
/// does not promise semantic class selection or sky segmentation.
enum VisionSubjectMaskCapabilities {
    static var supportsForegroundSubjectMask: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }
}

enum VisionSubjectMaskRenderer {
    static func image(for source: CIImage) -> CIImage? {
        guard VisionSubjectMaskCapabilities.supportsForegroundSubjectMask,
              source.extent.width > 0,
              source.extent.height > 0
        else { return nil }

        if #available(macOS 14.0, *) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: source, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first,
                      !observation.allInstances.isEmpty
                else { return nil }
                let pixelBuffer = try observation.generateScaledMaskForImage(
                    forInstances: observation.allInstances,
                    from: handler
                )
                return align(CIImage(cvPixelBuffer: pixelBuffer), to: source.extent)
            } catch {
                // A failed Vision request must fail closed: local adjustments
                // are never applied across the entire image as a substitute.
                return nil
            }
        }
        return nil
    }

    private static func align(_ mask: CIImage, to sourceExtent: CGRect) -> CIImage? {
        let maskExtent = mask.extent
        guard maskExtent.width > 0, maskExtent.height > 0 else { return nil }
        let normalized = mask.transformed(by: CGAffineTransform(
            translationX: -maskExtent.minX,
            y: -maskExtent.minY
        ))
        let scaled = normalized.transformed(by: CGAffineTransform(
            scaleX: sourceExtent.width / maskExtent.width,
            y: sourceExtent.height / maskExtent.height
        ))
        return scaled
            .transformed(by: CGAffineTransform(translationX: sourceExtent.minX, y: sourceExtent.minY))
            .cropped(to: sourceExtent)
    }
}
