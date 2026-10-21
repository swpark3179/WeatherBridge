import SwiftUI
import WeatherCore

/// 여행 날짜 카드 뒤의 움직이는 날씨 장면: 하늘 그라데이션, 도는 햇살, 흘러가는 구름, 빗줄기, 흔들리며 내리는 눈.
/// 동작 줄이기·저전력 모드이거나 지금 보이는 카드가 아니면 멈춘 그림을 그린다.
struct WeatherSceneView: View {
    let sky: TripSky?
    /// 화면에 보이는 카드만 움직인다 (가로로 넘기는 카드가 여러 장이라)
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLowPowerMode) private var isLowPowerMode
    @Environment(\.colorScheme) private var colorScheme

    private var paused: Bool {
        !isActive || reduceMotion || isLowPowerMode
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
            Canvas { canvas, size in
                // 멈춰 있으면 늘 같은 그림
                let time = paused ? 8 : context.date.timeIntervalSinceReferenceDate
                WeatherScene(sky: sky, dark: colorScheme == .dark).draw(in: &canvas, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 장면 그리기. 위치·속도는 번호마다 고정된 값이라 매 프레임 같은 모양이 이어서 움직인다.
private struct WeatherScene {
    let sky: TripSky?
    let dark: Bool

    func draw(in canvas: inout GraphicsContext, size: CGSize, time t: Double) {
        canvas.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(Gradient(colors: palette), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        )
        guard let sky else { return }
        switch sky {
        case .clear:
            sun(&canvas, size, t, strength: 1)
        case .partlyCloudy:
            sun(&canvas, size, t, strength: 0.8)
            clouds(&canvas, size, t, count: 2, scale: 0.9, white: 1, opacity: 0.85)
        case .cloudy:
            clouds(&canvas, size, t, count: 4, scale: 1.15, white: dark ? 0.55 : 0.93, opacity: 0.8)
        case .rain:
            clouds(&canvas, size, t, count: 3, scale: 1.2, white: dark ? 0.35 : 0.7, opacity: 0.85)
            RainStreaks.draw(
                in: &canvas, size: size, time: t, count: 36,
                color: .white.opacity(dark ? 0.35 : 0.55), length: 18, slant: 3
            )
        case .snow:
            clouds(&canvas, size, t, count: 3, scale: 1.1, white: dark ? 0.6 : 0.97, opacity: 0.8)
            snow(&canvas, size, t)
        }
    }

    private var palette: [Color] {
        guard let sky else { return dark ? [rgb(0x1C1F24), rgb(0x2A2E35)] : [rgb(0xD9DEE5), rgb(0xEEF1F5)] }
        switch sky {
        case .clear: return dark ? [rgb(0x0B1D3A), rgb(0x23477A)] : [rgb(0x3A8DFF), rgb(0x9CCBFF)]
        case .partlyCloudy: return dark ? [rgb(0x13233D), rgb(0x2E4766)] : [rgb(0x5A97D6), rgb(0xBBD7F0)]
        case .cloudy: return dark ? [rgb(0x1D232B), rgb(0x3A4350)] : [rgb(0x8D9AAA), rgb(0xCDD5DE)]
        case .rain: return dark ? [rgb(0x11171F), rgb(0x2A3442)] : [rgb(0x56677C), rgb(0x95A4B5)]
        case .snow: return dark ? [rgb(0x1A2332), rgb(0x3E4C60)] : [rgb(0x9DB2CA), rgb(0xEAF0F6)]
        }
    }

    private var sunColor: Color { dark ? rgb(0xFFE08A) : rgb(0xFFD54A) }

    /// 오른쪽 위 해: 숨 쉬듯 번지는 빛과 천천히 도는 햇살
    private func sun(_ canvas: inout GraphicsContext, _ size: CGSize, _ t: Double, strength: Double) {
        let r = min(size.width, size.height) * 0.11
        let c = CGPoint(x: size.width * 0.8, y: size.height * 0.2)
        let glow = r * 3 * CGFloat(1 + 0.06 * sin(t * 1.3))
        canvas.fill(
            Path(ellipseIn: CGRect(x: c.x - glow, y: c.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [sunColor.opacity(0.55 * strength), sunColor.opacity(0)]),
                center: c, startRadius: r * 0.8, endRadius: glow
            )
        )
        let rays = 12
        for i in 0..<rays {
            let angle = Double(i) / Double(rays) * 2 * .pi + t * 0.12
            let (dx, dy) = (CGFloat(cos(angle)), CGFloat(sin(angle)))
            let outer = r * CGFloat(1.75 + 0.12 * sin(t * 2 + Double(i)))
            var ray = Path()
            ray.move(to: CGPoint(x: c.x + dx * r * 1.35, y: c.y + dy * r * 1.35))
            ray.addLine(to: CGPoint(x: c.x + dx * outer, y: c.y + dy * outer))
            canvas.stroke(
                ray,
                with: .color(sunColor.opacity(0.7 * strength)),
                style: StrokeStyle(lineWidth: r * 0.12, lineCap: .round)
            )
        }
        canvas.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(sunColor))
    }

    /// 왼쪽에서 오른쪽으로 흘러가는 구름. 한 층에 그려 겹친 곳이 진해지지 않는다.
    private func clouds(
        _ canvas: inout GraphicsContext, _ size: CGSize, _ t: Double,
        count: Int, scale: CGFloat, white: Double, opacity: Double
    ) {
        canvas.drawLayer { layer in
            layer.opacity = opacity
            for i in 0..<count {
                let width = size.width * CGFloat(0.38 + 0.14 * rand(i, 1)) * scale
                let y = size.height * CGFloat(0.1 + 0.3 * rand(i, 2))
                let speed = 6 + 10 * rand(i, 3) // pt/초
                let span = Double(size.width + width)
                let x = CGFloat((rand(i, 4) * span + t * speed).truncatingRemainder(dividingBy: span)) - width / 2
                layer.fill(cloud(center: CGPoint(x: x, y: y), width: width), with: .color(Color(white: white)))
            }
        }
    }

    private func cloud(center c: CGPoint, width w: CGFloat) -> Path {
        let h = w * 0.45
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: c.x - w / 2, y: c.y, width: w, height: h * 0.5),
            cornerSize: CGSize(width: h * 0.25, height: h * 0.25)
        )
        path.addEllipse(in: CGRect(x: c.x - w * 0.42, y: c.y - h * 0.3, width: w * 0.45, height: h * 0.8))
        path.addEllipse(in: CGRect(x: c.x - w * 0.14, y: c.y - h * 0.62, width: w * 0.5, height: h * 1.1))
        path.addEllipse(in: CGRect(x: c.x + w * 0.12, y: c.y - h * 0.25, width: w * 0.36, height: h * 0.75))
        return path
    }

    /// 크기·속도가 다른 눈송이가 좌우로 흔들리며 내린다
    private func snow(_ canvas: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        for i in 0..<40 {
            let period = 5 + 4 * rand(i, 5)
            let phase = (t / period + rand(i, 6)).truncatingRemainder(dividingBy: 1)
            let y = -6 + (size.height + 12) * CGFloat(phase)
            let x = size.width * CGFloat(rand(i, 7)) + CGFloat(10 * sin(t * (0.6 + rand(i, 8)) + Double(i)))
            let r = CGFloat(1.4 + 2.2 * rand(i, 9))
            canvas.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(.white.opacity(0.65 + 0.3 * rand(i, 10)))
            )
        }
    }

    /// 번호마다 고정된 0..<1 값
    private func rand(_ i: Int, _ salt: Int) -> Double {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }

    private func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// 옅은 빗줄기 (비 상세 카드 글자 뒤). 동작 줄이기가 켜져 있으면 그리지 않고, 저전력 모드에서는 멈춘다.
struct RainStreaks: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLowPowerMode) private var isLowPowerMode

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isLowPowerMode)) { context in
                Canvas { canvas, size in
                    Self.draw(
                        in: &canvas, size: size, time: context.date.timeIntervalSinceReferenceDate,
                        count: 16, color: .blue.opacity(0.3)
                    )
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// 줄기마다 위치·주기(1.1–1.8초)·위상을 고정해 매번 같은 모양으로 떨어진다. `slant`만큼 비스듬히.
    static func draw(
        in canvas: inout GraphicsContext, size: CGSize, time: Double,
        count: Int, color: Color, length: CGFloat = 16, slant: CGFloat = 0
    ) {
        for i in 0..<count {
            let x = size.width * CGFloat((i * 37 + 11) % 97) / 97
            let period = 1.1 + Double((i * 173) % 700) / 1000
            let offset = Double((i * 311) % 1800) / 1800
            let phase = (time / period + offset).truncatingRemainder(dividingBy: 1)
            let y = -length + (size.height + length * 2) * CGFloat(phase)
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x - slant, y: y + length))
            canvas.stroke(streak, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}
