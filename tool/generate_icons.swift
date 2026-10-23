// Run from the repository root: swift tool/generate_icons.swift
// Original vector identity. AppKit/CoreGraphics are supplied by macOS; no
// external package is needed. Export opaque PNGs for Apple's icon catalog.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brand = root.appendingPathComponent("assets/branding")
try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let rust = CGColor(colorSpace: colorSpace, components: [182/255, 93/255, 67/255, 1])!
let paper = CGColor(colorSpace: colorSpace, components: [252/255, 247/255, 237/255, 1])!

func bookPath() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 228, y: 286))
  p.addCurve(to: CGPoint(x: 492, y: 306), control1: CGPoint(x: 340, y: 232), control2: CGPoint(x: 424, y: 252))
  p.addLine(to: CGPoint(x: 492, y: 724))
  p.addCurve(to: CGPoint(x: 228, y: 704), control1: CGPoint(x: 405, y: 670), control2: CGPoint(x: 324, y: 664))
  p.closeSubpath()
  p.move(to: CGPoint(x: 532, y: 306))
  p.addCurve(to: CGPoint(x: 796, y: 286), control1: CGPoint(x: 600, y: 252), control2: CGPoint(x: 694, y: 232))
  p.addLine(to: CGPoint(x: 796, y: 704))
  p.addCurve(to: CGPoint(x: 532, y: 724), control1: CGPoint(x: 700, y: 664), control2: CGPoint(x: 620, y: 670))
  p.closeSubpath()
  return p
}

func playPath() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 610, y: 408))
  p.addQuadCurve(to: CGPoint(x: 626, y: 398), control: CGPoint(x: 610, y: 388))
  p.addLine(to: CGPoint(x: 720, y: 454))
  p.addQuadCurve(to: CGPoint(x: 720, y: 474), control: CGPoint(x: 738, y: 464))
  p.addLine(to: CGPoint(x: 626, y: 530))
  p.addQuadCurve(to: CGPoint(x: 610, y: 520), control: CGPoint(x: 610, y: 540))
  p.closeSubpath()
  return p
}

func render(_ size: Int, to url: URL) throws {
  let context = CGContext(data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  context.setAllowsAntialiasing(true)
  context.interpolationQuality = .high
  context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
  context.translateBy(x: 0, y: 1024)
  context.scaleBy(x: 1, y: -1)
  context.setFillColor(rust)
  context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
  context.setFillColor(paper)
  context.addPath(bookPath())
  context.fillPath()
  context.setFillColor(rust)
  context.addPath(playPath())
  context.fillPath()
  context.setStrokeColor(rust.copy(alpha: 0.45)!)
  context.setLineWidth(22)
  context.setLineCap(.round)
  context.move(to: CGPoint(x: 302, y: 393))
  context.addLine(to: CGPoint(x: 414, y: 416))
  context.move(to: CGPoint(x: 302, y: 466))
  context.addLine(to: CGPoint(x: 414, y: 489))
  context.strokePath()
  let image = context.makeImage()!
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("PNG export failed: \(url)") }
}

let bookData = "M228 286C340 232 424 252 492 306V724C405 670 324 664 228 704ZM532 306C600 252 694 232 796 286V704C700 664 620 670 532 724Z"
let playData = "M610 408Q610 388 626 398L720 454Q738 464 720 474L626 530Q610 540 610 520Z"
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="#B65D43"/>
  <path d="\(bookData)" fill="#FCF7ED"/>
  <path d="\(playData)" fill="#B65D43"/>
  <path d="M302 393L414 416M302 466L414 489" stroke="#B65D43" stroke-opacity=".45" stroke-width="22" stroke-linecap="round"/>
</svg>
"""
try svg.write(to: brand.appendingPathComponent("app-icon.svg"), atomically: true, encoding: .utf8)
try render(1024, to: brand.appendingPathComponent("app-icon.png"))

for folder in ["ios/Runner/Assets.xcassets/AppIcon.appiconset", "macos/Runner/Assets.xcassets/AppIcon.appiconset"] {
  let catalog = root.appendingPathComponent(folder)
  let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog.appendingPathComponent("Contents.json"))) as! [String: Any]
  for entry in contents["images"] as! [[String: Any]] {
    guard let filename = entry["filename"] as? String,
      let size = entry["size"] as? String,
      let scale = entry["scale"] as? String else { continue }
    let side = Double(size.split(separator: "x")[0])!
    let multiplier = Double(scale.replacingOccurrences(of: "x", with: ""))!
    try render(Int(side * multiplier), to: catalog.appendingPathComponent(filename))
  }
}
for (density, size) in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)] {
  try render(size, to: root.appendingPathComponent("android/app/src/main/res/mipmap-\(density)/ic_launcher.png"))
}
let drawable = root.appendingPathComponent("android/app/src/main/res/drawable/app_icon_foreground.xml")
try """
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="1024" android:viewportHeight="1024">
  <path android:fillColor="#FCF7ED" android:pathData="\(bookData)"/>
  <path android:fillColor="#B65D43" android:pathData="\(playData)"/>
  <path android:pathData="M302 393L414 416M302 466L414 489" android:strokeColor="#73B65D43" android:strokeWidth="22" android:strokeLineCap="round"/>
</vector>
""".write(to: drawable, atomically: true, encoding: .utf8)
let adaptive = root.appendingPathComponent("android/app/src/main/res/mipmap-anydpi-v26")
try FileManager.default.createDirectory(at: adaptive, withIntermediateDirectories: true)
try """
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/launcher_background"/>
  <foreground android:drawable="@drawable/app_icon_foreground"/>
  <monochrome android:drawable="@drawable/app_icon_monochrome"/>
</adaptive-icon>
""".write(to: adaptive.appendingPathComponent("ic_launcher.xml"), atomically: true, encoding: .utf8)
try """
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="1024" android:viewportHeight="1024">
  <path android:fillColor="#FFFFFF" android:fillType="evenOdd" android:pathData="\(bookData)\(playData)"/>
</vector>
""".write(to: root.appendingPathComponent("android/app/src/main/res/drawable/app_icon_monochrome.xml"), atomically: true, encoding: .utf8)
let colors = root.appendingPathComponent("android/app/src/main/res/values/launcher_colors.xml")
try "<resources><color name=\"launcher_background\">#B65D43</color></resources>".write(to: colors, atomically: true, encoding: .utf8)
print("Generated original book/play icon: iOS, Android (adaptive + monochrome), macOS, and editable SVG.")
