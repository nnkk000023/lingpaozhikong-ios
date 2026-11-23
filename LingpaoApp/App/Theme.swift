import SwiftUI

public extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 零跑语义设计色板（精确对齐原安卓版 `OJ` & `DH`，适配浅色与深色模式）
public struct LingpaoPalette: Sendable {
    public let background: Color
    public let card: Color
    public let ink: Color
    public let secondary: Color
    public let line: Color
    public let inactive: Color
    public let danger: Color
    public let good: Color
    public let warning: Color
    public let positiveText: Color
    public let warningText: Color
    public let dangerText: Color
    public let accent: Color

    public static let light = LingpaoPalette(
        background: Color(hex: 0xEEF0F3),
        card: Color.white,
        ink: Color(hex: 0x1C2140),
        secondary: Color(hex: 0x5F6474),
        line: Color(hex: 0xE3E5EA),
        inactive: Color(hex: 0x6B7080),
        danger: Color(hex: 0xC2412D),
        good: Color(hex: 0x1FA463),
        warning: Color(hex: 0xC77F0A),
        positiveText: Color(hex: 0x12633C),
        warningText: Color(hex: 0x805000),
        dangerText: Color(hex: 0x9F3020),
        accent: Color(hex: 0x1FA463)
    )

    public static let dark = LingpaoPalette(
        background: Color(hex: 0x0F1117),
        card: Color(hex: 0x1C1F2A),
        ink: Color(hex: 0xECEEF3),
        secondary: Color(hex: 0x8E93A2),
        line: Color(hex: 0x2E3240),
        inactive: Color(hex: 0x7C8191),
        danger: Color(hex: 0xE0644F),
        good: Color(hex: 0x1FA463),
        warning: Color(hex: 0xE8A33D),
        positiveText: Color(hex: 0x72D5A2),
        warningText: Color(hex: 0xF4C277),
        dangerText: Color(hex: 0xFF9D8B),
        accent: Color(hex: 0x28B872)
    )

    public static func forScheme(_ scheme: ColorScheme) -> LingpaoPalette {
        scheme == .dark ? .dark : .light
    }
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    init(argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// 统一圆角信息卡片容器修饰器
public struct LingpaoCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var padding: CGFloat

    public init(padding: CGFloat = 16) {
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(palette.card)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.045), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(palette.line.opacity(0.65), lineWidth: 0.75)
            )
    }
}

public extension View {
    func lingpaoCard(padding: CGFloat = 16) -> some View {
        modifier(LingpaoCardStyle(padding: padding))
    }
}
