import AppKit
import Foundation

enum IconError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self { case .invalid(let message): return message }
    }
}

enum IconDesign {
    static let radii: [Double] = [40, 28, 16]
    static let tracks = ["9BBFE7", "8EADD7", "7999C9"]
    static let lamps = ["FF797F", "F7CF6B", "61DFB0"]
    static let start = "344C78"
    static let end = "142039"
    static let border = "203354"

    static func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: alpha).cgColor
    }

    static func position(ring: Int, lamp: Int) -> CGPoint {
        let angle = Double(-90 + lamp * 120 + ring * 35) * .pi / 180
        return CGPoint(x: 64 + radii[ring] * cos(angle), y: 64 + radii[ring] * sin(angle))
    }

    static func circle(_ center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    static func png(pixels: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space,
                                        colors: [color(start), color(end)] as CFArray,
                                        locations: [0, 1]) else {
            throw IconError.invalid("无法创建图标位图或渐变")
        }
        let context = graphics.cgContext
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldAntialias(true)
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: CGFloat(pixels) / 128, y: -CGFloat(pixels) / 128)
        context.saveGState()
        context.addPath(CGPath(roundedRect: CGRect(x: 4, y: 4, width: 120, height: 120),
                               cornerWidth: 28, cornerHeight: 28, transform: nil))
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: 4, y: 4), end: CGPoint(x: 124, y: 124), options: [])
        context.restoreGState()
        context.addPath(CGPath(roundedRect: CGRect(x: 5, y: 5, width: 118, height: 118),
                               cornerWidth: 27, cornerHeight: 27, transform: nil))
        context.setStrokeColor(color("FFFFFF", alpha: 0.16))
        context.setLineWidth(1)
        context.strokePath()
        for ring in radii.indices {
            context.setStrokeColor(color(tracks[ring]))
            context.setLineWidth(2.6)
            context.strokeEllipse(in: circle(CGPoint(x: 64, y: 64), radius: CGFloat(radii[ring])))
        }
        for ring in radii.indices {
            for lamp in lamps.indices {
                context.saveGState()
                context.setAlpha(ring == lamp ? 1 : 0.23)
                // A transparency layer makes fill and border fade as one SVG group.
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.setFillColor(color(lamps[lamp]))
                context.setStrokeColor(color(border))
                context.setLineWidth(1.2)
                context.addEllipse(in: circle(position(ring: ring, lamp: lamp), radius: 4.5))
                context.drawPath(using: .fillStroke)
                context.endTransparencyLayer()
                context.restoreGState()
            }
        }
        guard let data = bitmap.representation(using: .png, properties: [:]), !data.isEmpty else {
            throw IconError.invalid("无法编码图标 PNG")
        }
        return data
    }

    static func number(_ value: CGFloat) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    }

    static func svg(menu: Bool) -> String {
        var lines = ["<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(menu ? "12 12 104 104" : "0 0 128 128")\">",
                     "<title>Traceflow\(menu ? " 菜单栏图标" : " 深蓝同心多环")</title>"]
        if !menu {
            lines += ["<defs><linearGradient id=\"blue\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop stop-color=\"#\(start)\"/><stop offset=\"1\" stop-color=\"#\(end)\"/></linearGradient></defs>",
                      "<rect x=\"4\" y=\"4\" width=\"120\" height=\"120\" rx=\"28\" fill=\"url(#blue)\"/>",
                      "<rect x=\"5\" y=\"5\" width=\"118\" height=\"118\" rx=\"27\" fill=\"none\" stroke=\"white\" stroke-opacity=\"0.16\" stroke-width=\"1\"/>"]
        }
        for ring in radii.indices {
            lines.append("<circle cx=\"64\" cy=\"64\" r=\"\(Int(radii[ring]))\" fill=\"none\" stroke=\"\(menu ? "currentColor" : "#" + tracks[ring])\" stroke-width=\"\(menu ? "5" : "2.6")\"/>")
        }
        for ring in radii.indices {
            for lamp in lamps.indices where !menu || ring == lamp {
                let point = position(ring: ring, lamp: lamp)
                let center = "cx=\"\(number(point.x))\" cy=\"\(number(point.y))\""
                if menu {
                    lines.append("<circle \(center) r=\"4.3\" fill=\"currentColor\"/>")
                } else {
                    lines.append("<g opacity=\"\(ring == lamp ? "1" : "0.23")\"><circle \(center) r=\"4.5\" fill=\"#\(lamps[lamp])\" stroke=\"#\(border)\" stroke-width=\"1.2\"/></g>")
                }
            }
        }
        return (lines + ["</svg>", ""]).joined(separator: "\n")
    }
}

func outputDirectories() throws -> (iconset: URL, sources: URL) {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 4 else { throw IconError.invalid("需要 --iconset 与 --source-dir 两个绝对目录参数") }
    var values: [String: URL] = [:]
    for index in stride(from: 0, to: arguments.count, by: 2) {
        let key = arguments[index], path = arguments[index + 1]
        guard ["--iconset", "--source-dir"].contains(key), values[key] == nil, path.hasPrefix("/") else {
            throw IconError.invalid("参数重复、未知或目录不是绝对路径：\(key)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw IconError.invalid("输出目录不存在：\(path)")
        }
        values[key] = URL(fileURLWithPath: path, isDirectory: true)
    }
    guard let iconset = values["--iconset"], let sources = values["--source-dir"], iconset != sources else {
        throw IconError.invalid("必须提供两个不同的输出目录")
    }
    return (iconset, sources)
}

do {
    let directories = try outputDirectories()
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            try IconDesign.png(pixels: size * scale).write(to: directories.iconset.appendingPathComponent(name), options: .atomic)
        }
    }
    try IconDesign.svg(menu: false).write(to: directories.sources.appendingPathComponent("TraceflowIcon.svg"), atomically: true, encoding: .utf8)
    try IconDesign.svg(menu: true).write(to: directories.sources.appendingPathComponent("TraceflowMenuIcon.svg"), atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("图标生成失败：\(error)\n".utf8))
    exit(1)
}
