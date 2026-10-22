import CoreGraphics

/// Finds the row/column arrangement that shows all devices as large as possible.
enum GridLayout {
    struct Placement {
        var frames: [CGRect]
    }

    /// - Parameter aspects: width/height of each item including its frame.
    static func layout(aspects: [CGFloat], in bounds: CGSize, spacing: CGFloat) -> Placement {
        guard !aspects.isEmpty, bounds.width > 0, bounds.height > 0 else { return Placement(frames: []) }
        var best: (score: CGFloat, frames: [CGRect]) = (-1, [])
        for rows in 1...aspects.count {
            let frames = layout(aspects: aspects, rows: rows, bounds: bounds, spacing: spacing)
            // Maximize the smallest item, then the total covered area.
            let areas = frames.map { $0.width * $0.height }
            let score = (areas.min() ?? 0) * 4 + areas.reduce(0, +)
            if score > best.score {
                best = (score, frames)
            }
        }
        return Placement(frames: best.frames)
    }

    private static func layout(aspects: [CGFloat], rows: Int, bounds: CGSize, spacing: CGFloat) -> [CGRect] {
        let perRow = Int((Double(aspects.count) / Double(rows)).rounded(.up))
        let rowItems = stride(from: 0, to: aspects.count, by: perRow).map {
            Array(aspects[$0..<min($0 + perRow, aspects.count)])
        }
        let rowCount = CGFloat(rowItems.count)
        let availableHeight = bounds.height - spacing * (rowCount - 1)
        // Height of each row if it filled the width exactly.
        let naturalHeights = rowItems.map { items in
            (bounds.width - spacing * CGFloat(items.count - 1)) / items.reduce(0, +)
        }
        let totalNatural = naturalHeights.reduce(0, +)
        let shrink = min(1, availableHeight / totalNatural)
        let heights = naturalHeights.map { $0 * shrink }
        let usedHeight = heights.reduce(0, +) + spacing * (rowCount - 1)

        var frames: [CGRect] = []
        var y = (bounds.height - usedHeight) / 2
        for (rowIndex, items) in rowItems.enumerated() {
            let height = heights[rowIndex]
            let rowWidth = items.reduce(0) { $0 + $1 * height } + spacing * CGFloat(items.count - 1)
            var x = (bounds.width - rowWidth) / 2
            for aspect in items {
                let width = aspect * height
                frames.append(CGRect(x: x, y: y, width: width, height: height))
                x += width + spacing
            }
            y += height + spacing
        }
        return frames
    }
}
