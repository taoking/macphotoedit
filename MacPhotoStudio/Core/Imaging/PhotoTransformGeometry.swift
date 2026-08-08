import CoreGraphics
import CoreImage

/// The single transform contract shared by the Core Image render path and the
/// editor canvas. Local masks are persisted in normalized source coordinates;
/// this type converts them through the exact crop → flip → rotation transform
/// used by `PhotoImagePipeline` without making preview size part of state.
struct PhotoTransformGeometry {
    let sourceExtent: CGRect
    let transform: TransformAdjustments

    init(sourceExtent: CGRect, transform: TransformAdjustments) {
        self.sourceExtent = sourceExtent
        self.transform = transform
    }

    var cropRect: CGRect {
        let crop = transform.crop.clamped
        return CGRect(
            x: sourceExtent.minX + sourceExtent.width * crop.x,
            y: sourceExtent.minY + sourceExtent.height * crop.y,
            width: sourceExtent.width * crop.width,
            height: sourceExtent.height * crop.height
        )
    }

    /// This intentionally mirrors the construction order in the previous
    /// renderer implementation. Do not replace it with an independently
    /// derived UI-only formula.
    var affineTransform: CGAffineTransform {
        var affine = CGAffineTransform.identity
        if transform.flipHorizontal { affine = affine.scaledBy(x: -1, y: 1) }
        if transform.flipVertical { affine = affine.scaledBy(x: 1, y: -1) }
        let radians = (transform.rotationDegrees + transform.straightenDegrees) * .pi / 180
        if radians != 0 { affine = affine.rotated(by: radians) }
        return affine
    }

    /// Core Image reports the transformed extent after crop/affine processing.
    /// Canvas display coordinates are normalized inside this exact extent.
    var transformedExtent: CGRect { cropRect.applying(affineTransform).standardized }

    func applying(to image: CIImage) -> CIImage {
        image.cropped(to: cropRect).transformed(by: affineTransform)
    }

    func displayedNormalizedPoint(forSourceNormalized point: CGPoint) -> CGPoint {
        guard sourceExtent.width > 0, sourceExtent.height > 0,
              transformedExtent.width > 0, transformedExtent.height > 0
        else { return CGPoint(x: 0.5, y: 0.5) }
        let sourcePoint = CGPoint(
            x: sourceExtent.minX + sourceExtent.width * clamp(point.x),
            y: sourceExtent.minY + sourceExtent.height * clamp(point.y)
        )
        let transformed = sourcePoint.applying(affineTransform)
        let extent = transformedExtent
        return CGPoint(
            x: clamp((transformed.x - extent.minX) / extent.width),
            y: clamp((transformed.y - extent.minY) / extent.height)
        )
    }

    func sourceNormalizedPoint(forDisplayedNormalized point: CGPoint) -> CGPoint {
        guard sourceExtent.width > 0, sourceExtent.height > 0,
              transformedExtent.width > 0, transformedExtent.height > 0
        else { return CGPoint(x: 0.5, y: 0.5) }
        let extent = transformedExtent
        let transformedPoint = CGPoint(
            x: extent.minX + extent.width * clamp(point.x),
            y: extent.minY + extent.height * clamp(point.y)
        )
        let sourcePoint = transformedPoint.applying(affineTransform.inverted())
        return CGPoint(
            x: clamp((sourcePoint.x - sourceExtent.minX) / sourceExtent.width),
            y: clamp((sourcePoint.y - sourceExtent.minY) / sourceExtent.height)
        )
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }
}
