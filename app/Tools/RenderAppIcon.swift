import AppKit
import Foundation

private let canvas = CGFloat(1024)
private let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png")

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create icon canvas")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

NSColor.clear.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvas, height: canvas)).fill()

let tileRect = NSRect(x: 52, y: 52, width: 920, height: 920)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 218, yRadius: 218)

let tileShadow = NSShadow()
tileShadow.shadowColor = NSColor(calibratedWhite: 0.02, alpha: 0.42)
tileShadow.shadowBlurRadius = 42
tileShadow.shadowOffset = NSSize(width: 0, height: -18)
tileShadow.set()

let tileGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.055, green: 0.090, blue: 0.190, alpha: 1),
    NSColor(calibratedRed: 0.075, green: 0.150, blue: 0.310, alpha: 1),
    NSColor(calibratedRed: 0.145, green: 0.105, blue: 0.330, alpha: 1)
])!
tileGradient.draw(in: tile, angle: -48)

NSGraphicsContext.saveGraphicsState()
tile.addClip()

let glow = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.05, green: 0.90, blue: 0.86, alpha: 0.30), 0),
    (NSColor(calibratedRed: 0.05, green: 0.65, blue: 1.00, alpha: 0.00), 1)
)!
glow.draw(
    fromCenter: NSPoint(x: 700, y: 730),
    radius: 0,
    toCenter: NSPoint(x: 700, y: 730),
    radius: 520,
    options: []
)

let upperHighlight = NSBezierPath(ovalIn: NSRect(x: 110, y: 620, width: 820, height: 430))
NSColor(calibratedWhite: 1, alpha: 0.035).setFill()
upperHighlight.fill()
NSGraphicsContext.restoreGraphicsState()

let boundaryRect = NSRect(x: 205, y: 188, width: 614, height: 648)
let boundary = NSBezierPath(roundedRect: boundaryRect, xRadius: 118, yRadius: 118)
NSColor(calibratedWhite: 1, alpha: 0.065).setFill()
boundary.fill()
boundary.lineWidth = 18
NSColor(calibratedWhite: 1, alpha: 0.20).setStroke()
boundary.stroke()

let innerBoundary = NSBezierPath(
    roundedRect: boundaryRect.insetBy(dx: 34, dy: 34),
    xRadius: 88,
    yRadius: 88
)
innerBoundary.lineWidth = 4
NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.98, alpha: 0.18).setStroke()
innerBoundary.stroke()

let shield = NSBezierPath()
shield.move(to: NSPoint(x: 512, y: 750))
shield.curve(
    to: NSPoint(x: 695, y: 680),
    controlPoint1: NSPoint(x: 574, y: 733),
    controlPoint2: NSPoint(x: 642, y: 706)
)
shield.line(to: NSPoint(x: 681, y: 490))
shield.curve(
    to: NSPoint(x: 512, y: 302),
    controlPoint1: NSPoint(x: 674, y: 402),
    controlPoint2: NSPoint(x: 606, y: 338)
)
shield.curve(
    to: NSPoint(x: 343, y: 490),
    controlPoint1: NSPoint(x: 418, y: 338),
    controlPoint2: NSPoint(x: 350, y: 402)
)
shield.line(to: NSPoint(x: 329, y: 680))
shield.curve(
    to: NSPoint(x: 512, y: 750),
    controlPoint1: NSPoint(x: 382, y: 706),
    controlPoint2: NSPoint(x: 450, y: 733)
)
shield.close()

let shieldShadow = NSShadow()
shieldShadow.shadowColor = NSColor(calibratedRed: 0.02, green: 0.60, blue: 0.88, alpha: 0.38)
shieldShadow.shadowBlurRadius = 30
shieldShadow.shadowOffset = NSSize(width: 0, height: -10)
shieldShadow.set()

let shieldGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.07, green: 0.91, blue: 0.78, alpha: 1),
    NSColor(calibratedRed: 0.06, green: 0.68, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.22, green: 0.40, blue: 0.94, alpha: 1)
])!
shieldGradient.draw(in: shield, angle: -62)

NSGraphicsContext.saveGraphicsState()
shield.addClip()
let shieldShine = NSBezierPath(ovalIn: NSRect(x: 340, y: 575, width: 380, height: 260))
NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
shieldShine.fill()
NSGraphicsContext.restoreGraphicsState()

shield.lineWidth = 7
NSColor(calibratedWhite: 1, alpha: 0.42).setStroke()
shield.stroke()

// A single controlled TCP path crossing the container boundary.
let channel = NSBezierPath()
channel.move(to: NSPoint(x: 138, y: 518))
channel.line(to: NSPoint(x: 388, y: 518))
channel.curve(
    to: NSPoint(x: 480, y: 570),
    controlPoint1: NSPoint(x: 430, y: 518),
    controlPoint2: NSPoint(x: 446, y: 570)
)
channel.line(to: NSPoint(x: 608, y: 570))
channel.lineCapStyle = .round
channel.lineJoinStyle = .round
channel.lineWidth = 28
NSColor(calibratedWhite: 0.98, alpha: 0.96).setStroke()
channel.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 608, y: 570))
arrow.line(to: NSPoint(x: 568, y: 604))
arrow.move(to: NSPoint(x: 608, y: 570))
arrow.line(to: NSPoint(x: 568, y: 536))
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.lineWidth = 28
NSColor(calibratedWhite: 0.98, alpha: 0.96).setStroke()
arrow.stroke()

let entryNode = NSBezierPath(ovalIn: NSRect(x: 113, y: 493, width: 50, height: 50))
NSColor(calibratedRed: 0.10, green: 0.91, blue: 0.84, alpha: 1).setFill()
entryNode.fill()
entryNode.lineWidth = 7
NSColor(calibratedWhite: 1, alpha: 0.86).setStroke()
entryNode.stroke()

let tunnelNode = NSBezierPath(ovalIn: NSRect(x: 417, y: 493, width: 50, height: 50))
NSColor(calibratedRed: 0.08, green: 0.54, blue: 0.95, alpha: 1).setFill()
tunnelNode.fill()
tunnelNode.lineWidth = 7
NSColor(calibratedWhite: 1, alpha: 0.90).setStroke()
tunnelNode.stroke()

let tileOutline = NSBezierPath(roundedRect: tileRect.insetBy(dx: 5, dy: 5), xRadius: 213, yRadius: 213)
tileOutline.lineWidth = 10
NSColor(calibratedWhite: 1, alpha: 0.13).setStroke()
tileOutline.stroke()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon PNG")
}
try png.write(to: outputURL, options: .atomic)
print(outputURL.path)
