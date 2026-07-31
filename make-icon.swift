// Draws Peekaboo's app icon and writes an .iconset folder.
//
// The ghost is redrawn here in AppKit rather than imported, because the app
// icon needs to read at 16 px as well as 512: thicker outline, bigger eyes,
// fewer details than the SVG in ui/. build.sh turns the output into .icns.
//
// Run with:  swift make-icon.swift <output-dir>

import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out,
                                         withIntermediateDirectories: true)

/// Draws the icon into a square of the given size, in points.
func drawIcon(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)

    // macOS icons leave a margin and sit on a rounded square.
    let pad = s * 0.055
    let box = NSRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let squircle = NSBezierPath(roundedRect: box,
                                xRadius: box.width * 0.235,
                                yRadius: box.width * 0.235)

    // deep violet backdrop, so a pale ghost stands out at any size
    let bg = NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.31, blue: 0.78, alpha: 1),
                                 NSColor(srgbRed: 0.20, green: 0.15, blue: 0.42, alpha: 1)])!
    squircle.addClip()
    bg.draw(in: box, angle: -90)

    // a soft halo behind the ghost
    let halo = NSGradient(colors: [NSColor(white: 1, alpha: 0.22),
                                   NSColor(white: 1, alpha: 0)])!
    halo.draw(in: NSRect(x: box.minX, y: box.minY + box.height * 0.10,
                         width: box.width, height: box.height * 0.95),
              relativeCenterPosition: .zero)

    // --- the ghost, in a 100×100 space mapped onto the box ---
    let u = box.width / 100
    func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        // y measured downwards, like the SVG, then flipped for AppKit
        NSPoint(x: box.minX + x * u, y: box.maxY - y * u)
    }

    let body = NSBezierPath()
    let top: CGFloat = 42, halfW: CGFloat = 30, hem: CGFloat = 66
    body.appendArc(withCenter: P(50, top), radius: halfW * u,
                   startAngle: 0, endAngle: 180)
    body.line(to: P(20, hem))
    // four waves along the hem
    var x: CGFloat = 20
    let step = (halfW * 2) / 4
    for i in 0..<4 {
        let nx = x + step
        body.curve(to: P(nx, hem),
                   controlPoint1: P(x + step * 0.32, hem + 13),
                   controlPoint2: P(nx - step * 0.32, hem + 13))
        x = nx
        _ = i
    }
    body.close()

    NSColor(srgbRed: 0.98, green: 0.99, blue: 1.0, alpha: 1).setFill()
    body.fill()
    NSColor(srgbRed: 0.13, green: 0.15, blue: 0.19, alpha: 1).setStroke()
    body.lineWidth = max(1.2, 3.4 * u)
    body.lineJoinStyle = .round
    body.stroke()

    // eyes — oversized on purpose, they carry the whole character at 16 px
    let eyeR = 6.2 * u
    NSColor(srgbRed: 0.13, green: 0.15, blue: 0.19, alpha: 1).setFill()
    for ex: CGFloat in [37, 63] {
        NSBezierPath(ovalIn: NSRect(x: P(ex, 44).x - eyeR, y: P(ex, 44).y - eyeR * 1.2,
                                    width: eyeR * 2, height: eyeR * 2.4)).fill()
    }
    // catchlights
    NSColor(white: 1, alpha: 0.95).setFill()
    for ex: CGFloat in [39, 65] {
        let r = 2.1 * u
        NSBezierPath(ovalIn: NSRect(x: P(ex, 41).x - r, y: P(ex, 41).y - r,
                                    width: r * 2, height: r * 2)).fill()
    }

    // cheeks — only legible above 64 px, so skip them below
    if s >= 64 {
        NSColor(srgbRed: 1, green: 0.64, blue: 0.73, alpha: 0.55).setFill()
        for cx: CGFloat in [26, 74] {
            NSBezierPath(ovalIn: NSRect(x: P(cx, 55).x - 5.4 * u, y: P(cx, 55).y - 3 * u,
                                        width: 10.8 * u, height: 6 * u)).fill()
        }
    }

    img.unlockFocus()
    return img
}

func write(_ img: NSImage, _ name: String, pixels: Int) {
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}

// The iconset macOS expects: each size at 1x and 2x.
for base in [16, 32, 128, 256, 512] {
    write(drawIcon(CGFloat(base)), "icon_\(base)x\(base).png", pixels: base)
    write(drawIcon(CGFloat(base * 2)), "icon_\(base)x\(base)@2x.png", pixels: base * 2)
}
print("icon drawn into \(out)")
