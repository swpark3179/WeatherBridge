import SwiftUI
import WeatherCore

/// 장소 카드의 24시간 막대: 맨 위 기온 선과 기온 숫자, 비 구간 괄호, 막대 뒤 구간 음영, 지금·자정·출근 표시, 아래 3시간 눈금.
/// 꾹 누른 채 밀면 그 시각의 강수확률·기온 말풍선이 따라오고(시간마다 햅틱), 누르면 잠깐 보인다.
/// 접근성 문구는 쓰는 쪽이 `.accessibilityLabel`로 붙이고, VoiceOver는 위아래로 쓸어 시간을 넘긴다.
struct RainTimelineView: View {
    let model: RainTimelineModel
    /// 강조할 괄호의 `Bracket.window` (없으면 nil)
    let selectedWindow: Int?
    /// 지금 보이는 카드 (처음 보일 때 막대가 자라고 기온 선이 그려진다)
    var isActive = true
    /// 꾹 눌러 미는 중 (그동안 바깥 스크롤을 막는다)
    @Binding var isScrubbing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false
    /// 말풍선을 보이는 막대 순번
    @State private var scrub: Int?
    @State private var hideTask: Task<Void, Never>?
    /// 꾹 눌러 고르기 시작한 횟수 (햅틱)
    @State private var holds = 0
    /// 한 번이라도 밀어 봤으면 안내를 숨긴다
    @SceneStorage("scrubHintSeen") private var hintSeen = false

    private let tempHeight: CGFloat = 40
    private let bracketHeight: CGFloat = 24
    private let barHeight: CGFloat = 64
    private let markerHeight: CGFloat = 16
    private let axisHeight: CGFloat = 14
    private let spacing: CGFloat = 4

    private var showsTemperature: Bool { model.tempScale != nil }
    private var showsCommuteRow: Bool { !model.commutes.isEmpty }
    /// 지금 바로 비 구간이 있으면 그 괄호 이름과 겹치므로 "지금"은 빼고 선만 둔다
    private var showsNowLabel: Bool { !model.brackets.contains { $0.start < model.now + 3 } }

    private var totalHeight: CGFloat {
        (showsTemperature ? tempHeight + spacing : 0) + bracketHeight + barHeight + axisHeight + spacing * 2
            + (showsCommuteRow ? markerHeight + spacing : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let unit = geo.size.width / CGFloat(max(model.bars.count, 1))
                VStack(alignment: .leading, spacing: spacing) {
                    if showsTemperature {
                        temperatureRow(unit: unit)
                    }
                    bracketRow(unit: unit)
                    barRow(unit: unit)
                    if showsCommuteRow {
                        commuteRow(unit: unit)
                    }
                    axisRow(unit: unit)
                }
                .overlay(alignment: .topLeading) {
                    if let scrub {
                        scrubOverlay(index: scrub, unit: unit, width: geo.size.width)
                    }
                }
                .contentShape(Rectangle())
                .gesture(HoldScrubGesture { point in
                    guard let point else {
                        isScrubbing = false
                        hide(after: 1.2)
                        return
                    }
                    hideTask?.cancel()
                    if !isScrubbing {
                        isScrubbing = true
                        holds += 1
                        hintSeen = true
                    }
                    if let index = model.barIndex(at: point.x / unit), index != scrub {
                        withMotion(Motion.scrub, reduceMotion: reduceMotion) { scrub = index }
                    }
                })
                .onTapGesture(coordinateSpace: .local) { location in
                    guard let index = model.barIndex(at: location.x / unit) else { return }
                    withMotion(Motion.scrub, reduceMotion: reduceMotion) { scrub = index }
                    hide(after: 2)
                }
            }
            .frame(height: totalHeight)
            if !hintSeen, !model.bars.isEmpty {
                Label("꾹 눌러 밀면 시간별 값을 볼 수 있어요", systemImage: "hand.point.up.left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .motion(Motion.fade, value: hintSeen)
        .onChange(of: isActive, initial: true) { _, active in
            if active { appeared = true }
        }
        .onDisappear {
            hideTask?.cancel()
            if isScrubbing { isScrubbing = false }
        }
        // 시간이 바뀔 때마다 (처음 고를 때는 아래 햅틱)
        .sensoryFeedback(trigger: scrub) { old, new in old != nil && new != nil ? SensoryFeedback.selection : nil }
        .sensoryFeedback(.impact(weight: .light), trigger: holds)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(scrub.map { model.accessibilityText(at: $0) } ?? "")
        .accessibilityHint("위아래로 쓸어 시간별 강수확률과 기온을 들어요")
        .accessibilityAdjustableAction { direction in
            guard !model.bars.isEmpty else { return }
            switch direction {
            case .increment: scrub = min((scrub ?? -1) + 1, model.bars.count - 1)
            case .decrement: scrub = max((scrub ?? 1) - 1, 0)
            @unknown default: break
            }
        }
    }

    /// 말풍선을 잠시 뒤 숨긴다. 그 사이 다시 고르면 취소한다
    private func hide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, !isScrubbing else { return }
            withMotion(Motion.fade, reduceMotion: reduceMotion, reduced: Motion.fade) { scrub = nil }
        }
    }

