import Foundation
import CoreGraphics

/// One physical key, in ZMK `key_physical_attrs` units (100 = 1u, rotation in centi-degrees).
public struct PhysicalKey: Sendable, Hashable {
    public let index: Int
    public let w: Double
    public let h: Double
    public let x: Double
    public let y: Double
    public let rotation: Double
    public let rx: Double
    public let ry: Double

    /// Center of the key after applying its rotation around (rx, ry), in units.
    public var center: CGPoint {
        let cx = x + w / 2, cy = y + h / 2
        guard rotation != 0 else { return CGPoint(x: cx, y: cy) }
        let a = rotation / 100 * .pi / 180
        let dx = cx - rx, dy = cy - ry
        return CGPoint(x: rx + dx * cos(a) - dy * sin(a), y: ry + dx * sin(a) + dy * cos(a))
    }

    public var degrees: Double { rotation / 100 }
    public var isLeft: Bool { center.x < 900 }
    public var isThumb: Bool { rotation != 0 }
}

public enum Adv360Layout {
    public static let keyCount = 76

    /// Number of bindings per visual row in the keymap file, used for pretty-printing.
    public static let rowLengths = [14, 14, 18, 14, 16]

    /// Row/column-index positions used when formatting bindings into an aligned grid.
    /// Each row is split into left block, thumb/center block and right block.
    public static let rowBlocks: [(left: Int, mid: Int, right: Int)] = [
        (7, 0, 7), (7, 0, 7), (7, 4, 7), (6, 2, 6), (5, 6, 5),
    ]

    public static let keys: [PhysicalKey] = {
        let raw: [[Double]] = [
            [125, 100, 0, 25, 0, 0, 0], [100, 100, 125, 25, 0, 0, 0], [100, 100, 225, 0, 0, 0, 0],
            [100, 100, 325, 0, 0, 0, 0], [100, 100, 425, 0, 0, 0, 0], [100, 100, 525, 0, 0, 0, 0],
            [100, 100, 625, 0, 0, 0, 0], [100, 100, 1075, 0, 0, 0, 0], [100, 100, 1175, 0, 0, 0, 0],
            [100, 100, 1275, 0, 0, 0, 0], [100, 100, 1375, 0, 0, 0, 0], [100, 100, 1475, 0, 0, 0, 0],
            [100, 100, 1575, 25, 0, 0, 0], [125, 100, 1675, 25, 0, 0, 0],
            [125, 100, 0, 125, 0, 0, 0], [100, 100, 125, 125, 0, 0, 0], [100, 100, 225, 100, 0, 0, 0],
            [100, 100, 325, 100, 0, 0, 0], [100, 100, 425, 100, 0, 0, 0], [100, 100, 525, 100, 0, 0, 0],
            [100, 100, 625, 100, 0, 0, 0], [100, 100, 1075, 100, 0, 0, 0], [100, 100, 1175, 100, 0, 0, 0],
            [100, 100, 1275, 100, 0, 0, 0], [100, 100, 1375, 100, 0, 0, 0], [100, 100, 1475, 100, 0, 0, 0],
            [100, 100, 1575, 125, 0, 0, 0], [125, 100, 1675, 125, 0, 0, 0],
            [125, 100, 0, 225, 0, 0, 0], [100, 100, 125, 225, 0, 0, 0], [100, 100, 225, 200, 0, 0, 0],
            [100, 100, 325, 200, 0, 0, 0], [100, 100, 425, 200, 0, 0, 0], [100, 100, 525, 200, 0, 0, 0],
            [100, 100, 625, 200, 0, 0, 0],
            [100, 100, 675, 400, 1500, 525, 400], [100, 100, 775, 400, 1500, 525, 400],
            [100, 100, 925, 400, -1500, 1275, 400], [100, 100, 1025, 400, -1500, 1275, 400],
            [100, 100, 1075, 200, 0, 0, 0], [100, 100, 1175, 200, 0, 0, 0], [100, 100, 1275, 200, 0, 0, 0],
            [100, 100, 1375, 200, 0, 0, 0], [100, 100, 1475, 200, 0, 0, 0], [100, 100, 1575, 225, 0, 0, 0],
            [125, 100, 1675, 225, 0, 0, 0],
            [125, 100, 0, 325, 0, 0, 0], [100, 100, 125, 325, 0, 0, 0], [100, 100, 225, 300, 0, 0, 0],
            [100, 100, 325, 300, 0, 0, 0], [100, 100, 425, 300, 0, 0, 0], [100, 100, 525, 300, 0, 0, 0],
            [100, 100, 775, 500, 1500, 525, 400], [100, 100, 925, 500, -1500, 1275, 400],
            [100, 100, 1175, 300, 0, 0, 0], [100, 100, 1275, 300, 0, 0, 0], [100, 100, 1375, 300, 0, 0, 0],
            [100, 100, 1475, 300, 0, 0, 0], [100, 100, 1575, 325, 0, 0, 0], [125, 100, 1675, 325, 0, 0, 0],
            [125, 100, 0, 425, 0, 0, 0], [100, 100, 125, 425, 0, 0, 0], [100, 100, 225, 400, 0, 0, 0],
            [100, 100, 325, 400, 0, 0, 0], [100, 100, 425, 400, 0, 0, 0],
            [100, 200, 575, 500, 1500, 525, 400], [100, 200, 675, 500, 1500, 525, 400],
            [100, 100, 775, 600, 1500, 525, 400], [100, 100, 925, 600, -1500, 1275, 400],
            [100, 200, 1025, 500, -1500, 1275, 400], [100, 200, 1125, 500, -1500, 1275, 400],
            [100, 100, 1275, 400, 0, 0, 0], [100, 100, 1375, 400, 0, 0, 0], [100, 100, 1475, 400, 0, 0, 0],
            [100, 100, 1575, 425, 0, 0, 0], [125, 100, 1675, 425, 0, 0, 0],
        ]
        return raw.enumerated().map { i, k in
            PhysicalKey(index: i, w: k[0], h: k[1], x: k[2], y: k[3], rotation: k[4], rx: k[5], ry: k[6])
        }
    }()

    /// Bounding box of all keys (rotated) in units.
    public static let bounds: CGRect = {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for k in keys {
            let a: Double = k.degrees * .pi / 180
            let c = k.center
            let corners: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            for (sx, sy) in corners {
                let dx: Double = sx * k.w / 2
                let dy: Double = sy * k.h / 2
                let px: Double = c.x + dx * cos(a) - dy * sin(a)
                let py: Double = c.y + dx * sin(a) + dy * cos(a)
                minX = min(minX, px); maxX = max(maxX, px)
                minY = min(minY, py); maxY = max(maxY, py)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }()

    /// Spatial neighbour for arrow-key navigation.
    public static func neighbor(of index: Int, dx: Double, dy: Double) -> Int? {
        let from = keys[index].center
        var best: (Int, Double)?
        for k in keys where k.index != index {
            let c = k.center
            let vx = c.x - from.x, vy = c.y - from.y
            let along = vx * dx + vy * dy
            guard along > 20 else { continue }
            let across = abs(vx * dy - vy * dx)
            let score = along + across * 2.5
            if best == nil || score < best!.1 { best = (k.index, score) }
        }
        return best?.0
    }
}
