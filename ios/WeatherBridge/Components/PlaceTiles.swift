import Observation
import SwiftUI
import WeatherCore

/// 장소 카드를 넘기는 정도: 0 = 첫 장소, 1 = 둘째 장소.
/// 넘기는 동안 프레임마다 바뀌므로 타일 줄만 읽게 따로 둔다(화면 전체를 다시 계산하지 않게).
@Observable
final class PagerProgress {
    var value: CGFloat = 0
}

/// 장소 요약 칸 하나
struct PlaceTile: Identifiable {
    var id: PlaceKind { kind }
    let kind: PlaceKind
    let name: String
    /// 큰 글자 (지금 기온)
    let value: String
    /// 아래 줄 ("8–10시 비", "어제보다 −3°")
    let detail: String
    let symbolName: String
    let tint: Color
    /// 오른쪽 위 작은 글 ("최대 68%")
    var badge: String?
}

/// 장소 요약 칸 줄: 집·회사를 나란히(큰 글자면 위아래로) 보이고, 누르면 그 장소를 고른다.
/// 고른 칸 테두리는 `progress`(장소 카드를 넘기는 정도)를 손가락 따라 따라가고, 없으면 고른 칸으로 옮겨 간다.
struct PlaceTileRow: View {
    let tiles: [PlaceTile]
    let selection: PlaceKind
    var progress: PagerProgress?
    let select: (PlaceKind) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let spacing: CGFloat = 8

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // 큰 글자: 위아래로 쌓고 고른 칸에 바로 테두리
            VStack(spacing: spacing) {
                ForEach(tiles) { tile in
                    button(tile)
                        .overlay {
                            if tile.kind == selection {
                                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
            }
        } else {
            HStack(spacing: spacing) {
                ForEach(tiles) { tile in
                    button(tile)
                }
            }
            .overlay(alignment: .leading) {
                SelectionRing(
                    count: tiles.count,
                    spacing: spacing,
                    index: tiles.firstIndex { $0.kind == selection } ?? 0,
                    progress: progress
                )
            }
        }
    }

    private func button(_ tile: PlaceTile) -> some View {
        let isSelected = tile.kind == selection
        return Button {
            select(tile.kind)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Label(tile.name, systemImage: tile.kind.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let badge = tile.badge {
                        Text(badge)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(tile.tint)
                            .contentTransition(.numericText())
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(tile.value)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Image(systemName: tile.symbolName)
                        .font(.subheadline)
                        .foregroundStyle(tile.tint)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(tile.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("이 장소를 봅니다")
    }
}

/// 고른 칸 테두리. 넘기는 정도가 있으면 그대로 따라가고(손가락과 함께), 없으면 고른 칸으로 옮겨 간다.
private struct SelectionRing: View {
    let count: Int
    let spacing: CGFloat
    let index: Int
    let progress: PagerProgress?

    var body: some View {
        GeometryReader { geo in
            let width = (geo.size.width - spacing * CGFloat(max(count - 1, 0))) / CGFloat(max(count, 1))
            // 여기서만 progress를 읽는다
            let position = min(max(progress?.value ?? CGFloat(index), 0), CGFloat(max(count - 1, 0)))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: width, height: geo.size.height)
                .offset(x: position * (width + spacing))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .motion(value: progress == nil ? index : -1)
    }
}