    // MARK: 기온 선

    private func temperatureRow(unit: CGFloat) -> some View {
        // 숫자가 선 위에 붙도록 위쪽은 비워 둔다
        let labelSpace: CGFloat = 14
        let lineHeight = tempHeight - labelSpace - 3
        let width = unit * CGFloat(model.bars.count)
        let shown = appeared || reduceMotion
        return ZStack(alignment: .topLeading) {
            if let scale = model.tempScale {
                TemperatureCurve(segments: model.tempSegments, scale: scale, count: model.bars.count)
                    .trim(from: 0, to: shown ? 1 : 0)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: width, height: lineHeight)
                    .offset(y: labelSpace)
                    .animation(reduceMotion ? nil : Motion.reveal, value: shown)
            }
            ForEach(Array(visibleLabels.enumerated()), id: \.offset) { order, label in
                let x = CGFloat(label.position) * unit
                let y = labelSpace + (1 - CGFloat(model.tempFraction(label.temp) ?? 0)) * lineHeight
                Circle()
                    .fill(label.kind == .low ? Color.blue : Color.orange)
                    .frame(width: label.kind == .tick ? 4 : 5, height: label.kind == .tick ? 4 : 5)
                    .position(x: x, y: y)
                Text(label.text)
                    .font(.caption2.weight(label.kind == .tick ? .regular : .semibold).monospacedDigit())
                    .foregroundStyle(labelColor(label.kind))
                    .fixedSize()
                    .position(x: min(max(x, 10), width - 10), y: y - 9)
                    .opacity(shown ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : Motion.fade.delay(0.2 + 0.8 * Double(order) / Double(max(visibleLabels.count, 1))),
                        value: shown
                    )
            }
        }
        .frame(width: width, height: tempHeight, alignment: .topLeading)
        .opacity(scrub == nil ? 1 : 0.6)
    }

    /// 큰 글자면 3시간 눈금 숫자는 하나 걸러 보인다 (최고·최저는 늘)
    private var visibleLabels: [RainTimelineModel.TempLabel] {
        guard dynamicTypeSize.isAccessibilitySize else { return model.tempLabels }
        var ticks = 0
        return model.tempLabels.filter { label in
            guard label.kind == .tick else { return true }
            defer { ticks += 1 }
            return ticks % 2 == 0
        }
    }

    private func labelColor(_ kind: RainTimelineModel.TempLabel.Kind) -> Color {
        switch kind {
        case .high: .orange
        case .low: .blue
        case .tick: .secondary
        }
    }

    // MARK: 비 구간·막대·눈금

    private func bracketRow(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if showsNowLabel {
                Text("지금")
                    .font(.caption2.weight(.semibold))
                    .offset(x: max(0, unit * model.now - 2))
            }
            ForEach(Array(model.brackets.enumerated()), id: \.offset) { _, bracket in
                let color = bracket.window == selectedWindow ? Color.blue : Color.secondary
                VStack(alignment: .leading, spacing: 2) {
                    Text(bracket.label)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    BracketShape()
                        .stroke(color, lineWidth: 2)
                        .frame(height: 6)
                }
                .foregroundStyle(color)
                .frame(width: max(unit * (bracket.end - bracket.start) - 2, 6), alignment: .leading)
                .offset(x: unit * bracket.start)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: bracketHeight, alignment: .top)
    }

    private func barRow(unit: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(Array(model.brackets.enumerated()), id: \.offset) { _, bracket in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(bracket.window == selectedWindow ? 0.14 : 0.07))
                    .frame(width: unit * (bracket.end - bracket.start), height: barHeight)
                    .offset(x: unit * bracket.start)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(model.bars.enumerated()), id: \.offset) { index, bar in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(bar.level.color)
                        .frame(height: appeared || reduceMotion ? max(3, barHeight * CGFloat(bar.pop) / 100) : 0)
                        .opacity(scrub == nil || scrub == index ? 1 : 0.45)
                        .animation(
                            reduceMotion ? nil : Motion.spring.delay(Double(index) * 0.018),
                            value: appeared
                        )
                }
            }
            .frame(height: barHeight, alignment: .bottom)
            if let midnight = model.midnight {
                VerticalRule()
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                    .frame(width: 1, height: barHeight)
                    .offset(x: unit * midnight)
            }
            ForEach(Array(model.commutes.enumerated()), id: \.offset) { _, commute in
                VerticalRule()
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 1.5, height: barHeight)
                    .offset(x: unit * commute - 0.75)
            }
            Rectangle()
                .fill(Color.primary)
                .frame(width: 1.5, height: barHeight + 4)
                .offset(x: unit * model.now - 0.75)
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .frame(height: barHeight, alignment: .bottom)
    }

    private func commuteRow(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.commutes.enumerated()), id: \.offset) { _, commute in
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(.secondarySystemGroupedBackground))
                    .frame(width: markerHeight, height: markerHeight)
                    .background(Color.primary, in: Circle())
                    .offset(x: unit * commute - markerHeight / 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: markerHeight, alignment: .top)
    }

    private func axisRow(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.ticks.enumerated()), id: \.offset) { _, tick in
                Text(tick.label)
                    .font(.caption2.weight(tick.isDayStart ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(tick.isDayStart ? Color.primary : Color.secondary)
                    .fixedSize()
                    .offset(x: unit * tick.position)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: axisHeight, alignment: .top)
    }

    // MARK: 고른 시각

    /// 고른 막대 가운데 세로선과 맨 위 말풍선 ("16시 · 70% · 19°")
    private func scrubOverlay(index: Int, unit: CGFloat, width: CGFloat) -> some View {
        let x = (CGFloat(index) + 0.5) * unit
        let calloutWidth: CGFloat = 132
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.primary.opacity(0.6))
                .frame(width: 1.5, height: totalHeight - axisHeight)
                .offset(x: x - 0.75)
            Text(model.callout(at: index))
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color(.separator), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                .frame(width: calloutWidth)
                .offset(x: min(max(x - calloutWidth / 2, 0), max(width - calloutWidth, 0)), y: -6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .motionTransition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
    }
}

