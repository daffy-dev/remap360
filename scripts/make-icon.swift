// Renders the app icon and logo assets from Sources/Remap360/Views/Brand.swift.
// Built by scripts/bundle.sh: swiftc scripts/make-icon.swift Sources/Remap360/Views/Brand.swift
// Usage: make-icon <out-dir>   → <out-dir>/AppIcon.iconset, logo-mark.png, wordmark-*.png, dmg-background*.png
import AppKit
import SwiftUI

@MainActor
func png<V: View>(_ view: V, scale: CGFloat = 1) -> Data {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    let cg = renderer.cgImage!
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
}

@MainActor
func run() throws {
    let out = URL(fileURLWithPath: CommandLine.arguments[1])
    let iconset = out.appendingPathComponent("AppIcon.iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                       ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
        try png(AppIconArtwork(), scale: CGFloat(px) / 1024).write(to: iconset.appendingPathComponent("icon_\(name).png"))
    }
    try png(AppIconArtwork()).write(to: out.appendingPathComponent("app-icon.png"))
    try png(LogoMark().frame(width: 512, height: 512), scale: 2).write(to: out.appendingPathComponent("logo-mark.png"))
    try png(Wordmark(height: 120).padding(40).environment(\.colorScheme, .dark).background(Brand.ink), scale: 2)
        .write(to: out.appendingPathComponent("wordmark-dark.png"))
    try png(Wordmark(height: 120).padding(40).environment(\.colorScheme, .light).background(Color.white), scale: 2)
        .write(to: out.appendingPathComponent("wordmark-light.png"))
    try png(DMGBackground()).write(to: out.appendingPathComponent("dmg-background.png"))
    try png(DMGBackground(), scale: 2).write(to: out.appendingPathComponent("dmg-background@2x.png"))
}

@main
struct MakeIcon {
    @MainActor static func main() throws { try run() }
}
