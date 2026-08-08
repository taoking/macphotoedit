import CoreGraphics
import CoreImage
import Foundation

/// A stable cache identity for a foreground-subject request. It deliberately
/// excludes photo-editing controls: subject selection is derived from the
/// pre-local-adjustment source, not from exposure, colour or mask order.
struct SubjectMaskCacheKey: Hashable {
    enum Rendition: String, Hashable {
        case preview
        case export
        case transient
    }

    static let visionRequestRevision = 1

    let sourceIdentifier: String
    let sourceRevision: String
    let rendition: Rendition
    let pixelWidth: Int
    let pixelHeight: Int
    let originXMillipixels: Int
    let originYMillipixels: Int
    let requestRevision: Int

    init(
        sourceIdentifier: String,
        sourceRevision: String,
        rendition: Rendition,
        extent: CGRect,
        requestRevision: Int = Self.visionRequestRevision
    ) {
        self.sourceIdentifier = sourceIdentifier
        self.sourceRevision = sourceRevision
        self.rendition = rendition
        pixelWidth = Int(extent.width.rounded())
        pixelHeight = Int(extent.height.rounded())
        originXMillipixels = Int((extent.minX * 1_000).rounded())
        originYMillipixels = Int((extent.minY * 1_000).rounded())
        self.requestRevision = requestRevision
    }

    init(sourceURL: URL, rendition: Rendition, extent: CGRect) {
        let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = values?.fileSize ?? -1
        let modificationNanoseconds = values?.contentModificationDate.map {
            Int64(($0.timeIntervalSince1970 * 1_000_000_000).rounded())
        } ?? -1
        self.init(
            sourceIdentifier: sourceURL.standardizedFileURL.path(percentEncoded: false),
            sourceRevision: "\(fileSize):\(modificationNanoseconds)",
            rendition: rendition,
            extent: extent
        )
    }

    /// Source-less API callers still share one request within their current
    /// render. A UUID prevents an unrelated CIImage with coincidentally equal
    /// geometry from reusing a mask without a trustworthy source signature.
    static func transient(for extent: CGRect) -> Self {
        Self(
            sourceIdentifier: UUID().uuidString,
            sourceRevision: "transient",
            rendition: .transient,
            extent: extent
        )
    }
}

struct SubjectMaskCacheDiagnostics: Equatable {
    let generatedRequests: Int
    let cacheHits: Int
    let cachedEntries: Int
}

/// Generates local Vision foreground masks and retains only a bounded,
/// disposable in-memory preview/export cache. Masks never enter Catalog SQLite
/// or a media directory. A cached `nil` is intentional: a failed/no-subject
/// request remains fail-closed without repeatedly applying a whole-image
/// fallback.
final class SubjectMaskProvider: @unchecked Sendable {
    typealias Generator = (CIImage) -> CIImage?

    private enum CachedMask {
        case image(CIImage)
        case noMask
    }

    private let capacity: Int
    private let generator: Generator
    private let lock = NSLock()
    private var cache: [SubjectMaskCacheKey: CachedMask] = [:]
    private var lru: [SubjectMaskCacheKey] = []
    private var generatedRequests = 0
    private var cacheHits = 0

    init(capacity: Int = 8, generator: @escaping Generator = VisionSubjectMaskRenderer.image) {
        self.capacity = max(1, capacity)
        self.generator = generator
    }

    func mask(for source: CIImage, key: SubjectMaskCacheKey) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] {
            cacheHits += 1
            touch(key)
            return image(from: cached)
        }

        // Serializing generation also prevents two overlapping preview tasks
        // from running duplicate Vision requests for the same cache key.
        let generated = generator(source)
        generatedRequests += 1
        let cached: CachedMask = generated.map(CachedMask.image) ?? .noMask
        cache[key] = cached
        touch(key)
        while lru.count > capacity {
            let evicted = lru.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        return generated
    }

    func diagnostics() -> SubjectMaskCacheDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return SubjectMaskCacheDiagnostics(
            generatedRequests: generatedRequests,
            cacheHits: cacheHits,
            cachedEntries: cache.count
        )
    }

    func clear() {
        lock.lock()
        cache.removeAll()
        lru.removeAll()
        generatedRequests = 0
        cacheHits = 0
        lock.unlock()
    }

    private func touch(_ key: SubjectMaskCacheKey) {
        lru.removeAll { $0 == key }
        lru.append(key)
    }

    private func image(from cached: CachedMask) -> CIImage? {
        if case let .image(image) = cached { return image }
        return nil
    }
}
