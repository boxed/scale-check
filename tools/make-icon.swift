// Renders the app icon: the app's 12-note grid (A minor pentatonic) with one
// wrong note lit red.
// Run: swift tools/make-icon.swift ScaleCheck/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

let background = CGGradient(colorsSpace: space, colors: [color(0x23283a), color(0x0c0e15)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: CGFloat(size)), end: .zero, options: [])

let columns = 4, rows = 3
let cell: CGFloat = 180, gap: CGFloat = 36
let gridWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * gap
let gridHeight = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
let left = (CGFloat(size) - gridWidth) / 2
let top = (CGFloat(size) - gridHeight) / 2

let scale: Set<Int> = [0, 3, 5, 7, 10]
let wrong = 1

// The wrong note goes last so its glow lies over its neighbors, not under them.
for offset in (0..<12).filter({ $0 != wrong }) + [wrong] {
    let col = offset % columns, row = offset / columns
    // CoreGraphics has y up; lay rows out top to bottom.
    let rect = CGRect(x: left + CGFloat(col) * (cell + gap),
                      y: CGFloat(size) - top - cell - CGFloat(row) * (cell + gap),
                      width: cell, height: cell)
    let fill: CGColor
    if offset == 0 {
        fill = color(0xff9230)
    } else if offset == wrong {
        fill = color(0xff3b30)
    } else if scale.contains(offset) {
        fill = color(0x0a84ff)
    } else {
        fill = color(0xffffff, 0.12)
    }
    if offset == wrong {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 90, color: color(0xff3b30, 0.9))
    }
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 36, cornerHeight: 36, transform: nil))
    ctx.setFillColor(fill)
    ctx.fillPath()
    if offset == wrong { ctx.restoreGState() }
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
