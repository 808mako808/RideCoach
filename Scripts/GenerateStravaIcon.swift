import AppKit

let outputURL = URL(fileURLWithPath: "Assets/RideCoach-Strava-Icon.png")
let side = 1024
let size = NSSize(width: side, height: side)

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

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

let bounds = NSRect(origin: .zero, size: size)
NSColor(red: 252 / 255, green: 76 / 255, blue: 2 / 255, alpha: 1).setFill()
NSBezierPath(roundedRect: bounds, xRadius: 180, yRadius: 180).fill()

func strokePath(_ path: NSBezierPath, width: CGFloat) {
    NSColor.white.setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

strokePath(NSBezierPath(ovalIn: NSRect(x: 194, y: 266, width: 252, height: 252)), width: 54)
strokePath(NSBezierPath(ovalIn: NSRect(x: 578, y: 266, width: 252, height: 252)), width: 54)

let framePath = NSBezierPath()
framePath.move(to: NSPoint(x: 320, y: 392))
framePath.line(to: NSPoint(x: 446, y: 622))
framePath.line(to: NSPoint(x: 552, y: 392))
framePath.line(to: NSPoint(x: 704, y: 392))
framePath.line(to: NSPoint(x: 590, y: 569))
framePath.line(to: NSPoint(x: 690, y: 569))
strokePath(framePath, width: 54)

let handlebarPath = NSBezierPath()
handlebarPath.move(to: NSPoint(x: 438, y: 622))
handlebarPath.line(to: NSPoint(x: 356, y: 622))
strokePath(handlebarPath, width: 54)

let mountainPath = NSBezierPath()
mountainPath.move(to: NSPoint(x: 470, y: 720))
mountainPath.line(to: NSPoint(x: 534, y: 816))
mountainPath.line(to: NSPoint(x: 598, y: 720))
strokePath(mountainPath, width: 46)

NSGraphicsContext.restoreGraphicsState()

guard
    let png = representation.representation(using: .png, properties: [:])
else {
    fatalError("Could not create PNG data.")
}

try png.write(to: outputURL)
print(outputURL.path)
