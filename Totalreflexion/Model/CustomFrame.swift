import AppKit
import CoreGraphics

/// A user-supplied device frame image (PNG with a transparent screen area).
/// The screen area is found automatically by flood-filling the transparent pixels from the center.
struct CustomFrame {
    let image: NSImage
    let pixelSize: CGSize
    /// Screen area in unit coordinates (0...1, origin top-left).
    let screenRect: CGRect

    var isPortrait: Bool { pixelSize.height > pixelSize.width }

    private static var cache: [String: CustomFrame] = [:]

    @MainActor
    static func load(path: String) -> CustomFrame? {
        if let cached = cache[path] {
            return cached
        }
        guard let image = NSImage(contentsOfFile: path),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rect = detectScreen(in: cgImage) else { return nil }
        let frame = CustomFrame(image: image, pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
                                screenRect: rect)
        cache[path] = frame
        return frame
    }

    private static func detectScreen(in image: CGImage) -> CGRect? {
        // Work on a downscaled copy; precision of ~0.2% is plenty.
        let scale = min(1, 600 / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        var alpha = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &alpha, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let start = (height / 2) * width + width / 2
        guard alpha[start] < 32 else { return nil }
        var visited = [Bool](repeating: false, count: width * height)
        var stack = [start]
        visited[start] = true
        var minX = width, maxX = 0, minY = height, maxY = 0
        while let index = stack.popLast() {
            let x = index % width
            let y = index / width
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let next = ny * width + nx
                if !visited[next], alpha[next] < 32 {
                    visited[next] = true
                    stack.append(next)
                }
            }
        }
        // Bitmap rows run top to bottom in memory, matching the top-left origin we want.
        return CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
                      width: CGFloat(maxX - minX + 1) / CGFloat(width),
                      height: CGFloat(maxY - minY + 1) / CGFloat(height))
    }
}
