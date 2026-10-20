import Charts
import SwiftUI

extension View {
    /// 그래프를 처음 열 때 그림 영역을 왼쪽부터 드러내 선이 그려지듯 보이게 한다. 축 눈금과 라벨은 처음부터 보인다.
    /// 동작 줄이기가 켜져 있으면 바로 다 보인다.
    func revealsPlotOnAppear() -> some View {
        modifier(PlotReveal())
    }
}

private struct PlotReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        let shown = reduceMotion ? 1 : progress
        content
            .chartPlotStyle { plot in
                plot.mask {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: geo.size.width * shown)
                    }
                }
            }
            .onAppear {
                guard progress == 0, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.1)) { progress = 1 }
            }
    }
}
