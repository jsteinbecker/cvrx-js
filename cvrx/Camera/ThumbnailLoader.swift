//
//  ThumbnailLoader.swift
//  cvrx
//

import Foundation
import ImageIO
import SwiftUI

actor ThumbnailLoader {

    // MARK: - Stored state

    private let cache = NSCache<NSString, CGImage>()
    private var inFlight: [NSString: Task<CGImage?, Never>] = [:]

    init(memoryLimit: Int = 100 * 1024 * 1024) {  // ~100 MB
        cache.totalCostLimit = memoryLimit
    }

    /// Returns a thumbnail for `url`, decoding it off the main actor.
    /// Repeated requests for the same image share a single decode.
    func thumbnail(for url: URL, maxPixel: CGFloat) async -> CGImage? {
        let key = cacheKey(url: url, maxPixel: maxPixel)

        if let cached = cache.object(forKey: key) { return cached }
        if let pending = inFlight[key] { return await pending.value }

        let task = decodeTask(url: url, maxPixel: maxPixel)
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let image = await task.value
        if let image { store(image, for: key) }
        return image
    }

    private func cacheKey(url: URL, maxPixel: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(maxPixel))" as NSString
    }

    private func store(_ image: CGImage, for key: NSString) {
        let cost = image.bytesPerRow * image.height
        cache.setObject(image, forKey: key, cost: cost)
    }

    /// Off-actor work: read the file and render a downsampled thumbnail.
    private func decodeTask(url: URL, maxPixel: CGFloat) -> Task<CGImage?, Never> {
        Task.detached(priority: .userInitiated) {
            ThumbnailLoader.renderThumbnail(url: url, maxPixel: maxPixel)
        }
    }

    /// Pure, stateless decode — no shared state, easy to reason about and test.
    private static func renderThumbnail(url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel * 2,  // for @2x displays
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