/// 기온 선: 막대 가운데를 지나는 단조 3차 곡선(값 밖으로 튀어나가지 않는다). 빈 시간에서 끊긴다.
private struct TemperatureCurve: Shape {
    let segments: [[RainTimelineModel.TempPoint]]
    let scale: ClosedRange<Double>
    /// 막대 수
    let count: Int

    func path(in rect: CGRect) -> Path {
        let unit = rect.width / CGFloat(max(count, 1))
        let span = max(scale.upperBound - scale.lowerBound, 1)
        // 1° 오를 때 올라가는 높이
        let rise = rect.height / CGFloat(span)
        func point(_ p: RainTimelineModel.TempPoint) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(p.position) * unit, y: rect.maxY - CGFloat(p.temp - scale.lowerBound) * rise)
        }
        var path = Path()
        for segment in segments {
            guard let first = segment.first else { continue }
            path.move(to: point(first))
            for (a, b) in zip(segment, segment.dropFirst()) {
                let start = point(a)
                let end = point(b)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x + unit / 3, y: start.y - CGFloat(a.slope) * rise / 3),
                    control2: CGPoint(x: end.x - unit / 3, y: end.y + CGFloat(b.slope) * rise / 3)
                )
            }
        }
        return path
    }
}

/// 위가 막힌 괄호 ⎴ 모양
private struct BracketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// 세로선 (점선은 stroke 스타일로 준다)
private struct VerticalRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
