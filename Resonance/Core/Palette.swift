import SwiftUI
import UIKit

/// Material-style tonal palette built from one seed color. Light and dark variants.
struct Palette: Equatable {
    var primary: Color
    var onPrimary: Color
    var primaryContainer: Color
    var onPrimaryContainer: Color
    var secondaryContainer: Color
    var onSecondaryContainer: Color
    var surface: Color
    var surfaceContainer: Color
    var surfaceContainerHigh: Color
    var onSurface: Color
    var onSurfaceVariant: Color
    var outline: Color

    static let defaultSeed: UInt32 = 0x4F6BD8

    init(seed: UInt32, dark: Bool, amoled: Bool = false) {
        let hsl = HSL(argb: seed)
        // Seeds that are grey or almost black would give a dull palette; keep some chroma.
        let s = min(max(hsl.s, 0.35), 0.85)
        func tone(_ l: Double, _ sat: Double? = nil, hue: Double? = nil) -> Color {
            Color(HSL(h: hue ?? hsl.h, s: sat ?? s, l: l).uiColor)
        }
        let neutral = min(0.14, s * 0.25)
        if dark {
            primary = tone(0.78)
            onPrimary = tone(0.20)
            primaryContainer = tone(0.30)
            onPrimaryContainer = tone(0.90)
            secondaryContainer = tone(0.27, s * 0.45)
            onSecondaryContainer = tone(0.90, s * 0.45)
            surface = amoled ? .black : tone(0.09, neutral)
            surfaceContainer = amoled ? Color(white: 0.07) : tone(0.13, neutral)
            surfaceContainerHigh = amoled ? Color(white: 0.11) : tone(0.17, neutral)
            onSurface = tone(0.90, neutral)
            onSurfaceVariant = tone(0.75, neutral)
            outline = tone(0.50, neutral)
        } else {
            primary = tone(0.40)
            onPrimary = .white
            primaryContainer = tone(0.90)
            onPrimaryContainer = tone(0.15)
            secondaryContainer = tone(0.90, s * 0.45)
            onSecondaryContainer = tone(0.18, s * 0.45)
            surface = tone(0.98, neutral)
            surfaceContainer = tone(0.94, neutral)
            surfaceContainerHigh = tone(0.91, neutral)
            onSurface = tone(0.10, neutral)
            onSurfaceVariant = tone(0.35, neutral)
            outline = tone(0.60, neutral)
        }
    }
}

struct HSL {
    var h: Double // 0...1
    var s: Double
    var l: Double

    init(h: Double, s: Double, l: Double) { self.h = h; self.s = s; self.l = l }

    init(argb: UInt32) {
        let r = Double((argb >> 16) & 0xFF) / 255
        let g = Double((argb >> 8) & 0xFF) / 255
        let b = Double(argb & 0xFF) / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        let d = mx - mn
        var hue = 0.0
        let light = (mx + mn) / 2
        var sat = 0.0
        if d > 0 {
            sat = d / (1 - abs(2 * light - 1))
            if mx == r { hue = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { hue = (b - r) / d + 2 }
            else { hue = (r - g) / d + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        self.h = hue; self.s = sat; self.l = light
    }

    var uiColor: UIColor {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var (r, g, b) = (0.0, 0.0, 0.0)
        switch Int(hp) % 6 {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        let m = l - c / 2
        return UIColor(red: r + m, green: g + m, blue: b + m, alpha: 1)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(seed: Palette.defaultSeed, dark: false)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

enum SeedColor {
    /// The color that best represents a cover: the most saturated, not too dark or light, area.
    static func from(_ image: UIImage) -> UInt32? {
        let size = 24
        guard let cg = image.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: size * size * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard ok else { return nil }
        var best: (score: Double, argb: UInt32)?
        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        for i in 0..<(size * size) {
            let r = Double(data[i * 4]), g = Double(data[i * 4 + 1]), b = Double(data[i * 4 + 2])
            sumR += r; sumG += g; sumB += b
            let argb = UInt32(0xFF) << 24 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
            let hsl = HSL(argb: argb)
            let balance = 1 - abs(hsl.l - 0.5) * 1.6
            let score = hsl.s * max(balance, 0)
            if score > (best?.score ?? 0.08) { best = (score, argb) }
        }
        if let best { return best.argb }
        // Grey cover: fall back to the average, which the palette will give some chroma.
        let n = Double(size * size)
        return UInt32(0xFF) << 24 | UInt32(sumR / n) << 16 | UInt32(sumG / n) << 8 | UInt32(sumB / n)
    }
}

extension Color {
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: 1
        )
    }
}
