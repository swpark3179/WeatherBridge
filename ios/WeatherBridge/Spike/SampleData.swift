import Foundation
import WeatherCore

/// 실험실 화면용 샘플. 실제 예보가 아님을 화면에 표시한다.
enum SampleData {
    static func commuteState(updatedAt: Date) -> CommuteState {
        CommuteState(
            headline: "☔ 회사 15–18시 최대 70% (샘플)",
            highlight: true,
            places: [
                PlaceBrief(
                    name: "집", temp: 12,
                    pops: [0, 0, 10, 10, 10, 10, 20, 20, 20, 10, 10, 10],
                    maxPop: 20, rainWindow: nil
                ),
                PlaceBrief(
                    name: "회사", temp: 15,
                    pops: [0, 0, 10, 10, 20, 30, 40, 50, 60, 70, 60, 40],
                    maxPop: 70, rainWindow: "15–18시"
                ),
            ],
            updatedAt: Int(updatedAt.timeIntervalSince1970)
        )
    }
}
