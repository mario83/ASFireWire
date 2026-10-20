import AppKit
import SwiftUI

/// Loads the original Orpheus.app bitmaps from a local, gitignored copy.
/// The files stay out of git until Prism Sound grants a redistribution license.
enum OrpheusVendorArt {
    private static let cache = NSCache<NSString, NSImage>()

    static var isAvailable: Bool { chromeBackground() != nil || image(named: "background") != nil }

    static func image(named name: String) -> NSImage? {
        image(named: name, extensions: ["png", "bmp", "gif", "icns"])
    }

    /// The GIF is the true 703×678 window. The PNG is 714×687 with a green
    /// chroma fringe that showed in the upper corners when scaled into the layout.
    static func chromeBackground() -> NSImage? {
        if let gif = image(named: "background", extensions: ["gif"]) { return gif }
        guard let image = image(named: "background", extensions: ["png", "bmp"]) else { return nil }
        let target = OrpheusClassicLayout.window
        guard image.size.width > target.width + 1 || image.size.height > target.height + 1 else { return image }
        let rect = NSRect(x: (image.size.width - target.width) / 2,
                          y: (image.size.height - target.height) / 2,
                          width: target.width,
                          height: target.height)
        return crop(image, to: rect)
    }

    private static func image(named name: String, extensions: [String]) -> NSImage? {
        let key = "\(name)|\(extensions.joined(separator: ","))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        for url in candidateURLs(named: name, extensions: extensions) {
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = false
                cache.setObject(image, forKey: key)
                return image
            }
        }
        return nil
    }

    static func frame(named name: String, index: Int, count: Int) -> NSImage? {
        guard let image = image(named: name), count > 0 else { return nil }
        let clamped = min(max(index, 0), count - 1)
        let frameSize = NSSize(width: image.size.width / CGFloat(count), height: image.size.height)
        return crop(image, to: NSRect(x: frameSize.width * CGFloat(clamped),
                                      y: 0,
                                      width: frameSize.width,
                                      height: frameSize.height))
    }

    static func knobFrame(index: Int) -> NSImage? {
        let sheets = [("bigKnob1", 6), ("bigKnob2", 8), ("vol3", 8), ("vol4", 7)]
        var remaining = min(max(index, 0), 28)
        for (name, count) in sheets {
            if remaining < count { return frame(named: name, index: remaining, count: count) }
            remaining -= count
        }
        return frame(named: "vol4", index: 6, count: 7)
    }

    static func panFrame(value: Double, range: ClosedRange<Double>) -> NSImage? {
        let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return frame(named: "pan", index: Int(floor(41 * min(max(t, 0), 1))), count: 41)
    }

    private static func crop(_ image: NSImage, to rect: NSRect) -> NSImage? {
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let crop = CGRect(x: rect.minX * scaleX,
                          y: (image.size.height - rect.maxY) * scaleY,
                          width: rect.width * scaleX,
                          height: rect.height * scaleY).integral
        guard let sliced = cgImage.cropping(to: crop) else { return nil }
        return NSImage(cgImage: sliced, size: rect.size)
    }

    private static func candidateURLs(named name: String, extensions: [String]) -> [URL] {
        var roots: [URL] = []
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ASFW/OrpheusVendor")
        if let support { roots.append(support) }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("OrpheusVendor") {
            roots.append(bundled)
        }
        let thisFile = URL(fileURLWithPath: #filePath)
        roots.append(thisFile.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/OrpheusVendor"))
        roots.append(URL(fileURLWithPath: "/Applications/Prism Sound/Orpheus.app/Contents/Resources"))
        return roots.flatMap { root in extensions.map { root.appendingPathComponent("\(name).\($0)") } }
    }
}

struct OrpheusSprite: View {
    let name: String
    var frameIndex = 0
    var frameCount = 1

    var body: some View {
        OrpheusRaster(image: displayed)
    }

    private var displayed: NSImage? {
        frameCount > 1
            ? OrpheusVendorArt.frame(named: name, index: frameIndex, count: frameCount)
            : OrpheusVendorArt.image(named: name)
    }
}

struct OrpheusRaster: View {
    let image: NSImage?

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
