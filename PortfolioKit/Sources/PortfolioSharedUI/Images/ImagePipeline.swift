import CoreGraphics
import Foundation
import ImageIO
import Synchronization

/// Loads images from URLs and keeps them, so each is downloaded and decoded once. Decoded images stay
/// in memory while there's room. Downloaded data stays on disk in a `URLCache`, which follows the
/// server's cache headers, so images survive relaunches. Decoding happens off the main thread.
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
    /// Downloads under way, so views showing the same image wait for one download.
    private let loading = Mutex<[URL: Task<CGImage, any Error>]>([:])

    /// - Parameters:
    ///   - configuration: how images are downloaded. The default keeps them on disk.
    ///   - memoryLimit: about how many bytes of decoded images to keep in memory.
    public init(configuration: URLSessionConfiguration = ImagePipeline.defaultConfiguration(), memoryLimit: Int = ImagePipeline.memoryLimit) {
        session = URLSession(configuration: configuration)
        decoded = DecodedImageCache(costLimit: memoryLimit)
    }

    /// Downloads into a disk cache of its own, apart from other requests.
    public static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        let directory = URL.cachesDirectory.appending(path: "Images", directoryHint: .isDirectory)
        configuration.urlCache = URLCache(memoryCapacity: urlCacheMemory, diskCapacity: diskLimit, directory: directory)
        return configuration
    }

    /// The image at `url`, if it's decoded and in memory.
    public func cachedImage(for url: URL) -> CGImage? {
        decoded.image(for: url)
    }

    /// The image at `url`: from memory, or else downloaded (or read from disk) and decoded. A download
    /// finishes even if the caller stops waiting, so the image is ready the next time it's wanted.
    ///
    /// - Throws: `LoadingError`, or the `URLError` that stopped the download.
    public func image(for url: URL) async throws -> CGImage {
        // Memory and the downloads under way are checked together, and a download moves its image into
        // memory and stops being under way together, so two callers asking at once never both download.
        let lookup: Lookup = loading.withLock { downloads in
            if let download = downloads[url] { return .downloading(download) }
            if let image = decoded.image(for: url) { return .inMemory(image) }
            let download = Task.detached(priority: .userInitiated) { [self] in
                do {
                    let image = try await self.download(url)
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
        case .inMemory(let image): return image
        case .downloading(let download): return try await download.value
        }
    }

    private enum Lookup {
        case inMemory(CGImage)
        case downloading(Task<CGImage, any Error>)
    }

    private func download(_ url: URL) async throws -> CGImage {
        let (data, response) = try await session.data(from: url)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw LoadingError.status(response.statusCode)
        }
        return try Self.decode(data)
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
}
