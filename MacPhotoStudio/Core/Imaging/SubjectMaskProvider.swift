import CoreGraphics
import CoreImage
import Foundation

/// A stable cache identity for a foreground-subject request. It deliberately
/// excludes photo-editing controls: subject selection is derived from the
/// pre-local-adjustment source, not from exposure, colour or mask order.
struct SubjectMaskCacheKey: Hashable, Sendable {
    enum Rendition: String, Hashable, Sendable {
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
        let values = try? sourceURL.resourceValues(forKeys: [
            .fileResourceIdentifierKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let fileResourceIdentifier = values?.fileResourceIdentifier.map { String(describing: $0) } ?? "unavailable"
        let fileSize = values?.fileSize ?? -1
        let modificationNanoseconds = values?.contentModificationDate.map {
            Int64(($0.timeIntervalSince1970 * 1_000_000_000).rounded())
        } ?? -1
        self.init(
            sourceIdentifier: sourceURL.standardizedFileURL.path(percentEncoded: false),
            sourceRevision: "\(fileResourceIdentifier):\(fileSize):\(modificationNanoseconds)",
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

    /// A single synchronous Vision request shared by every concurrent caller
    /// for one cache key. Waiting occurs on this per-key condition, never on
    /// the provider's global cache lock.
    private final class InFlightMask {
        private let condition = NSCondition()
        private var result: CachedMask?

        func waitForResult() -> CachedMask {
            condition.lock()
            defer { condition.unlock() }
            while result == nil {
                condition.wait()
            }
            return result!
        }

        func complete(with result: CachedMask) {
            condition.lock()
            self.result = result
            condition.broadcast()
            condition.unlock()
        }
    }

    private let capacity: Int
    private let generator: Generator
    private let lock = NSLock()
    private var cache: [SubjectMaskCacheKey: CachedMask] = [:]
    private var inFlight: [SubjectMaskCacheKey: InFlightMask] = [:]
    private var lru: [SubjectMaskCacheKey] = []
    private var generatedRequests = 0
    private var cacheHits = 0

    init(capacity: Int = 8, generator: @escaping Generator = VisionSubjectMaskRenderer.image) {
        self.capacity = max(1, capacity)
        self.generator = generator
    }

    func mask(for source: CIImage, key: SubjectMaskCacheKey) -> CIImage? {
        lock.lock()
        if let cached = cache[key] {
            cacheHits += 1
            touch(key)
            lock.unlock()
            return image(from: cached)
        }

        if let existingRequest = inFlight[key] {
            // The result will be cached before the request wakes us. Count the
            // shared in-flight result as a cache hit for diagnostics.
            cacheHits += 1
            lock.unlock()
            return image(from: existingRequest.waitForResult())
        }

        let request = InFlightMask()
        inFlight[key] = request
        lock.unlock()

        // Vision may take materially longer than a cache lookup. It must run
        // outside the global lock so unrelated images can generate in parallel.
        let generated = generator(source)
        let cached: CachedMask = generated.map(CachedMask.image) ?? .noMask

        lock.lock()
        generatedRequests += 1
        cache[key] = cached
        touch(key)
        while lru.count > capacity {
            let evicted = lru.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        inFlight.removeValue(forKey: key)
        lock.unlock()

        request.complete(with: cached)
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
