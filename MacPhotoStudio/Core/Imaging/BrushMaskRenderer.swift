import CoreGraphics
import CoreImage
import Foundation

/// Rasterizes non-destructive vector brush strokes only while an image is being
/// rendered. The resulting grayscale texture is bounded in memory and is never
/// encoded into Catalog SQLite state.
enum BrushMaskRenderer {
    private static let textureCache = BrushMaskTextureCache()

    static func image(for strokes: [BrushStroke], extent: CGRect) -> CIImage? {
        guard strokes.contains(where: \.hasPoints),
              extent.width > 0,
              extent.height > 0
        else { return nil }

        let width = Int(extent.width.rounded(.up))
        let height = Int(extent.height.rounded(.up))
        guard width > 0, height > 0, width <= Int.max / height else { return nil }

        let key = BrushMaskTextureCacheKey(width: width, height: height, strokes: strokes)
        let byteCount = width * height
        guard let cgImage = textureCache.image(for: key, byteCount: byteCount, make: {
            rasterize(strokes: strokes, width: width, height: height)
        }) else { return nil }

        return CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    private static func rasterize(strokes: [BrushStroke], width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let scale = CGFloat(min(width, height))
        for stroke in strokes where stroke.hasPoints && stroke.clampedOpacity > 0 {
            let points = stroke.points.map { point in
                let point = point.clamped
                return CGPoint(
                    x: CGFloat(point.x) * CGFloat(max(width - 1, 0)),
                    y: CGFloat(point.y) * CGFloat(max(height - 1, 0))
                )
            }
            let radius = max(0.5, CGFloat(stroke.clampedRadius) * scale)
            draw(stroke: stroke, through: points, radius: radius, in: context, colorSpace: colorSpace)
        }
        return context.makeImage()
    }

    private static func draw(
        stroke: BrushStroke,
        through points: [CGPoint],
        radius: CGFloat,
        in context: CGContext,
        colorSpace: CGColorSpace
    ) {
        guard let first = points.first else { return }
        let spacing = max(1, radius * 0.5)
        drawStamp(stroke: stroke, at: first, radius: radius, in: context, colorSpace: colorSpace)
        for (start, end) in zip(points, points.dropFirst()) {
            let distance = hypot(end.x - start.x, end.y - start.y)
            let stepCount = max(1, Int(ceil(distance / spacing)))
            for step in 1...stepCount {
                let fraction = CGFloat(step) / CGFloat(stepCount)
                let point = CGPoint(
                    x: start.x + (end.x - start.x) * fraction,
                    y: start.y + (end.y - start.y) * fraction
                )
                drawStamp(stroke: stroke, at: point, radius: radius, in: context, colorSpace: colorSpace)
            }
        }
    }

    private static func drawStamp(
        stroke: BrushStroke,
        at point: CGPoint,
        radius: CGFloat,
        in context: CGContext,
        colorSpace: CGColorSpace
    ) {
        let gray: CGFloat = stroke.erase ? 0 : 1
        let opacity = CGFloat(stroke.clampedOpacity)
        let hardness = CGFloat(stroke.clampedHardness)
        let stamp = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        if hardness >= 0.999 {
            context.setFillColor(gray: gray, alpha: opacity)
            context.fillEllipse(in: stamp)
            return
        }

        let colors = [
            CGColor(gray: gray, alpha: opacity),
            CGColor(gray: gray, alpha: opacity),
            CGColor(gray: gray, alpha: 0)
        ] as CFArray
        let locations: [CGFloat] = [0, hardness, 1]
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors,
            locations: locations
        ) else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: point,
            startRadius: 0,
            endCenter: point,
            endRadius: radius,
            options: []
        )
    }
}

private struct BrushMaskTextureCacheKey: Hashable {
    let width: Int
    let height: Int
    let strokes: [BrushStroke]
}

/// The cache has both per-entry and total byte bounds. Full-resolution exports
/// larger than the entry limit are rasterized and immediately released; they do
/// not displace useful preview textures or become an unbounded derived cache.
private final class BrushMaskTextureCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [BrushMaskTextureCacheKey: CGImage] = [:]
    private var order: [BrushMaskTextureCacheKey] = []
    private var totalByteCount = 0
    private let maximumEntryByteCount = 16 * 1_024 * 1_024
    private let maximumTotalByteCount = 48 * 1_024 * 1_024

    func image(
        for key: BrushMaskTextureCacheKey,
        byteCount: Int,
        make: () -> CGImage?
    ) -> CGImage? {
        lock.lock()
        if let cached = images[key] {
            touch(key)
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let rendered = make() else { return nil }
        guard byteCount <= maximumEntryByteCount else { return rendered }

        lock.lock()
        defer { lock.unlock() }
        if let cached = images[key] {
            touch(key)
            return cached
        }
        images[key] = rendered
        order.append(key)
        totalByteCount += byteCount
        trimToBudget()
        return rendered
    }

    private func touch(_ key: BrushMaskTextureCacheKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func trimToBudget() {
        while totalByteCount > maximumTotalByteCount, let oldest = order.first {
            order.removeFirst()
            guard let image = images.removeValue(forKey: oldest) else { continue }
            totalByteCount -= image.width * image.height
        }
    }
}
