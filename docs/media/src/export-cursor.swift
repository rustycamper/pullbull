// Saves the system arrow cursor (NSCursor.arrow) as a 4x PNG for the mockup. Usage:
//   swift export-cursor.swift <out.png>
import AppKit

_ = NSApplication.shared
let img = NSCursor.arrow.image
let scale = 4.0
let bmp = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(img.size.width * scale), pixelsHigh: Int(img.size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
bmp.size = img.size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
img.draw(in: NSRect(origin: .zero, size: img.size))
NSGraphicsContext.restoreGraphicsState()
try! bmp.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
