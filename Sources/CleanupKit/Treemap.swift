import Foundation
import CoreGraphics

/// Squarified treemap layout. Turns weighted items into rectangles that pack a
/// container while keeping each tile close to square — the standard disk-map
/// visualization (DaisyDisk-style).
public enum Treemap {

    public struct Tile<ID: Hashable & Sendable>: Sendable {
        public let id: ID
        public let rect: CGRect
    }

    /// Lay `items` (id + non-negative weight) into `rect`.
    public static func layout<ID>(
        _ items: [(id: ID, weight: Double)],
        in rect: CGRect
    ) -> [Tile<ID>] {
        let positive = items.filter { $0.weight > 0 }
        guard !positive.isEmpty, rect.width > 0, rect.height > 0 else { return [] }

        let sorted = positive.sorted { $0.weight > $1.weight }
        let totalWeight = sorted.reduce(0) { $0 + $1.weight }
        let scale = (rect.width * rect.height) / totalWeight
        var scaled = sorted.map { (id: $0.id, area: $0.weight * scale) }

        var tiles: [Tile<ID>] = []
        var free = rect
        var row: [(id: ID, area: Double)] = []

        func shorterSide() -> CGFloat { min(free.width, free.height) }

        while !scaled.isEmpty {
            let next = scaled[0]
            if row.isEmpty || worstRatio(row, side: shorterSide()) >= worstRatio(row + [next], side: shorterSide()) {
                row.append(next)
                scaled.removeFirst()
            } else {
                placeRow(row, in: &free, into: &tiles)
                row = []
            }
        }
        if !row.isEmpty { placeRow(row, in: &free, into: &tiles) }
        return tiles
    }

    /// Worst (largest) aspect ratio among a candidate row laid along `side`.
    private static func worstRatio<ID>(_ row: [(id: ID, area: Double)], side: CGFloat) -> Double {
        let s = side == 0 ? 1 : Double(side)
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0 else { return .greatestFiniteMagnitude }
        let maxA = row.map(\.area).max() ?? 0
        let minA = row.map(\.area).min() ?? 0
        return max((s * s * maxA) / (sum * sum), (sum * sum) / (s * s * minA))
    }

    /// Place a finished row along the shorter side, then shrink `free`.
    private static func placeRow<ID>(
        _ row: [(id: ID, area: Double)],
        in free: inout CGRect,
        into tiles: inout [Tile<ID>]
    ) {
        let sum = CGFloat(row.reduce(0) { $0 + $1.area })
        let horizontal = free.width >= free.height
        // Thickness of the row band, perpendicular to the layout axis.
        let band = horizontal ? sum / free.height : sum / free.width

        var offset: CGFloat = horizontal ? free.minY : free.minX
        for item in row {
            let length = CGFloat(item.area) / max(band, 0.0001)
            let tileRect = horizontal
                ? CGRect(x: free.minX, y: offset, width: band, height: length)
                : CGRect(x: offset, y: free.minY, width: length, height: band)
            tiles.append(Tile(id: item.id, rect: tileRect))
            offset += length
        }

        if horizontal {
            free = CGRect(x: free.minX + band, y: free.minY,
                          width: free.width - band, height: free.height)
        } else {
            free = CGRect(x: free.minX, y: free.minY + band,
                          width: free.width, height: free.height - band)
        }
    }
}
