import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("오늘", systemImage: "cloud.sun") {
                TodayPlaceholderView()
            }
            Tab("실험실", systemImage: "flask") {
                SpikeView()
            }
        }
    }
}

private struct TodayPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "준비 중",
                systemImage: "cloud.sun.rain",
                description: Text("집·회사의 시간대별 강수확률은 Phase 2에서 표시됩니다.")
            )
            .navigationTitle("WeatherBridge")
        }
    }
}
