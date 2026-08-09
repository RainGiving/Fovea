import AppKit
import Foundation
import FoveaCore

/// 缩略图请求的紧迫程度。
///
/// 胶卷条一次会排进几十张，队列按先进先出跑。当前这张排在中间就要等前面
/// 二十来张解完才轮到，而它正好是画面正中被放大的那一格，缺图最显眼。
/// 抬高它的队列优先级，让它插到队首。
enum ThumbnailPriority: Sendable {
    case normal
    case high

    var queuePriority: Operation.QueuePriority {
        switch self {
        case .normal: .normal
        case .high: .veryHigh
        }
    }
}

final class ThumbnailProvider {
    typealias Completion = @Sendable (Result<NSImage, Error>) -> Void
    typealias Loader = @Sendable (ImageItem, CGFloat, ThumbnailPriority, @escaping Completion) -> @Sendable () -> Void
    typealias Decoder = @Sendable (ImageItem, CGFloat) throws -> DecodedImage

    static let defaultMaxPixelSize: CGFloat = 320
    static let maximumConcurrentDecodeCount = 4

    private static let cache = ThumbnailCacheStorage()
    private static let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Fovea.thumbnail-decode"
        // 缩略图是用户正盯着的界面，跑在 utility 上会被系统压到后台节奏，
        // 机器一忙就迟迟出不来。
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = maximumConcurrentDecodeCount
        return queue
    }()

    private let maxPixelSize: CGFloat
    private let loader: Loader

    init(
        maxPixelSize: CGFloat = ThumbnailProvider.defaultMaxPixelSize,
        loader: Loader? = nil,
        currentFileVersionAtURL: @escaping @Sendable (URL) -> CurrentFileVersion? = CurrentFileVersion.read(at:),
        decoder: Decoder? = nil
    ) {
        self.maxPixelSize = maxPixelSize
        let resolvedDecoder = decoder ?? { item, maxPixelSize in
            try ImageDecodeService().decode(
                url: item.url,
                format: item.format,
                maxPixelSize: maxPixelSize
            )
        }
        self.loader = loader ?? { item, maxPixelSize, priority, completion in
            Self.loadDefaultThumbnail(
                item: item,
                maxPixelSize: maxPixelSize,
                priority: priority,
                currentFileVersionAtURL: currentFileVersionAtURL,
                decoder: resolvedDecoder,
                completion: completion
            )
        }
    }

    @discardableResult
    func loadThumbnail(
        for item: ImageItem,
        priority: ThumbnailPriority = .normal,
        completion: @escaping Completion
    ) -> ThumbnailRequest {
        let request = ThumbnailRequest()
        let cancelLoader = loader(item, maxPixelSize, priority) { result in
            guard request.completeIfActive() else { return }
            completion(result)
        }
        request.setCancelHandler(cancelLoader)
        return request
    }

    private static func loadDefaultThumbnail(
        item: ImageItem,
        maxPixelSize: CGFloat,
        priority: ThumbnailPriority,
        currentFileVersionAtURL: @escaping @Sendable (URL) -> CurrentFileVersion?,
        decoder: @escaping Decoder,
        completion: @escaping Completion
    ) -> @Sendable () -> Void {
        let version = currentFileVersionAtURL(item.url)
        let key = ThumbnailCacheKey(url: item.url, version: version, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) {
            DispatchQueue.main.async {
                completion(.success(cached))
            }
            return {}
        }

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard operation?.isCancelled == false else { return }

            // 投递结果时不能再看 operation 是否还活着。
            // 操作一执行完队列就可能把它释放掉，等 main 队列的块跑起来时
            // 弱引用已经是 nil，而 `nil == false` 为假，completion 会被
            // 直接丢弃，那一格缩略图就永远空白。取消与否交给
            // ThumbnailRequest.completeIfActive 判断，那一层本来就管这件事。
            func deliver(_ result: Result<NSImage, Error>) {
                DispatchQueue.main.async { completion(result) }
            }

            do {
                let decoded = try decoder(item, maxPixelSize)
                guard currentFileVersionAtURL(item.url) == version else {
                    guard operation?.isCancelled == false else { return }
                    deliver(.failure(ImageDecodeError.cannotDecodeImage))
                    return
                }
                let image = NSImage(cgImage: decoded.cgImage, size: decoded.pixelSize)
                // 解码这一步已经做完了，取消只拦投递，不该把成果一起扔掉。
                // 胶卷条重建时同一张图会立刻被再请求一次，缓存里有就是瞬时命中，
                // 否则每次重建都要从头再解一遍。
                cache.setObject(image, forKey: key, cost: decoded.decodedByteCost)
                guard operation?.isCancelled == false else { return }
                deliver(.success(image))
            } catch {
                deliver(.failure(error))
            }
        }
        operation.queuePriority = priority.queuePriority
        decodeQueue.addOperation(operation)

        let cancellation = OperationCancellation(operation: operation)
        return { cancellation.cancel() }
    }

    static func removeAllCachedThumbnailsForTesting() {
        cache.removeAllObjects()
    }
}

private final class ThumbnailCacheStorage: @unchecked Sendable {
    private let cache = NSCache<ThumbnailCacheKey, NSImage>()

    init() {
        cache.totalCostLimit = ImageCache.defaultThumbnailCostLimit
    }

    func object(forKey key: ThumbnailCacheKey) -> NSImage? {
        cache.object(forKey: key)
    }

    func setObject(_ image: NSImage, forKey key: ThumbnailCacheKey, cost: Int) {
        cache.setObject(image, forKey: key, cost: cost)
    }

    func removeAllObjects() {
        cache.removeAllObjects()
    }
}

private final class ThumbnailCacheKey: NSObject, @unchecked Sendable {
    private let url: URL
    private let version: CurrentFileVersion?
    private let maxPixelSize: Int

    init(url: URL, version: CurrentFileVersion?, maxPixelSize: CGFloat) {
        self.url = url.standardizedFileURL
        self.version = version
        self.maxPixelSize = Int(maxPixelSize.rounded(.up))
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(url)
        hasher.combine(version)
        hasher.combine(maxPixelSize)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ThumbnailCacheKey else { return false }
        return url == other.url && version == other.version && maxPixelSize == other.maxPixelSize
    }
}

final class ThumbnailRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?
    private var cancelled = false
    private var finished = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    fileprivate func setCancelHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        let shouldCancelImmediately = cancelled
        if finished {
            lock.unlock()
        } else if shouldCancelImmediately {
            lock.unlock()
            handler()
        } else {
            onCancel = handler
            lock.unlock()
        }
    }

    fileprivate func completeIfActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, !finished else { return false }
        finished = true
        onCancel = nil
        return true
    }

    func cancel() {
        lock.lock()
        guard !cancelled, !finished else {
            lock.unlock()
            return
        }

        cancelled = true
        let handler = onCancel
        onCancel = nil
        lock.unlock()
        handler?()
    }
}

private final class OperationCancellation: @unchecked Sendable {
    private let operation: Operation

    init(operation: Operation) {
        self.operation = operation
    }

    func cancel() {
        operation.cancel()
    }
}
