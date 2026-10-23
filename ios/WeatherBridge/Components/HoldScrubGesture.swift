import SwiftUI
import UIKit

/// 꾹 누른 뒤 미는 제스처 (UIKit 길게 누르기). 0.25초 안에 움직이면 실패해서 장소 넘기기·세로 스크롤이 그대로 되고,
/// 누른 채로 머물면 그 뒤로는 미는 동안 위치를 알려 준다. 손을 떼면 nil.
struct HoldScrubGesture: UIGestureRecognizerRepresentable {
    var minimumDuration: TimeInterval = 0.25
    let onChange: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = 10
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(context.converter.localLocation)
        default:
            onChange(nil)
        }
    }
}
