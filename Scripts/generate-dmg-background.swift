#!/usr/bin/swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-dmg-background.swift <output.png>\n", stderr)
    exit(2)
}

let width = 600
let height = 360
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Unable to create background bitmap\n", stderr)
    exit(1)
}

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create drawing context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let canvas = NSRect(x: 0, y: 0, width: width, height: height)

NSGradient(colors: [
    NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.98, green: 0.985, blue: 0.995, alpha: 1),
    NSColor(calibratedRed: 0.95, green: 0.97, blue: 1, alpha: 1)
])?.draw(in: canvas, angle: 90)

let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.24, green: 0.65, blue: 1, alpha: 0.14),
    NSColor(calibratedRed: 0.24, green: 0.65, blue: 1, alpha: 0)
])
glow?.draw(in: canvas, relativeCenterPosition: NSPoint(x: 0, y: 0.42))

func drawCentered(_ text: String, top: CGFloat, attributes: [NSAttributedString.Key: Any]) {
    let value = text as NSString
    let size = value.size(withAttributes: attributes)
    value.draw(
        at: NSPoint(x: (CGFloat(width) - size.width) / 2, y: CGFloat(height) - top - size.height),
        withAttributes: attributes
    )
}

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.19, alpha: 1)
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.39, green: 0.45, blue: 0.53, alpha: 1)
]
drawCentered("安装 FastNET", top: 31, attributes: titleAttributes)
drawCentered("将 FastNET 拖到“应用程序”文件夹", top: 63, attributes: subtitleAttributes)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.systemBlue.withAlphaComponent(0.22)
shadow.shadowBlurRadius = 5
shadow.shadowOffset = NSSize(width: 0, height: -1.5)
shadow.set()
NSColor.systemBlue.withAlphaComponent(0.82).setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 250, y: 155))
arrow.line(to: NSPoint(x: 350, y: 155))
arrow.move(to: NSPoint(x: 337, y: 168))
arrow.line(to: NSPoint(x: 351, y: 155))
arrow.line(to: NSPoint(x: 337, y: 142))
arrow.stroke()
NSGraphicsContext.restoreGraphicsState()

let pill = NSBezierPath(roundedRect: NSRect(x: 173, y: 24, width: 254, height: 30), xRadius: 15, yRadius: 15)
NSColor.white.withAlphaComponent(0.74).setFill()
pill.fill()

NSColor(calibratedRed: 0.15, green: 0.71, blue: 0.38, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 193, y: 36, width: 6, height: 6)).fill()

let footerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
    .foregroundColor: NSColor(calibratedRed: 0.39, green: 0.45, blue: 0.53, alpha: 1)
]
("支持 macOS 26 及更高版本" as NSString).draw(
    at: NSPoint(x: 210, y: 32.5),
    withAttributes: footerAttributes
)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode background PNG\n", stderr)
    exit(1)
}

do {
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
} catch {
    fputs("Unable to write background PNG: \(error.localizedDescription)\n", stderr)
    exit(1)
}
