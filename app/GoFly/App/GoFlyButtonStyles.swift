import SwiftUI

enum GoFlyButtonVariant: CaseIterable, Equatable, Identifiable {
    case primary, neutral, danger, ghostPrimary, ghostSecondary

    var id: String {
        switch self {
        case .primary: "primary"
        case .neutral: "neutral"
        case .danger: "danger"
        case .ghostPrimary: "ghostPrimary"
        case .ghostSecondary: "ghostSecondary"
        }
    }

    var galleryTitleKey: String { "gallery.button.variant.\(id)" }
    var galleryIcon: GoFlyIconAsset {
        switch self {
        case .primary, .danger: .play
        case .neutral: .star
        case .ghostPrimary: .search
        case .ghostSecondary: .chevronLeft
        }
    }
    var galleryActionKey: String {
        switch self {
        case .primary: "route.start"
        case .neutral: "common.cancel"
        case .danger: "imports.deleteAction"
        case .ghostPrimary: "operation.retry"
        case .ghostSecondary: "common.back"
        }
    }
}

enum GoFlyButtonSize: CaseIterable, Equatable, Identifiable {
    case large, medium, small, extraSmall, inline

    var id: String {
        switch self {
        case .large: "large"
        case .medium: "medium"
        case .small: "small"
        case .extraSmall: "extraSmall"
        case .inline: "inline"
        }
    }

    var galleryTitleKey: String { "gallery.button.size.\(id)" }

    var visibleHeight: CGFloat {
        switch self {
        case .large: 56
        case .medium: 48
        case .small: 40
        case .extraSmall: 32
        case .inline: 40
        }
    }

    var font: GoFlyFont {
        switch self {
        case .large: .bodyEmphasis
        case .medium: .buttonMedium
        case .small: .buttonSmall
        case .extraSmall: .captionEmphasis
        case .inline: .buttonSmall
        }
    }

    var horizontalInset: CGFloat {
        switch self {
        case .large: 24
        case .medium: 20
        case .small: 16
        case .extraSmall: 12
        case .inline: 0
        }
    }
}

/// Figma `Button / Text` and `Button / Icon + Text` (Type × State × Size): the
/// shared label and style for every text button. Use `GoFlyButtonStyle`
/// directly only when the label needs more than a title and an icon.
struct GoFlyButton: View {
    let title: String
    var icon: GoFlyIconAsset? = nil
    var variant: GoFlyButtonVariant = .primary
    var size: GoFlyButtonSize = .large
    let action: () -> Void

    var body: some View {
        Button(action: action) { GoFlyIconLabel(title: title, icon: icon).lineLimit(1) }
            .buttonStyle(GoFlyButtonStyle(variant: variant, size: size))
    }
}

/// One token-driven implementation for Figma's filled, neutral, danger, and
/// text-only buttons. Buttons placed side by side share one size, so their
/// heights match. The visible XS button stays 32 pt while its hit area is 44.
struct GoFlyButtonStyle: ButtonStyle {
    let variant: GoFlyButtonVariant
    var size: GoFlyButtonSize = .large
    var expandsToFill = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let visibleHeight = size.visibleHeight
        let isGhost = variant == .ghostPrimary || variant == .ghostSecondary
        let foreground = foregroundColor
        return configuration.label
            .goFlyFont(size.font)
            .multilineTextAlignment(.center)
            .frame(maxWidth: expandsToFill ? .infinity : nil, minHeight: visibleHeight, alignment: .center)
            .padding(.horizontal, size.horizontalInset)
            .foregroundStyle(foreground)
            .tint(foreground)
            .background(backgroundColor, in: Capsule())
            .overlay {
                if isEnabled && variant == .neutral {
                    Capsule().strokeBorder(GoFlyStyle.separator, lineWidth: 1).allowsHitTesting(false)
                }
            }
            .brightness(isEnabled && configuration.isPressed && !isGhost && variant != .primary && variant != .danger ? -0.04 : 0)
            .opacity(isEnabled && configuration.isPressed && isGhost ? 0.72 : 1)
            .scaleEffect(isEnabled && configuration.isPressed && (variant == .primary || variant == .danger) ? 0.98 : 1)
            .frame(minHeight: max(44, visibleHeight))
            .contentShape(Capsule())
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return (variant == .ghostPrimary || variant == .ghostSecondary) ? .clear : GoFlyStyle.disabledSurface
        }
        return switch variant {
        case .primary: GoFlyStyle.primary
        case .neutral: GoFlyStyle.actionSecondarySurface
        case .danger: GoFlyStyle.danger
        case .ghostPrimary, .ghostSecondary: .clear
        }
    }

    private var foregroundColor: Color {
        guard isEnabled else { return GoFlyTextColor.disabled }
        return switch variant {
        case .primary: GoFlyThemeColor.commonWhite
        case .danger: GoFlyThemeColor.actionDangerText
        case .neutral, .ghostSecondary: GoFlyTextColor.primary
        case .ghostPrimary: GoFlyTextColor.accent
        }
    }
}

