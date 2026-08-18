// ios/scripts/gen-appicon.swift
// Однократный генератор иконки: swift ios/scripts/gen-appicon.swift
import AppKit
import CoreGraphics

let size = 1024.0

// Create bitmap context directly to ensure 1024x1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
let ctx = CGContext(data: nil,
                    width: Int(size),
                    height: Int(size),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo.rawValue)!

// Градиентный фон
let colors = [
    NSColor(red: 0x1B / 255, green: 0x5E / 255, blue: 0x20 / 255, alpha: 1).cgColor,
    NSColor(red: 0x00 / 255, green: 0x45 / 255, blue: 0x0D / 255, alpha: 1).cgColor,
]
let gradient = CGGradient(colorsSpace: colorSpace,
                          colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0),
                       options: [])

ctx.setFillColor(NSColor.white.cgColor)
ctx.setStrokeColor(NSColor.white.cgColor)

// Флагшток
let poleX = 430.0
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: poleX, y: 260))
ctx.addLine(to: CGPoint(x: poleX, y: 790))
ctx.strokePath()

// Флажок (треугольник вправо)
ctx.move(to: CGPoint(x: poleX + 17, y: 780))
ctx.addLine(to: CGPoint(x: poleX + 320, y: 655))
ctx.addLine(to: CGPoint(x: poleX + 17, y: 530))
ctx.closePath()
ctx.fillPath()

// Лунка (эллипс под флагштоком)
ctx.fillEllipse(in: CGRect(x: poleX - 150, y: 195, width: 300, height: 80))

// Get image from context
let cgImage = ctx.makeImage()!
let image = NSImage(cgImage: cgImage, size: NSZeroSize)

// Write PNG
let tiff = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiff)!
let png = bitmap.representation(using: .png, properties: [:])!
let out = "ios/SmartGolfCaddy/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
try! FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent,
                                         withIntermediateDirectories: true)
try! png.write(to: URL(fileURLWithPath: out))
print("written: \(out)")
