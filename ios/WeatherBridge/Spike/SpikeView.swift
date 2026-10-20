import SwiftUI
import UIKit

/// Phase 0 기술 검증 화면 (docs/spikes.md 참고). 설정 → 실험실에서 연다.
struct SpikeView: View {
    @EnvironmentObject private var bridge: LiveActivityBridge
    @State private var channelId = ""

    var body: some View {
        Form {
            Section("상태") {
                LabeledContent("Live Activity 허용", value: bridge.activitiesEnabled ? "예" : "아니요")
                LabeledContent("알림 권한", value: grantedText)
                LabeledContent("진행 중 활동", value: "\(bridge.activeCount)개")
            }

            Section {
                TokenRow(title: "APNs 기기 토큰", token: bridge.apnsDeviceToken)
                TokenRow(title: "push-to-start 토큰", token: bridge.pushToStartToken)
            } header: {
                Text("토큰")
            } footer: {
                Text("서버 스파이크(spike-apns)에 붙여넣어 원격 시작을 시험합니다. 개발자 계정으로 서명된 빌드에서만 발급됩니다.")
            }

            Section {
                Button("샘플 브리핑 시작 (3분)") {
                    bridge.startSample(minutes: 3, channelId: nil)
                }
                TextField("브로드캐스트 채널 ID (선택)", text: $channelId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("채널 구독으로 시작 (3분)") {
                    bridge.startSample(minutes: 3, channelId: channelId)
                }
                .disabled(channelId.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("모두 종료", role: .destructive) {
                    bridge.endAll()
                }
            } header: {
                Text("로컬 테스트")
            } footer: {
                Text("샘플 데이터입니다. 잠금화면에서 표시 → 3분 뒤 '출근 시간 지남' 표시를 확인하세요.")
            }

            if let error = bridge.lastError {
                Section("오류") {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("실험실")
    }

    private var grantedText: String {
        switch bridge.notificationsGranted {
        case .some(true): "허용"
        case .some(false): "거부"
        case .none: "확인 중"
        }
    }
}

private struct TokenRow: View {
    let title: String
    let token: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            if let token {
                Text(token)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(3)
                Button("복사") {
                    UIPasteboard.general.string = token
                }
                .font(.caption)
            } else {
                Text("아직 없음").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
