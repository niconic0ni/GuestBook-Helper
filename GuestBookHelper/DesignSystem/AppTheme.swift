import SwiftUI
import UIKit

// MARK: - Appearance

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "自动"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var detailTitle: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色外观"
        case .dark: return "深色外观"
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.fill"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Palette

enum AppTheme {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let canvas = dynamic(light: 0xF3F3F0, dark: 0x08090C)
    static let canvasUIColor = UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? 0x08090C : 0xF3F3F0)
    }
    static let canvasDeep = dynamic(light: 0xE9E9E4, dark: 0x0D0F14)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x141519)
    static let surfaceElevated = dynamic(light: 0xFFFFFF, dark: 0x1B1C21)
    static let surfaceMuted = dynamic(light: 0xF0F0EC, dark: 0x1F2026)
    static let ink = dynamic(light: 0x121216, dark: 0xF4F3EE)
    static let secondary = dynamic(light: 0x68686F, dark: 0xA8A8B0)
    static let tertiary = dynamic(light: 0x9A9AA1, dark: 0x73737D)
    static let line = dynamic(light: 0xE1E1DB, dark: 0x2B2C33)
    static let lineStrong = dynamic(light: 0xCFCFC8, dark: 0x3B3C45)
    static let accent = dynamic(light: 0x0A6CFF, dark: 0x5B9CFF)
    static let accentUIColor = UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? 0x5B9CFF : 0x0A6CFF)
    }
    static let accentDeep = dynamic(light: 0x0047B8, dark: 0x2E6FE0)
    static let accentSoft = dynamic(light: 0xE7F0FF, dark: 0x132440)
    static let gold = dynamic(light: 0xA47A3D, dark: 0xD9B87B)
    static let goldSoft = dynamic(light: 0xF6EEDF, dark: 0x2B2318)
    static let success = dynamic(light: 0x157A4B, dark: 0x5DDEA0)
    static let successSoft = dynamic(light: 0xE2F4EA, dark: 0x12291F)
    static let warning = dynamic(light: 0xA66312, dark: 0xF3B65B)
    static let warningSoft = dynamic(light: 0xFBF0DD, dark: 0x2D2315)
    static let danger = dynamic(light: 0xB43737, dark: 0xFF8585)
    static let dangerSoft = dynamic(light: 0xFBE7E6, dark: 0x2F1717)
    static let sold = dynamic(light: 0x76767E, dark: 0x8D8D97)
    static let soldSoft = dynamic(light: 0xEFEFEE, dark: 0x23242A)
    static let searchFill = dynamic(light: 0xE9E9E4, dark: 0x1D1E23)
    static let searchFillUIColor = UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? 0x1D1E23 : 0xE9E9E4)
    }
    static let separator = dynamic(light: 0xE7E7E2, dark: 0x2B2C33)
    static let shadow = dynamic(light: 0x000000, dark: 0x000000)

    static let cardShadow = Color.black.opacity(0.055)

    static func categoryColor(_ lob: String) -> Color {
        switch lob.lowercased() {
        case "iphone": return dynamic(light: 0x1668E3, dark: 0x6CA6FF)
        case "ipad": return dynamic(light: 0x7C4DDB, dark: 0xB79BFF)
        case "watch": return dynamic(light: 0x1B8A6B, dark: 0x65D7B6)
        case "airpods", "audio": return dynamic(light: 0xC17B18, dark: 0xF3BE6B)
        case "mac": return dynamic(light: 0x535C68, dark: 0xB9C2CF)
        default: return dynamic(light: 0x6A6A72, dark: 0xA7A7B0)
        }
    }

    static func categorySoftColor(_ lob: String) -> Color {
        categoryColor(lob).opacity(0.13)
    }

    static func categorySymbol(_ lob: String) -> String {
        let symbol: String
        switch lob.lowercased() {
        case "iphone": symbol = "iphone"
        case "ipad": symbol = "ipad"
        case "watch": symbol = "applewatch"
        case "airpods", "audio": symbol = "airpods"
        case "mac": symbol = "laptopcomputer"
        default: symbol = "shippingbox"
        }
        return SFSymbol.available(symbol, fallback: "shippingbox")
    }

    static func statusColor(for type: TransactionType) -> Color {
        switch type {
        case .transferIn: return success
        case .returned: return gold
        case .transferOut: return sold
        case .sellout: return sold
        case .unknown: return tertiary
        }
    }

    static func statusSoftColor(for type: TransactionType) -> Color {
        switch type {
        case .transferIn: return successSoft
        case .returned: return goldSoft
        case .transferOut: return soldSoft
        case .sellout: return soldSoft
        case .unknown: return surfaceMuted
        }
    }

    static func conditionColor(for condition: ItemCondition) -> Color {
        switch condition {
        case .good: return success
        case .demo: return warning
        case .defective: return danger
        case .unknown: return tertiary
        }
    }

    static func conditionSoftColor(for condition: ItemCondition) -> Color {
        switch condition {
        case .good: return successSoft
        case .demo: return warningSoft
        case .defective: return dangerSoft
        case .unknown: return surfaceMuted
        }
    }
}

// MARK: - Helpers

enum SFSymbol {
    static func available(_ name: String, fallback: String = "questionmark") -> String {
        if UIImage(systemName: name) != nil { return name }
        if UIImage(systemName: fallback) != nil { return fallback }
        return "circle"
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension Font {
    static func gbSerif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func gbMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Background

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.canvas
            RadialGradient(
                colors: [
                    AppTheme.accent.opacity(colorScheme == .dark ? 0.14 : 0.055),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 520
            )
            LinearGradient(
                colors: [
                    Color.clear,
                    AppTheme.canvasDeep.opacity(colorScheme == .dark ? 0.85 : 0.5)
                ],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - Cards & typography

struct SectionKicker: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.6)
            .foregroundColor(AppTheme.tertiary)
    }
}

struct SectionHeading: View {
    var title: String
    var subtitle: String?
    var trailing: AnyView?

    init(_ title: String, subtitle: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundColor(AppTheme.ink)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondary)
                }
            }
            Spacer(minLength: 8)
            if let trailing = trailing { trailing }
        }
    }
}

struct SurfaceCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 0
    var shadow: Bool = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                )
        } else {
            content
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(AppTheme.line.opacity(0.9), lineWidth: 0.8)
                        )
                )
                .shadow(color: shadow ? AppTheme.cardShadow : .clear, radius: 16, x: 0, y: 8)
        }
    }
}

extension View {
    func surfaceCard(cornerRadius: CGFloat = 22, padding: CGFloat = 0, shadow: Bool = true) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius, padding: padding, shadow: shadow))
    }

    func gbHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Buttons

struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: AppTheme.accent.opacity(0.22), radius: 10, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundColor(destructive ? AppTheme.danger : AppTheme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppTheme.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(AppTheme.line.opacity(0.9), lineWidth: 0.7)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - iOS 13 navigation helpers

extension View {
    @ViewBuilder
    func gbInlineTitle(_ title: String) -> some View {
        if #available(iOS 14.0, *) {
            self.navigationBarTitle(title, displayMode: .inline)
        } else {
            self.navigationBarTitle(title)
        }
    }
}