/// Status-context action used by banners and snackbars. The visible capsule is
/// 32 pt high; its Button retains the shared 44 pt minimum target.
struct GoFlyStatusActionStyle: ButtonStyle {
    let tone: GoFlyStatusTone

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .goFlyFont(GoFlyFont.subheadlineEmphasis)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minWidth: 48, minHeight: 32)
            .foregroundStyle(isEnabled ? GoFlyTextColor.primary : GoFlyTextColor.disabled)
            .background(backgroundSurface, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isEnabled ? tone.actionBorder : GoFlyStyle.separator,
                                  lineWidth: isEnabled ? tone.actionBorderWidth : 0.5)
                    .allowsHitTesting(false)
            }
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.76 : 1)
    }

    private var backgroundSurface: Color {
        colorScheme == .dark ? .clear : GoFlyStyle.floatingControlSurface
    }
}

/// Shared selectable preset capsule chip used by speed and wander-range sheets.
struct GoFlyPresetChip<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            label()
                .goFlyFont(GoFlyFont.footnoteEmphasis)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    colorScheme == .dark && isSelected ? GoFlyStyle.secondarySurface : GoFlyStyle.cardSurface,
                    in: Capsule()
                )
                .overlay {
                    Capsule().strokeBorder(
                        isSelected ? GoFlyThemeColor.iconAccent : GoFlyStyle.border,
                        lineWidth: 1
                    )
                }
                .foregroundStyle(isSelected ? GoFlyTextColor.accent : GoFlyTextColor.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

enum GoFlyIconButtonVariant: CaseIterable, Equatable, Identifiable {
    case standard, route, ghostStandard, ghostRoute, clear, more, mapControls, copy

    var id: String {
        switch self {
        case .standard: "standard"
        case .route: "route"
        case .ghostStandard: "ghostStandard"
        case .ghostRoute: "ghostRoute"
        case .clear: "clear"
        case .more: "more"
        case .mapControls: "mapControls"
        case .copy: "copy"
        }
    }

    var galleryIcon: GoFlyIconAsset {
        switch self {
        case .standard, .ghostStandard: .star
        case .route, .ghostRoute: .swapHorizontal
        case .clear: .close
        case .more: .more
        case .mapControls: .locate
        case .copy: .copy
        }
    }

    var galleryTitleKey: String { "gallery.iconButton.variant.\(id)" }

    var hasBorder: Bool {
        switch self {
        case .standard, .route, .mapControls, .copy: true
        case .ghostStandard, .ghostRoute, .clear, .more: false
        }
    }

    var surface: Color {
        switch self {
        case .standard, .mapControls, .copy: GoFlyStyle.cardSurface
        case .route: GoFlyStyle.secondarySurface
        case .ghostStandard, .ghostRoute, .clear, .more: .clear
        }
    }

    var foreground: Color {
        switch self {
        case .clear: GoFlyTextColor.secondary
        case .route: GoFlyTextColor.accent
        case .copy: GoFlyThemeColor.iconPrimary
        default: GoFlyTextColor.primary
        }
    }

    var hasFloatingShadow: Bool { self == .mapControls }
}

enum GoFlyIconButtonSize: CaseIterable, Equatable, Identifiable {
    case large, medium, small, extraSmall

    var id: String {
        switch self {
        case .large: "large"
        case .medium: "medium"
        case .small: "small"
        case .extraSmall: "extraSmall"
        }
    }

    var galleryTitleKey: String { "gallery.iconButton.size.\(id)" }

    var diameter: CGFloat {
        switch self { case .large: 44; case .medium: 40; case .small: 36; case .extraSmall: 32 }
    }

    var glyph: CGFloat {
        switch self { case .large: 22; case .medium: 20; case .small: 18; case .extraSmall: 16 }
    }
}

private enum GoFlyIconButtonAppearance {
    static func surface(variant: GoFlyIconButtonVariant, isEnabled: Bool) -> Color {
        if isEnabled { return variant.surface }
        return variant.hasBorder ? GoFlyStyle.disabledSurface : .clear
    }

    static func foreground(variant: GoFlyIconButtonVariant, isEnabled: Bool) -> Color {
        isEnabled ? variant.foreground : GoFlyThemeColor.iconButtonDisabled
    }

    static func border(variant: GoFlyIconButtonVariant, isEnabled: Bool) -> Color? {
        isEnabled && variant.hasBorder ? GoFlyStyle.separator : nil
    }
}

struct GoFlyIconStyle: ButtonStyle {
    var variant: GoFlyIconButtonVariant = .standard
    var size: GoFlyIconButtonSize = .large
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle().fill(GoFlyIconButtonAppearance.surface(variant: variant, isEnabled: isEnabled))
                .frame(width: size.diameter, height: size.diameter)
            configuration.label
                .foregroundStyle(GoFlyIconButtonAppearance.foreground(variant: variant, isEnabled: isEnabled))
                .tint(GoFlyIconButtonAppearance.foreground(variant: variant, isEnabled: isEnabled))
            if let border = GoFlyIconButtonAppearance.border(variant: variant, isEnabled: isEnabled) {
                Circle().strokeBorder(border, lineWidth: 0.5)
                    .frame(width: size.diameter, height: size.diameter)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Circle())
        .goFlyShadow(variant.hasFloatingShadow ? .floating : nil)
        .opacity(isEnabled && configuration.isPressed && !variant.hasFloatingShadow ? 0.7 : 1)
    }
}

