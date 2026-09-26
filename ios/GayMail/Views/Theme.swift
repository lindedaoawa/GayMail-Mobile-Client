import SwiftUI

/// 取色自 Android 端 `res/values/colors.xml`，保持两端视觉一致。
extension Color {
    static let gmPrimary = Color(hex: 0x2993C7)
    static let gmPrimaryDark = Color(hex: 0x154963)
    static let gmAccent = Color(hex: 0xF1C40F)
    static let gmBackground = Color(hex: 0xF0F8FF)
    static let gmSurface = Color(hex: 0xFFFFFF)
    static let gmText = Color(hex: 0x154963)
    static let gmDanger = Color(hex: 0xDC3545)
    static let gmSuccess = Color(hex: 0x28A745)
    static let gmUnread = Color(hex: 0x2993C7)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}