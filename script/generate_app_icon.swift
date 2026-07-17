#!/usr/bin/env swift

import AppKit
import Foundation

guard let outputPath = CommandLine.arguments.dropFirst().first else {
    fputs("usage: generate_app_icon.swift <output.iconset>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let entries: [(pixels: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

var generated: [String: Data] = [:]
for entry in entries {
    let image = renderIcon(pixels: entry.pixels)
    guard let tiff = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: outputDirectory.appending(path: entry.name), options: .atomic)
    generated[entry.name] = data
}

let chunks: [(type: String, name: String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

var payload = Data()
for chunk in chunks {
    guard let png = generated[chunk.name] else { throw CocoaError(.fileReadNoSuchFile) }
    payload.append(contentsOf: chunk.type.utf8)
    appendUInt32(UInt32(png.count + 8), to: &payload)
    payload.append(png)
}

var icon = Data("icns".utf8)
appendUInt32(UInt32(payload.count + 8), to: &icon)
icon.append(payload)
try icon.write(
    to: outputDirectory.deletingPathExtension().appendingPathExtension("icns"),
    options: .atomic
)

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { bytes in
        data.append(contentsOf: bytes)
    }
}

func renderIcon(pixels: Int) -> NSImage {
    let side = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let outerInset = side * 0.055
    let outer = NSBezierPath(
        roundedRect: NSRect(
            x: outerInset,
            y: outerInset,
            width: side - outerInset * 2,
            height: side - outerInset * 2
        ),
        xRadius: side * 0.22,
        yRadius: side * 0.22
    )
    NSColor(srgbRed: 0.09, green: 0.12, blue: 0.14, alpha: 1).setFill()
    outer.fill()

    let drive = NSBezierPath(
        roundedRect: NSRect(
            x: side * 0.18,
            y: side * 0.25,
            width: side * 0.64,
            height: side * 0.49
        ),
        xRadius: side * 0.085,
        yRadius: side * 0.085
    )
    NSColor(srgbRed: 0.88, green: 0.92, blue: 0.93, alpha: 1).setFill()
    drive.fill()

    let slot = NSBezierPath(
        roundedRect: NSRect(
            x: side * 0.27,
            y: side * 0.49,
            width: side * 0.46,
            height: side * 0.105
        ),
        xRadius: side * 0.025,
        yRadius: side * 0.025
    )
    NSColor(srgbRed: 0.16, green: 0.21, blue: 0.23, alpha: 1).setFill()
    slot.fill()

    let indicator = NSBezierPath(ovalIn: NSRect(
        x: side * 0.28,
        y: side * 0.335,
        width: side * 0.055,
        height: side * 0.055
    ))
    NSColor(srgbRed: 0.98, green: 0.48, blue: 0.35, alpha: 1).setFill()
    indicator.fill()

    let badgeRect = NSRect(
        x: side * 0.61,
        y: side * 0.17,
        width: side * 0.24,
        height: side * 0.24
    )
    NSColor(srgbRed: 0.20, green: 0.72, blue: 0.49, alpha: 1).setFill()
    NSBezierPath(ovalIn: badgeRect).fill()

    let check = NSBezierPath()
    check.move(to: NSPoint(x: side * 0.665, y: side * 0.285))
    check.line(to: NSPoint(x: side * 0.71, y: side * 0.24))
    check.line(to: NSPoint(x: side * 0.795, y: side * 0.335))
    check.lineWidth = max(1.5, side * 0.025)
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor.white.setStroke()
    check.stroke()

    let sparkle = NSBezierPath()
    sparkle.move(to: NSPoint(x: side * 0.78, y: side * 0.71))
    sparkle.line(to: NSPoint(x: side * 0.78, y: side * 0.84))
    sparkle.move(to: NSPoint(x: side * 0.715, y: side * 0.775))
    sparkle.line(to: NSPoint(x: side * 0.845, y: side * 0.775))
    sparkle.lineWidth = max(1.2, side * 0.016)
    sparkle.lineCapStyle = .round
    NSColor(srgbRed: 0.99, green: 0.68, blue: 0.28, alpha: 1).setStroke()
    sparkle.stroke()

    return image
}
