import SwiftUI

/// Figma 04 Theme typography. Text uses `Font.system` at the Figma point size;
/// `@ScaledMetric` applies the matching Dynamic Type curve to every token except
/// the two deliberately fixed display styles, `micro` and `metric`.
enum GoFlyFont: CaseIterable {
    case display, title, wheel, headline, body, bodyEmphasis
    case subheadline, subheadlineEmphasis, footnote, footnoteEmphasis
    case buttonMedium, buttonSmall, caption, captionEmphasis, micro, metric

    var pointSize: CGFloat {
        switch self {
        case .display: 28
        case .title: 20
        case .wheel: 22
        case .headline, .body, .bodyEmphasis: 17
        case .buttonMedium: 16
        case .subheadline, .subheadlineEmphasis: 15
        case .buttonSmall: 14
        case .footnote, .footnoteEmphasis: 13
        case .caption, .captionEmphasis: 12
        case .micro: 10
        case .metric: 36
        }
    }

    var weight: Font.Weight {
        switch self {
        case .wheel, .body, .subheadline, .footnote, .caption: .regular
        default: .semibold
        }
    }

    var dynamicTypeStyle: Font.TextStyle {
        switch self {
        case .display: .title
        case .title: .title3
        case .wheel: .title2
        case .headline: .headline
        case .body, .bodyEmphasis: .body
        case .buttonMedium: .callout
        case .subheadline, .subheadlineEmphasis: .subheadline
        case .buttonSmall, .footnote, .footnoteEmphasis: .footnote
        case .caption, .captionEmphasis, .micro: .caption
        case .metric: .largeTitle
        }
    }

    var isFixed: Bool { self == .micro || self == .metric }
}

private struct GoFlyFontModifier: ViewModifier {
    let token: GoFlyFont
    @ScaledMetric private var scaledPointSize: CGFloat

    init(token: GoFlyFont) {
        self.token = token
        _scaledPointSize = ScaledMetric(wrappedValue: token.pointSize, relativeTo: token.dynamicTypeStyle)
    }

    func body(content: Content) -> some View {
        let size = token.isFixed ? token.pointSize : scaledPointSize
        content.font(.system(size: size, weight: token.weight, design: .default))
    }
}

extension View {
    func goFlyFont(_ token: GoFlyFont) -> some View {
        modifier(GoFlyFontModifier(token: token))
    }
}

// MARK: - Text colors (docs/IOS-TYPOGRAPHY.md)
/// Text and text-like icons use semantic Figma tokens; action foreground uses
/// pure common white per the confirmed Dark primary-button rule.
enum GoFlyTextColor {
    static let primary = GoFlyThemeColor.textPrimary
    static let secondary = GoFlyThemeColor.textSecondary
    static let message = GoFlyThemeColor.textStatusSecondary
    static let disabled = GoFlyThemeColor.textDisabled
    static let inverse = GoFlyThemeColor.commonWhite
    static let onDark = GoFlyThemeColor.commonWhite
    static let danger = GoFlyThemeColor.textDanger
    static let warning = GoFlyThemeColor.textWarning
    static let success = GoFlyThemeColor.textSuccess
    static let accent = GoFlyThemeColor.textAccent
    static let input = GoFlyThemeColor.textInputDefault
    static let inputIcon = GoFlyThemeColor.iconInputDefault
    static let iconAccent = GoFlyThemeColor.iconAccent
}
