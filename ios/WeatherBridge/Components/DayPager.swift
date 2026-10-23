import SwiftUI

/// 날짜 카드를 가로로 넘기는 페이저: 옆 카드가 살짝 보이며 줄어들고, 카드 하나씩 멈춘다. 아래에 쪽 점.
/// 여행 상세와 기온 탭 3일 보기가 함께 쓴다. `selected`는 보이는 카드와 서로 따라간다.
struct DayPager<Item: Identifiable, Card: View>: View {
    let items: [Item]
    @Binding var selected: Item.ID?
    @ViewBuilder let card: (_ item: Item, _ isActive: Bool) -> Card

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        card(item, selected == item.id)
                            .containerRelativeFrame(.horizontal)
                            .pagerCardTransition()
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selected)
            .safeAreaPadding(.horizontal, 28)
            .sensoryFeedback(.selection, trigger: selected)

            if items.count > 1 {
                PageDots(ids: items.map(\.id), selected: selected)
            }
        }
    }
}

/// 쪽 점: 고른 쪽은 길게
struct PageDots<ID: Hashable>: View {
    let ids: [ID]
    let selected: ID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ids, id: \.self) { id in
                Capsule()
                    .fill(id == selected ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: id == selected ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: selected)
        .accessibilityHidden(true)
    }
}

extension View {
    /// 페이저 옆 카드: 줄어들며 흐려진다. 동작 줄이기면 흐려지기만 한다
    func pagerCardTransition() -> some View {
        modifier(PagerCardTransition())
    }
}

private struct PagerCardTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shrinks = !reduceMotion
        content.scrollTransition(axis: .horizontal) { content, phase in
            content
                .scaleEffect(phase.isIdentity || !shrinks ? 1 : 0.92)
                .opacity(phase.isIdentity ? 1 : 0.6)
        }
    }
}
