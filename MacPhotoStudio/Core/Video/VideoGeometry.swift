import CoreGraphics

/// The single source of truth for video display geometry. AVFoundation keeps
/// encoded pixels in `naturalSize`; the preferred transform carries camera
/// orientation and must be applied before presenting metadata or choosing an
/// export canvas.
enum VideoGeometry {
    static func displaySize(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGSize {
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(
            width: normalizedDimension(abs(transformed.width)),
            height: normalizedDimension(abs(transformed.height))
        )
    }

    private static func normalizedDimension(_ value: CGFloat) -> CGFloat {
        let rounded = value.rounded()
        return abs(value - rounded) < 0.001 ? rounded : value
    }
}
