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
        let displayed = displayedNormalizedPointUnclamped(forSourceNormalized: CGPoint(
            x: clamp(point.x),
            y: clamp(point.y)
        ))
        return CGPoint(x: clamp(displayed.x), y: clamp(displayed.y))
    }

    /// Converts a source point to the transformed display coordinate system
    /// without treating it as an editable, in-bounds position. This is used
    /// for the mathematical endpoint of a radius/vector: it may legitimately
    /// lie outside the source image or the visible crop.
    func displayedNormalizedPointUnclamped(forSourceNormalized point: CGPoint) -> CGPoint {
        guard sourceExtent.width > 0, sourceExtent.height > 0,
              transformedExtent.width > 0, transformedExtent.height > 0
        else { return CGPoint(x: 0.5, y: 0.5) }
        let sourcePoint = CGPoint(
            x: sourceExtent.minX + sourceExtent.width * point.x,
            y: sourceExtent.minY + sourceExtent.height * point.y
        )
        let transformed = sourcePoint.applying(affineTransform)
        let extent = transformedExtent
        return CGPoint(
            x: (transformed.x - extent.minX) / extent.width,
            y: (transformed.y - extent.minY) / extent.height
        )
    }

    /// Converts a source-pixel vector into display-normalized coordinates.
    /// Unlike a point mapping, a vector has no image-boundary semantics and is
    /// intentionally never clamped. This keeps radial and brush radii correct
    /// when their conceptual reference endpoint lies beyond an image edge or
    /// crop boundary.
    func displayedNormalizedVector(forSourceVector vector: CGVector) -> CGVector {
        guard transformedExtent.width > 0, transformedExtent.height > 0
        else { return .zero }

        // `affineTransform` currently has no translation, but subtracting the
        // transformed origin keeps vector semantics correct if that changes.
        let origin = CGPoint.zero.applying(affineTransform)
        let endpoint = CGPoint(x: vector.dx, y: vector.dy).applying(affineTransform)
        let transformed = CGVector(dx: endpoint.x - origin.x, dy: endpoint.y - origin.y)
        let extent = transformedExtent
        return CGVector(
            dx: transformed.dx / extent.width,
            dy: transformed.dy / extent.height
        )
    }

    /// Turns a physical source-pixel distance into a display vector. Radius
    /// callers provide a source-space direction, so the resulting magnitude
    /// remains independent of the radius centre and any viewport clipping.
    func displayedNormalizedVector(
        forSourceDistance distance: CGFloat,
        direction: CGVector = CGVector(dx: 1, dy: 0)
    ) -> CGVector {
        let length = hypot(direction.dx, direction.dy)
        guard length > 0 else { return .zero }
        return displayedNormalizedVector(forSourceVector: CGVector(
            dx: direction.dx / length * distance,
            dy: direction.dy / length * distance
        ))
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
