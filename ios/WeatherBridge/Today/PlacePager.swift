import SwiftUI
import WeatherCore

/// 장소 카드를 가로로 넘긴다: 한 장씩 멈추고 옆 카드가 살짝 보인다. 고른 장소(`selection`)와 서로 따라가고,
/// 넘기는 정도는 `progress`에 쓴다(타일 테두리만 다시 그리게). 두 카드는 높이를 맞춘다.
struct PlacePager<Card: View>: View {
    let kinds: [PlaceKind]
    @Binding var selection: PlaceKind
    let progress: PagerProgress
    @ViewBuilder let card: (_ kind: PlaceKind, _ isActive: Bool) -> Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 스크롤 위치 (보이는 카드)
    @State private var position: PlaceKind?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(kinds, id: \.self) { kind in
                    card(kind, kind == selection)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .containerRelativeFrame(.horizontal)
                        .pagerCardTransition()
                        // 옆 카드는 VoiceOver가 읽지 않는다 (위 타일로 고른다)
                        .accessibilityHidden(kind != selection)
                }
            }
            .scrollTargetLayout()
            // 두 카드 높이를 더 큰 쪽에 맞춘다
            .fixedSize(horizontal: false, vertical: true)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position)
        .safeAreaPadding(.horizontal, 16)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            let start = -geo.contentInsets.leading
            let end = geo.contentSize.width + geo.contentInsets.trailing - geo.containerSize.width
            guard end > start else { return 0 }
            return min(max((geo.contentOffset.x - start) / (end - start), 0), 1)
        } action: { _, value in
            progress.value = value * CGFloat(max(kinds.count - 1, 0))
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear {
            position = selection
            progress.value = CGFloat(kinds.firstIndex(of: selection) ?? 0)
        }
        .onChange(of: position) { _, new in
            if let new, new != selection { selection = new }
        }
        .onChange(of: selection) { _, new in
            guard position != new else { return }
            withMotion(Motion.standard, reduceMotion: reduceMotion) { position = new }
        }
    }
}
