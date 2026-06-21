import SwiftUI

/// L'Horizon's visual identity — a calm "cartographer of time": horizon lines, a
/// dawn-to-night gradient, refined serif display over a clean sans body. Every
/// colour and type token lives here so the whole app shares one mood.
enum Theme {

    // MARK: Palette — dawn over night.

    /// Deep indigo night — the furthest, top of the sky.
    static let night = Color(red: 0.07, green: 0.09, blue: 0.18)
    static let nightDeep = Color(red: 0.05, green: 0.06, blue: 0.13)
    /// Violet dusk — the mid sky.
    static let dusk = Color(red: 0.23, green: 0.18, blue: 0.34)
    /// Warm amber dawn at the horizon line.
    static let dawn = Color(red: 0.92, green: 0.59, blue: 0.38)
    static let dawnSoft = Color(red: 0.96, green: 0.72, blue: 0.50)
    /// Sun glow.
    static let glow = Color(red: 0.98, green: 0.81, blue: 0.51)
    /// Parchment / cartographer's paper — used for ink-on-paper surfaces.
    static let parchment = Color(red: 0.96, green: 0.94, blue: 0.89)
    static let parchmentInk = Color(red: 0.17, green: 0.15, blue: 0.13)

    /// Foreground land tones.
    static let landTop = Color(red: 0.16, green: 0.13, blue: 0.21)
    static let landBottom = Color(red: 0.06, green: 0.05, blue: 0.10)

    /// Faint horizon-line stroke colour over the sky.
    static let line = Color(red: 0.98, green: 0.91, blue: 0.80)

    /// Per-horizon accent — near horizons warmer (dawn), far horizons cooler
    /// (night), so the five lanes read as receding into the distance.
    static func accent(_ h: Horizon) -> Color {
        switch h {
        case .threeMonths: return Color(red: 0.97, green: 0.66, blue: 0.42) // warm amber
        case .sixMonths:   return Color(red: 0.93, green: 0.55, blue: 0.45) // coral
        case .oneYear:     return Color(red: 0.78, green: 0.46, blue: 0.55) // rose-violet
        case .threeYears:  return Color(red: 0.52, green: 0.44, blue: 0.66) // violet
        case .fiveYears:   return Color(red: 0.38, green: 0.42, blue: 0.62) // indigo
        }
    }

    static func statusColor(_ s: MilestoneStatus) -> Color {
        switch s {
        case .planned: return Color(red: 0.62, green: 0.62, blue: 0.70)
        case .active:  return Color(red: 0.36, green: 0.74, blue: 0.62)
        case .done:    return Color(red: 0.43, green: 0.78, blue: 0.49)
        case .slipped: return Color(red: 0.90, green: 0.49, blue: 0.40)
        }
    }

    // MARK: Gradients.

    /// The signature dawn-to-night sky used behind the board.
    static var sky: LinearGradient {
        LinearGradient(
            colors: [nightDeep, night, dusk, dawn.opacity(0.55)],
            startPoint: .top, endPoint: .bottom)
    }

    static var landFill: LinearGradient {
        LinearGradient(colors: [landTop, landBottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Type.

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    static func displayLight(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

/// A reusable progress ring in the cartographer style.
struct HorizonRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 6
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))")
                .font(Theme.mono(size * 0.28))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

/// A faint receding-horizon line motif for headers and empty states.
struct HorizonLines: View {
    var count: Int = 5
    var color: Color = Theme.line
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let frac = 1 - pow(1 - Double(i) / Double(count), 1.7)
                    let y = geo.size.height * (1 - 0.85 * frac)
                    let inset = geo.size.width * (0.02 + Double(i) * 0.04)
                    Path { p in
                        p.move(to: CGPoint(x: inset, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width - inset, y: y))
                    }
                    .stroke(color.opacity(0.5 - Double(i) * 0.07),
                            lineWidth: CGFloat(3 - Double(i) * 0.4))
                }
            }
        }
    }
}
