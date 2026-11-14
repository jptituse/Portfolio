import CoreGraphics
import Foundation
import ImageIO
import Synchronization

/// Loads images from URLs and keeps them, so each is downloaded and decoded once. Decoded images stay
/// in memory while there's room, and the ones views are showing stay however full it gets (`lease`).
/// Downloaded data stays on disk in a `URLCache`, which follows the server's cache headers, so images
/// survive relaunches. Decoding happens off the main thread.
///
/// The app shares one, `shared`, the way `AsyncImage` shares `URLSession.shared`.
public final class ImagePipeline: Sendable {
    /// Why an image couldn't be loaded.
    public enum LoadingError: Error, Hashable, Sendable {
        /// The server answered with this status instead of the image.
        case status(Int)
        /// The data isn't an image.
        case undecodable
    }

    public static let shared = ImagePipeline()

    private let session: URLSession
    private let decoded: DecodedImageCache
    private let scheduler: DownloadScheduler
    /// Downloads under way, so views showing the same image wait for one download.
    private let loading = Mutex<[URL: Task<CGImage, any Error>]>([:])
    /// The images views are showing, with how many show each. The views keep them in memory anyway, so
    /// they stay findable: a card growing out of a poster shows the poster's image from its first
    /// frame, even once the memory cache has let it go to make room for screen-sized artwork.
    private let showing = Mutex<[URL: ShownImage]>([:])

    private struct ShownImage {
        let image: CGImage
        var viewers: Int
    }

    /// - Parameters:
    ///   - configuration: how images are downloaded. The default keeps them on disk.
    ///   - memoryLimit: about how many bytes of decoded images to keep in memory.
    ///   - concurrentDownloads: how many downloads run at once; the rest wait their turn, the most
    ///     wanted first.
    public init(
        configuration: URLSessionConfiguration = ImagePipeline.defaultConfiguration(),
        memoryLimit: Int = ImagePipeline.memoryLimit,
        concurrentDownloads: Int = ImagePipeline.concurrentDownloads
    ) {
        session = URLSession(configuration: configuration)
        decoded = DecodedImageCache(costLimit: memoryLimit)
        scheduler = DownloadScheduler(limit: concurrentDownloads)
    }

    /// Downloads into a disk cache of its own, apart from other requests.
    public static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        let directory = URL.cachesDirectory.appending(path: "Images", directoryHint: .isDirectory)
        configuration.urlCache = URLCache(memoryCapacity: urlCacheMemory, diskCapacity: diskLimit, directory: directory)
        configuration.httpMaximumConnectionsPerHost = concurrentDownloads
        return configuration
    }

    /// The image at `url`, if it's decoded and in memory.
    public func cachedImage(for url: URL) -> CGImage? {
        decoded.image(for: url) ?? showing.withLock { $0[url]?.image }
    }

    /// Keeps `image`, from `url`, in memory for as long as the lease returned is held: a view holds one
    /// for each image it shows.
    public func lease(_ image: CGImage, for url: URL) -> ImageLease {
        showing.withLock { shown in
            shown[url, default: ShownImage(image: image, viewers: 0)].viewers += 1
        }
        return ImageLease(url: url, pipeline: self)
    }

    fileprivate func endLease(for url: URL) {
        let unseen: CGImage? = showing.withLock { shown in
            guard var entry = shown[url] else { return nil }
            entry.viewers -= 1
            guard entry.viewers == 0 else {
                shown[url] = entry
                return nil
            }
            shown[url] = nil
            return entry.image
        }
        // No view shows it now, so it stays only while there's room, like any other.
        if let unseen, decoded.image(for: url) == nil {
            decoded.insert(unseen, for: url)
        }
    }

    /// Lets go of every image in memory that no view is showing, as the memory cache does on its own
    /// once it's full or memory is short.
    func removeUnseenImagesFromMemory() {
        decoded.removeAll()
    }

    /// The image at `url`: from memory, or else downloaded (or read from disk) and decoded. A download
    /// finishes even if the caller stops waiting, so the image is ready the next time it's wanted.
    ///
    /// - Parameter priority: how soon it's wanted. While others wait their turn, the most wanted starts
    ///   first; asking again for one waiting, wanting it more, moves it up.
    /// - Throws: `LoadingError`, or the `URLError` that stopped the download.
    public func image(for url: URL, priority: ImagePriority = .normal) async throws -> CGImage {
        // Memory and the downloads under way are checked together, and a download moves its image into
        // memory and stops being under way together, so two callers asking at once never both download.
        let lookup: Lookup = loading.withLock { downloads in
            if let download = downloads[url] { return .waiting(download) }
            if let image = cachedImage(for: url) { return .inMemory(image) }
            let download = Task.detached(priority: .userInitiated) { [self] in
                do {
                    let image = try await self.download(url, priority: priority)
                    loading.withLock { downloads in
                        decoded.insert(image, for: url)
                        downloads[url] = nil
                    }
                    return image
                } catch {
                    loading.withLock { $0[url] = nil }
                    throw error
                }
            }
            downloads[url] = download
            return .downloading(download)
        }
        switch lookup {
        case .inMemory(let image):
            return image
        case .downloading(let download):
            return try await download.value
        case .waiting(let download):
            await scheduler.raise(url.absoluteString, to: priority)
            return try await download.value
        }
    }

    private enum Lookup {
        case inMemory(CGImage)
        /// A download it has just started.
        case downloading(Task<CGImage, any Error>)
        /// One asked for before, which may still be waiting its turn.
        case waiting(Task<CGImage, any Error>)
    }

    private func download(_ url: URL, priority: ImagePriority) async throws -> CGImage {
        await scheduler.acquire(url.absoluteString, priority: priority)
        do {
            let (data, response) = try await session.data(from: url)
            await scheduler.release()
            if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                throw LoadingError.status(response.statusCode)
            }
            return try Self.decode(data)
        } catch let error as LoadingError {
            throw error
        } catch {
            await scheduler.release()
            throw error
        }
    }

    /// Decodes now, rather than when the image is first drawn on the main thread.
    static func decode(_ data: Data) throws -> CGImage {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw LoadingError.undecodable
        }
        return image
    }

    /// Decoded images take far more memory than their files: a 4K backdrop is about 33 MB.
    public static let memoryLimit = 256 * 1024 * 1024
    /// Downloads at once: enough to keep a server busy, few enough that what's wanted most doesn't wait.
    public static let concurrentDownloads = 8
    static let urlCacheMemory = 16 * 1024 * 1024
    static let diskLimit = 512 * 1024 * 1024
}

/// Decoded images by URL. Past the cost limit, `NSCache` evicts some on its own, and more when memory is
/// short. It's thread-safe, but isn't marked `Sendable`.
private final class DecodedImageCache: @unchecked Sendable {
    private let cache = NSCache<NSURL, CGImage>()

    init(costLimit: Int) {
        cache.totalCostLimit = costLimit
    }

    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: CGImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Keeps an image a view shows in memory until the view lets go of it (`ImagePipeline.lease`).
public final class ImageLease: Sendable {
    private let url: URL
    private let pipeline: ImagePipeline

    fileprivate init(url: URL, pipeline: ImagePipeline) {
        self.url = url
        self.pipeline = pipeline
    }

    deinit {
        pipeline.endLease(for: url)
    }
}
