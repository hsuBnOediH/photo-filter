#!/usr/bin/env swift
// Generates Assets/AppIcon.icns with no Xcode required:
//   swift Scripts/make-icon.swift
// Draws a Sonoma-style squircle (gradient + photo stack + funnel badge) at each
// required size — re-rendering per size keeps SF Symbols crisp instead of downscaling
// one master. Replace this whole pipeline with a designed 1024px PNG anytime by
// regenerating the iconset from it.

import AppKit

let sizes: [(Int, Int)] = [  // (point size, scale)
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

func drawIcon(pixels: Int) -> NSImage {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    // macOS icon grid: the squircle occupies ~82.5% of the canvas, centered.
    let inset = size * 0.0875
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    //背景：照片应用风格的蓝→紫渐变
    NSGradient(
        starting: NSColor(calibratedRed: 0.32, green: 0.55, blue: 0.98, alpha: 1),
        ending: NSColor(calibratedRed: 0.55, green: 0.27, blue: 0.85, alpha: 1)
    )?.draw(in: squircle, angle: -60)

    // 主体：photo.stack 符号,白色,带柔和阴影
    func drawSymbol(_ name: String, color: NSColor, frame: NSRect, weight: NSFont.Weight = .medium) {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: frame.height, weight: weight)
        guard let symbol = base.withSymbolConfiguration(config) else { return }
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        color.set()
        let drawRect = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: drawRect)
        drawRect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        // Aspect-fit the tinted symbol into the target frame.
        let aspect = symbol.size.width / symbol.size.height
        var target = frame
        if aspect > 1 {
            target.size.height = frame.width / aspect
            target.origin.y += (frame.height - target.height) / 2
        } else {
            target.size.width = frame.height * aspect
            target.origin.x += (frame.width - target.width) / 2
        }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = size * 0.015
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
        shadow.set()
        tinted.draw(in: target)
        NSShadow().set()
    }

    let mainFrame = NSRect(
        x: rect.minX + rect.width * 0.16,
        y: rect.minY + rect.height * 0.20,
        width: rect.width * 0.68,
        height: rect.height * 0.60
    )
    drawSymbol("photo.stack", color: .white, frame: mainFrame)

    // 角标：右下角漏斗(筛选),表达"filter"
    let badgeSide = rect.width * 0.30
    let badgeFrame = NSRect(
        x: rect.maxX - badgeSide * 1.12,
        y: rect.minY + badgeSide * 0.16,
        width: badgeSide,
        height: badgeSide
    )
    drawSymbol("line.3.horizontal.decrease.circle.fill", color: .white, frame: badgeFrame, weight: .semibold)

    return image
}

// Emit the iconset.
let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("AppIcon.iconset")
let assets = root.appendingPathComponent("Assets")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try? fm.createDirectory(at: assets, withIntermediateDirectories: true)

for (points, scale) in sizes {
    let pixels = points * scale
    let image = drawIcon(pixels: pixels)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { fatalError("render failed at \(pixels)px") }
    rep.size = NSSize(width: points, height: points)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png failed") }
    let suffix = scale == 2 ? "@2x" : ""
    try! png.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}

// iconutil → .icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
try? fm.removeItem(at: iconset)
print("OK: Assets/AppIcon.icns")
