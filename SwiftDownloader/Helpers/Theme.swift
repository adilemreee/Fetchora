import SwiftUI

enum Theme {
    // MARK: - Theme Resolution
    static var isDark: Bool {
        let mode = UserDefaults.standard.string(forKey: Constants.Keys.themeMode) ?? "system"
        switch mode {
        case "dark": return true
        case "light": return false
        default:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    private static func adaptive(dark: String, light: String) -> Color {
        isDark ? Color(hex: dark) : Color(hex: light)
    }

    // MARK: - Colors
    static var primary: Color { adaptive(dark: "4F8EF7", light: "2563EB") }
    static var primaryLight: Color { adaptive(dark: "7AABFF", light: "3B82F6") }
    static var primaryDark: Color { adaptive(dark: "3A6FD8", light: "1D4ED8") }

    static var accent: Color { adaptive(dark: "34D399", light: "059669") }
    static var accentLight: Color { adaptive(dark: "6EE7B7", light: "10B981") }

    static var warning: Color { adaptive(dark: "F59E0B", light: "B45309") }
    static var warningLight: Color { adaptive(dark: "FCD34D", light: "D97706") }

    static var error: Color { adaptive(dark: "EF4444", light: "DC2626") }
    static var errorLight: Color { adaptive(dark: "FCA5A5", light: "F87171") }

    static var surfacePrimary: Color { adaptive(dark: "1A1B2E", light: "F8F8FA") }
    static var surfaceSecondary: Color { adaptive(dark: "222339", light: "EEEFF3") }
    static var surfaceTertiary: Color { adaptive(dark: "2A2B45", light: "E4E5EB") }
    static var surfaceElevated: Color { adaptive(dark: "32334D", light: "FFFFFF") }

    static var textPrimary: Color { adaptive(dark: "FFFFFF", light: "111827") }
    static var textSecondary: Color { adaptive(dark: "A0A3BD", light: "4B5563") }
    static var textTertiary: Color { adaptive(dark: "6B6F8D", light: "6B7280") }

    static var border: Color { adaptive(dark: "3D3E5C", light: "C8C9D2") }
    static var borderLight: Color { adaptive(dark: "4A4B6A", light: "D8D9E2") }

    // MARK: - Gradients
    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [primary, adaptive(dark: "6C5CE7", light: "4338CA")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var successGradient: LinearGradient {
        LinearGradient(
            colors: [accent, adaptive(dark: "10B981", light: "047857")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var progressGradient: LinearGradient {
        LinearGradient(
            colors: [primary, primaryLight],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [surfacePrimary, adaptive(dark: "0F1021", light: "E8E8ED")],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Dimensions
    static let cornerRadius: CGFloat = 12
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusLarge: CGFloat = 16

    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 16
    static let paddingLarge: CGFloat = 24

    static let sidebarWidth: CGFloat = 220
    static let rowHeight: CGFloat = 72
    static let menuBarWidth: CGFloat = 360
    static let menuBarHeight: CGFloat = 420

    // MARK: - Shadows
    static let shadowColor = Color.black.opacity(0.3)
    static let shadowRadius: CGFloat = 10

    // MARK: - Animation
    static let springAnimation = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let quickAnimation = Animation.easeInOut(duration: 0.2)
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
