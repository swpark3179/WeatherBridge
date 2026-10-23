import SwiftUI
import WeatherCore

/// 날씨 장면 카드: 뒤에 움직이는 날씨 장면, 위에 머리 칩, 아래에 값 패널.
/// 처음 보일 때 패널 숫자를 굴리고(`revealed`), 보일 때마다 머리의 하늘 아이콘을 한 번 튕긴다(`bounce`).
/// 여행 날짜 카드와 기온 탭 3일 카드가 함께 쓴다.
struct SceneCard<Header: View, Panel: View>: View {
    let sky: TripSky?
    /// 지금 보이는 카드 (장면은 보이는 카드만 움직인다)
    let isActive: Bool
    var height: CGFloat = 380
    /// 머리 칩과 패널 사이 최소 간격 (장면이 보이는 자리)
    var sceneSpace: CGFloat = 56
    @ViewBuilder let header: (_ bounce: Int) -> Header
    @ViewBuilder let panel: (_ revealed: Bool) -> Panel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 처음 보일 때 숫자를 시작 값에서 그 날 값으로 굴린다
    @State private var revealed = false
    /// 이 카드가 보이게 될 때마다 하늘 아이콘을 한 번 튕긴다
    @State private var bounce = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(bounce)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: sceneSpace)

            panel(revealed)
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(10)
        .frame(height: height)
        .background {
            WeatherSceneView(sky: sky, isActive: isActive)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { return }
            if !reduceMotion { bounce += 1 }
            guard !revealed else { return }
            withMotion(Motion.roll.delay(0.15), reduceMotion: reduceMotion) { revealed = true }
        }
    }
}

/// 큰 기온 숫자. 처음에는 시작 값(`from`: 지금·전날 값)을 보이고 그 날 값으로 굴러간다.
struct TempValue: View {
    let title: String
    let value: Double?
    let from: Double?
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let value {
                let shown = Int((revealed ? value : (from ?? value)).rounded())
                Text("\(shown)°")
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: Double(shown)))
            } else {
                Text("–")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(degreesText(value))")
    }
}

/// 하루 강수확률: 비 오는 날이면 우산
struct RainValue: View {
    let rain: TripRain

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Image(systemName: rain.rainy ? "umbrella.fill" : "drop")
                .font(.title3)
            Text("\(rain.pop)%")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(rain.rainy ? Color.blue : Color.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("강수확률 \(rain.pop)%\(rain.rainy ? ", 비 예상" : "")")
    }
}
