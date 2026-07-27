import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("usage: swift generate_app_icon.swift <mark.svg> <output.icns>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let mark = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to read icon mark at \(sourceURL.path)\n", stderr)
    exit(1)
}

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    let background = NSGradient(
        starting: NSColor(
            calibratedRed: 0.996,
            green: 0.980,
            blue: 0.957,
            alpha: 1
        ),
        ending: NSColor(
            calibratedRed: 0.976,
            green: 0.941,
            blue: 0.898,
            alpha: 1
        )
    )
    background?.draw(in: canvas, angle: -90)

    let inset = CGFloat(pixels) * 0.025
    mark.draw(
        in: canvas.insetBy(dx: inset, dy: inset),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

func bigEndianData(_ value: Int) -> Data {
    var encoded = UInt32(value).bigEndian
    return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}

let chunks: [(type: String, pixels: Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
    ("ic11", 32),
    ("ic12", 64),
    ("ic13", 256),
    ("ic14", 512),
]

var payload = Data()
var rendered: [Int: Data] = [:]

for chunk in chunks {
    let png: Data
    if let cached = rendered[chunk.pixels] {
        png = cached
    } else {
        png = try renderIcon(pixels: chunk.pixels)
        rendered[chunk.pixels] = png
    }

    payload.append(chunk.type.data(using: .ascii)!)
    payload.append(bigEndianData(png.count + 8))
    payload.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianData(payload.count + 8))
icns.append(payload)
try icns.write(to: outputURL, options: .atomic)
