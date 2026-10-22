// Erzeugt das AppIcon im macOS-Raster (824 pt Kachel auf 1024 pt Fläche, transparente Ecken).
// Aufruf: swift scripts/make-icon.swift <quelle.png|jpg> <AppIcon.appiconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let cgSource = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("usage: make-icon.swift <image> <appiconset>")
}
let output = URL(fileURLWithPath: args[2])

func render(size: Int) -> Data {
    let scale = CGFloat(size) / 1024
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let tile = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    // Soft drop shadow like system icons.
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
    let path = CGPath(roundedRect: tile, cornerWidth: 185 * scale, cornerHeight: 185 * scale, transform: nil)
    context.addPath(path)
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0)
    context.addPath(path)
    context.clip()
    // Source has its own rounded square with black corners; inset slightly so only blue remains.
    let inset = tile.width * 0.012
    context.draw(cgSource, in: tile.insetBy(dx: -inset, dy: -inset))
    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scaleFactor in [1, 2] {
        let pixels = points * scaleFactor
        let name = "icon_\(points)x\(points)\(scaleFactor == 2 ? "@2x" : "").png"
        try! render(size: pixels).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scaleFactor)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("AppIcon geschrieben nach \(output.path)")
