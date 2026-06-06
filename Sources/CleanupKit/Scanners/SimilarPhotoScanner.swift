import Foundation
import CoreGraphics
import ImageIO

/// Finds visually *similar* (not byte-identical) photos using a perceptual
/// difference-hash, so burst shots and re-saved/resized copies group together.
/// Personal photos are sensitive, so results are never auto-selected.
public struct SimilarPhotoScanner: Scanner {
    public let category: CleanupCategory = .similarPhotos

    let searchRoots: [URL]
    /// Max Hamming distance (out of 64 bits) to consider two photos similar.
    let threshold: Int
    let maxImages: Int

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp",
    ]

    public init(searchRoots: [URL]? = nil, threshold: Int = 8, maxImages: Int = 4000) {
        self.searchRoots = searchRoots ?? [
            FileSystem.home("Pictures"),
            FileSystem.home("Downloads"),
            FileSystem.home("Desktop"),
        ].filter(FileSystem.exists)
        self.threshold = threshold
        self.maxImages = maxImages
    }

    private struct Photo: Sendable {
        let url: URL
        let size: Int64
        let hash: UInt64
    }

    public func scan(report: @Sendable (CleanupItem) -> Void) async {
        let urls = collectImageURLs()

        // Hash concurrently — thumbnail decode is the expensive part.
        let photos: [Photo] = await withTaskGroup(of: Photo?.self) { group in
            for url in urls {
                group.addTask {
                    guard let hash = Self.dHash(of: url) else { return nil }
                    return Photo(url: url, size: FileSystem.size(of: url), hash: hash)
                }
            }
            var out: [Photo] = []
            for await p in group { if let p { out.append(p) } }
            return out
        }

        // Group by Hamming distance via union-find.
        let groups = clusters(of: photos)
        for group in groups where group.count > 1 {
            // Keep the largest file; the rest are removable candidates.
            let sorted = group.sorted { $0.size > $1.size }
            let key = "sim-\(sorted[0].hash)"
            for (idx, photo) in sorted.enumerated() {
                let keeper = idx == 0
                report(CleanupItem(
                    url: photo.url,
                    size: photo.size,
                    category: category,
                    safety: keeper ? .review : .caution,
                    label: photo.url.lastPathComponent,
                    detail: keeper
                        ? "Keep (largest) · \(group.count) similar"
                        : "Similar to \(sorted[0].url.lastPathComponent)",
                    lastModified: FileSystem.modificationDate(of: photo.url),
                    groupKey: key
                ))
            }
        }
    }

    private func collectImageURLs() -> [URL] {
        var urls: [URL] = []
        for root in searchRoots {
            guard let enumerator = FileSystem.manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                guard urls.count < maxImages else { return urls }
                if Self.imageExtensions.contains(url.pathExtension.lowercased()) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    /// Union-find clustering: any two photos within `threshold` bits join the
    /// same cluster.
    private func clusters(of photos: [Photo]) -> [[Photo]] {
        var parent = Array(0..<photos.count)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
            return r
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        for i in 0..<photos.count {
            for j in (i + 1)..<photos.count
            where Self.hamming(photos[i].hash, photos[j].hash) <= threshold {
                union(i, j)
            }
        }

        var buckets: [Int: [Photo]] = [:]
        for i in 0..<photos.count { buckets[find(i), default: []].append(photos[i]) }
        return Array(buckets.values)
    }

    static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    /// 64-bit difference hash: downscale to 9×8 grayscale, then for each row
    /// emit a bit per "is this pixel brighter than the one to its right".
    static func dHash(of url: URL) -> UInt64? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let w = 9, h = 8
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }

        let px = data.bindMemory(to: UInt8.self, capacity: w * h)
        var hash: UInt64 = 0
        var bit = 0
        for row in 0..<h {
            for col in 0..<(w - 1) {
                if px[row * w + col] > px[row * w + col + 1] { hash |= (UInt64(1) << UInt64(bit)) }
                bit += 1
            }
        }
        return hash
    }
}
