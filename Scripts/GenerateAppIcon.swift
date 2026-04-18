import AppKit

let assetsURL = URL(fileURLWithPath: "Assets")
let outputURL = assetsURL.appendingPathComponent("RideCoach-AppIcon-1024.png")
let iconsetURL = assetsURL.appendingPathComponent("RideCoach-AppIcon.iconset")
let icnsURL = assetsURL.appendingPathComponent("RideCoach-AppIcon.icns")
let side = 1024

guard let representation = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create bitmap.")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

let rect = NSRect(x: 0, y: 0, width: side, height: side)
let background = NSGradient(colors: [
    color(252, 76, 2),
    color(226, 43, 28)
])!
let backgroundPath = NSBezierPath(roundedRect: rect.insetBy(dx: 44, dy: 44), xRadius: 210, yRadius: 210)
background.draw(in: backgroundPath, angle: 90)

NSColor.black.withAlphaComponent(0.18).setFill()
NSBezierPath(ovalIn: NSRect(x: 146, y: 130, width: 732, height: 150)).fill()

func stroke(_ path: NSBezierPath, width: CGFloat, color: NSColor = .white) {
    color.setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func fill(_ path: NSBezierPath, color: NSColor) {
    color.setFill()
    path.fill()
}

let leftWheel = NSBezierPath(ovalIn: NSRect(x: 180, y: 245, width: 250, height: 250))
let rightWheel = NSBezierPath(ovalIn: NSRect(x: 594, y: 245, width: 250, height: 250))
stroke(leftWheel, width: 56)
stroke(rightWheel, width: 56)

let frame = NSBezierPath()
frame.move(to: NSPoint(x: 305, y: 370))
frame.line(to: NSPoint(x: 456, y: 610))
frame.line(to: NSPoint(x: 560, y: 370))
frame.line(to: NSPoint(x: 718, y: 370))
frame.line(to: NSPoint(x: 596, y: 560))
frame.line(to: NSPoint(x: 704, y: 560))
stroke(frame, width: 58)

let bar = NSBezierPath()
bar.move(to: NSPoint(x: 448, y: 610))
bar.line(to: NSPoint(x: 360, y: 610))
stroke(bar, width: 56)

let mountain = NSBezierPath()
mountain.move(to: NSPoint(x: 426, y: 704))
mountain.line(to: NSPoint(x: 512, y: 828))
mountain.line(to: NSPoint(x: 598, y: 704))
stroke(mountain, width: 54)

let spark = NSBezierPath()
spark.move(to: NSPoint(x: 728, y: 780))
spark.line(to: NSPoint(x: 760, y: 852))
spark.line(to: NSPoint(x: 792, y: 780))
spark.line(to: NSPoint(x: 864, y: 748))
spark.line(to: NSPoint(x: 792, y: 716))
spark.line(to: NSPoint(x: 760, y: 644))
spark.line(to: NSPoint(x: 728, y: 716))
spark.line(to: NSPoint(x: 656, y: 748))
spark.close()
fill(spark, color: color(255, 246, 198))

NSGraphicsContext.restoreGraphicsState()

guard let png = representation.representation(using: .png, properties: [:]) else {
    fatalError("Could not create PNG data.")
}

try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
try png.write(to: outputURL)

let iconSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

if FileManager.default.fileExists(atPath: iconsetURL.path) {
    try FileManager.default.removeItem(at: iconsetURL)
}
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let baseImage = NSImage(contentsOf: outputURL)!
for iconSize in iconSizes {
    let image = NSImage(size: NSSize(width: iconSize.pixels, height: iconSize.pixels))
    image.lockFocus()
    baseImage.draw(in: NSRect(x: 0, y: 0, width: iconSize.pixels, height: iconSize.pixels))
    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let resizedPNG = rep.representation(using: .png, properties: [:])
    else {
        fatalError("Could not create icon size \(iconSize.pixels).")
    }

    try resizedPNG.write(to: iconsetURL.appendingPathComponent(iconSize.name))
}

let icnsEntries: [(type: String, fileName: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { bytes in
        data.append(contentsOf: bytes)
    }
}

func appendOSType(_ value: String, to data: inout Data) {
    data.append(contentsOf: value.utf8)
}

var entryData = Data()
for entry in icnsEntries {
    let imageData = try Data(contentsOf: iconsetURL.appendingPathComponent(entry.fileName))
    appendOSType(entry.type, to: &entryData)
    appendUInt32(UInt32(imageData.count + 8), to: &entryData)
    entryData.append(imageData)
}

var icnsData = Data()
appendOSType("icns", to: &icnsData)
appendUInt32(UInt32(entryData.count + 8), to: &icnsData)
icnsData.append(entryData)
try icnsData.write(to: icnsURL)

print(outputURL.path)
print(icnsURL.path)
