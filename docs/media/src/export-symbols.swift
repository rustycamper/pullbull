// Exports SF Symbols and the app's custom pullbull.* symbols as black-on-transparent PNG masks at 4x,
// plus a manifest of their point sizes, for the HTML mockup. Usage:
//   swift export-symbols.swift <PullBull.app> <out-dir>
import AppKit

let args = CommandLine.arguments
let bundle = Bundle(path: args[1])!
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let scale: CGFloat = 4

struct Spec { let name: String; let size: CGFloat; let weight: NSFont.Weight; let weightName: String }
func w(_ s: String) -> NSFont.Weight {
    ["regular": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold][s]!
}
// name, point size, weight: every symbol the popover views reference at the size they use it.
let list: [(String, CGFloat, String)] = [
    ("magnifyingglass", 11, "regular"),
    ("line.3.horizontal.decrease", 10, "medium"),
    ("rectangle.split.3x1", 10, "medium"),
    ("xmark", 10, "medium"),
    ("xmark", 7, "bold"),
    ("bookmark", 11, "regular"),
    ("bookmark.fill", 11, "regular"),
    ("book.closed", 11, "regular"),
    ("chevron.right", 9, "bold"),
    ("checkmark.circle", 13, "regular"),
    ("xmark.circle", 13, "regular"),
    ("xmark.circle.fill", 13, "regular"),
    ("clock", 13, "regular"),
    ("minus.circle", 13, "regular"),
    ("minus", 13, "regular"),
    ("arrow.uturn.left", 9.5, "regular"),
    ("arrow.triangle.2.circlepath", 9.5, "regular"),
    ("person.2", 9.5, "regular"),
    ("clock", 9.5, "regular"),
    ("checkmark", 9.5, "regular"),
    ("bubble.left", 9.5, "regular"),
    ("exclamationmark.triangle", 9.5, "regular"),
    ("arrow.uturn.backward", 9, "semibold"),
    ("arrow.triangle.merge", 9, "semibold"),
    ("exclamationmark.triangle", 8, "semibold"),
    ("checkmark", 20, "regular"),
    ("arrow.clockwise", 24, "medium"),
    ("arrow.up.right.square", 24, "medium"),
    ("gearshape", 24, "medium"),
    ("circle.dashed", 11, "regular"),
    ("circle.lefthalf.filled", 11, "regular"),
    ("circle.dotted", 11, "regular"),
    ("square.dashed", 11, "regular"),
    ("checkmark.circle", 11, "regular"),
    ("chevron.left", 13, "medium"),
    ("link", 13, "regular"),
    ("arrow.clockwise", 13, "regular"),
    ("arrow.triangle.branch", 11, "regular"),
    ("arrow.right", 10, "semibold"),
    ("checkmark.circle", 12, "regular"),
    ("xmark.circle.fill", 12, "regular"),
    ("clock", 12, "regular"),
    ("minus.circle", 12, "regular"),
    ("chevron.down", 9, "semibold"),
    ("chevron.right", 9, "semibold"),
    ("arrow.up.right", 9, "semibold"),
    ("checkmark", 9, "semibold"),
    ("clock", 9, "semibold"),
    ("person.2.fill", 9, "regular"),
    ("doc.on.doc", 12, "medium"),
    ("arrow.up.right.square", 12, "medium"),
    ("rectangle.split.3x1", 12, "medium"),
    ("square", 11, "regular"),
    ("checkmark.square.fill", 11, "regular"),
    ("tag", 11, "regular"),
    ("pullbull.issue", 9, "semibold"),
    ("pullbull.pullrequest", 12, "regular"),
    ("pullbull.pullrequest", 13, "semibold"),
    ("pullbull.pullrequest", 13, "regular"),
    ("pullbull.pullrequest.draft", 13, "regular"),
    ("pullbull.pullrequest.merged", 12, "regular"),
    ("pullbull.pullrequest.closed", 12, "regular"),
    ("pullbull.issue", 13, "regular"),
    ("pullbull.issue", 13, "semibold"),
    ("pullbull.issue.closed", 13, "regular"),
    ("pullbull.issue.notplanned", 13, "regular"),
]

var manifest: [String: [String: Any]] = [:]
for (name, size, weightName) in list {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: w(weightName))
    let base: NSImage? = name.hasPrefix("pullbull.")
        ? NSImage(symbolName: name, bundle: bundle, variableValue: 1)
        : NSImage(systemSymbolName: name, accessibilityDescription: nil)
    guard let image = base?.withSymbolConfiguration(config) else {
        FileHandle.standardError.write("missing \(name)\n".data(using: .utf8)!)
        continue
    }
    let pts = image.size
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(ceil(pts.width * scale)), pixelsHigh: Int(ceil(pts.height * scale)),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = pts
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
        image.draw(in: NSRect(origin: .zero, size: pts))
    }
    NSGraphicsContext.restoreGraphicsState()
    let sizeTag = size == floor(size) ? "\(Int(size))" : "\(size)"
    let file = "\(name)-\(sizeTag)-\(weightName).png"
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(file))
    // Baseline offset: how far the image's alignment rect bottom sits below the text baseline.
    // Ink bounds in points (top-left origin), for symbols drawn `.resizable().scaledToFit()`.
    var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = -1, maxY = -1
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    manifest["\(name)|\(sizeTag)|\(weightName)"] = [
        "file": file, "w": Double(pts.width), "h": Double(pts.height),
        "ink": [Double(minX) / scale, Double(minY) / scale, Double(maxX - minX + 1) / scale, Double(maxY - minY + 1) / scale],
    ]
}
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
let js = "// Generated by export-symbols.swift: point sizes of each exported symbol mask.\nwindow.SYMBOLS = " + String(data: json, encoding: .utf8)! + ";\n"
try js.write(to: outDir.appendingPathComponent("manifest.js"), atomically: true, encoding: .utf8)
print("exported \(manifest.count)")
