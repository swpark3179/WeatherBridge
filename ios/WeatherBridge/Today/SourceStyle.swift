import SwiftUI
import UIKit
import WeatherCore

extension ForecastSourceInfo {
    /// 예보별 막대·선 색. 이웃한 색끼리 색각 이상에서도 구분되는 순서이고, 다크 모드는 어두운 바탕에 맞춘 단계를 따로 쓴다.
    static func color(_ provider: String) -> Color {
        switch provider {
        case "kma_short": dynamic(light: 0x2A78D6, dark: 0x3987E5)
        case "om_ecmwf": dynamic(light: 0xEB6834, dark: 0xD95926)
        case "om_gfs": dynamic(light: 0x1BAF7A, dark: 0x199E70)
        case "om_icon": dynamic(light: 0xEDA100, dark: 0xC98500)
        default: .gray
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