/// Shared circle chrome for icon-only controls hosted inside custom rows.
struct GoFlyIconButtonChrome: ViewModifier {
    let diameter: CGFloat
    let showsBorder: Bool
    let enabledSurface: Color?
    let borderColorOverride: Color?
    let variant: GoFlyIconButtonVariant
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        ZStack {
            Circle()
                .fill(enabledSurface ?? GoFlyIconButtonAppearance.surface(variant: variant, isEnabled: isEnabled))
                .frame(width: diameter, height: diameter)
            content.foregroundStyle(GoFlyIconButtonAppearance.foreground(variant: variant, isEnabled: isEnabled))
            let border = isEnabled
                ? (borderColorOverride ?? GoFlyIconButtonAppearance.border(variant: variant, isEnabled: true))
                : GoFlyIconButtonAppearance.border(variant: variant, isEnabled: false)
            if showsBorder, let border {
                Circle().strokeBorder(border, lineWidth: 0.5)
                    .frame(width: diameter, height: diameter)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Circle())
    }
}

extension View {
    func goFlyIconButtonChrome(diameter: CGFloat, showsBorder: Bool = true,
                               enabledSurface: Color? = nil,
                               borderColorOverride: Color? = nil,
                               variant: GoFlyIconButtonVariant = .standard) -> some View {
        modifier(GoFlyIconButtonChrome(diameter: diameter, showsBorder: showsBorder,
                                       enabledSurface: enabledSurface,
                                       borderColorOverride: borderColorOverride,
                                       variant: variant))
    }
}

private struct GoFlyIconForeground: ViewModifier {
    let enabledColor: Color
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.foregroundStyle(isEnabled ? enabledColor : GoFlyTextColor.disabled)
    }
}

extension View {
    func goFlyIconForeground(enabledColor: Color = GoFlyTextColor.primary) -> some View {
        modifier(GoFlyIconForeground(enabledColor: enabledColor))
    }
}
