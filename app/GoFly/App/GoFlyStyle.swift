import GoFlyCore
import SwiftUI

/// Semantic color aliases used by shared controls and screens.
enum GoFlyStyle {
    static let surface = GoFlyThemeColor.surfaceCard
    static let cardSurface = GoFlyThemeColor.surfaceCard
    static let canvas = GoFlyThemeColor.canvas
    static let secondarySurface = GoFlyThemeColor.surfaceControl
    static let actionSecondarySurface = GoFlyThemeColor.actionSecondarySurface
    static let primary = GoFlyThemeColor.actionPrimarySurface
    /// User-confirmed exception to the Figma variable's near-white dark value.
    static let primaryActionText = GoFlyThemeColor.commonWhite
    static let secondary = GoFlyThemeColor.textSecondary
    static let disabledForeground = GoFlyThemeColor.textDisabled
    static let disabledSurface = GoFlyThemeColor.surfaceDisabled
    static let errorForeground = GoFlyThemeColor.textDanger
    static let errorSurface = GoFlyThemeColor.surfaceStatusDanger
    static let border = GoFlyThemeColor.lineBorder
    static let subtleBorder = GoFlyThemeColor.lineSeparator.opacity(0.45)
    static let cornerRadius: CGFloat = 20
    /// Longer than a heartbeat write; see `goFlySteadyDisabled`.
    static let admissionBlipDelay: Duration = .seconds(1)
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 14
    static let routeListCardRadius: CGFloat = 14
    static let inputRadius: CGFloat = 12
    static let primaryButtonHeight: CGFloat = 56
    static let secondaryButtonHeight: CGFloat = 48
    static let smallButtonHeight: CGFloat = 40
    /// Visible gap between the search bar / execution header and the status pill.
    static let statusPillTopSpacing: CGFloat = 8
    /// The tappable pill sits in a 44 pt frame around its 30 pt capsule.
    static let statusPillHitInset: CGFloat = 7
    static let favoriteListTopSpacing: CGFloat = 16
    /// Primary button to the bottom edge of its sheet or panel (C2, D6, D7, D10.a, D20, E3).
    static let sheetButtonBottomSpacing: CGFloat = 40
    /// Measured gap a floating sheet adds below its content (home-indicator area),
    /// so a button padded by `favoriteEditorSaveBottomSpacing` sits 40 pt from the sheet bottom.
    static let sheetBottomAllowance: CGFloat = 29
    static let favoriteEditorSaveBottomSpacing: CGFloat = sheetButtonBottomSpacing - sheetBottomAllowance

    static let danger = GoFlyThemeColor.actionDangerSurface
    static let warning = GoFlyThemeColor.iconWarning
    static let success = GoFlyThemeColor.iconSuccess
    static let dangerForeground = GoFlyThemeColor.textDanger
    static let warningForeground = GoFlyThemeColor.textWarning
    static let successForeground = GoFlyThemeColor.textSuccess
    /// Figma A-section hero tiles bind to Common Color rather than the theme control surface.
    static func onboardingHeroSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? GoFlyThemeColor.commonGray900 : GoFlyThemeColor.commonGray50
    }
    static let toastDangerSurface = GoFlyThemeColor.surfaceStatusDanger
    static let toastWarningSurface = GoFlyThemeColor.surfaceStatusWarning
    static let toastSuccessSurface = GoFlyThemeColor.surfaceStatusSuccess
    static let toastMessage = GoFlyThemeColor.textStatusSecondary
    static let toastDismiss = GoFlyThemeColor.iconSecondary
    static let toastActionSurface = GoFlyThemeColor.surfaceControlFloating
    static let toastActionBorder = GoFlyThemeColor.lineBorder
    static let snackbarSurface = GoFlyThemeColor.surfaceCard
    static let snackbarForeground = GoFlyThemeColor.textPrimary
    static let instructionSurface = snackbarSurface
    static let sheetCornerRadius: CGFloat = 20

    // Component-specific roles alias the semantic token table above.
    static let iconButtonSurface = GoFlyThemeColor.surfaceControlFloating
    static let iconButtonBorder = GoFlyThemeColor.lineSeparator
    static let routeControlSurface = GoFlyThemeColor.surfaceControlFloating
    static let routeControlBorder = GoFlyThemeColor.lineSeparator
    static let directionInactive = GoFlyThemeColor.iconSecondary
    static let pasteSymbol = GoFlyThemeColor.iconSecondary
    static let pasteSymbolUIColor = GoFlyThemeColor.uiColor(named: "color/icon/secondary")
    static let inputSurfaceUIColor = GoFlyThemeColor.uiColor(named: "color/surface/input")
    static let inputTextUIColor = GoFlyThemeColor.uiColor(named: "color/text/secondary")
    static let primaryTextUIColor = GoFlyThemeColor.uiColor(named: "color/text/primary")
    static let accentTextUIColor = GoFlyThemeColor.uiColor(named: "color/text/accent")
    static let fieldSurface = GoFlyThemeColor.surfaceInput
    static let fieldFocusedSurface = GoFlyThemeColor.surfaceInput
    static let fieldBorder = GoFlyThemeColor.lineInputDefault
    static let fieldFocus = GoFlyThemeColor.textAccent
    static let overlayPanelSurface = GoFlyThemeColor.surfaceOverlaySheet
    static let tabBarSurface = overlayPanelSurface
    static let locationCardSurface = GoFlyThemeColor.surfaceOverlayLocationCard
    static let tabSeparator = GoFlyThemeColor.lineSeparator
    static let tabInactive = GoFlyThemeColor.iconSecondary
    static let dialogMessage = GoFlyThemeColor.textStatusSecondary
    static let dialogCancelSurface = GoFlyThemeColor.surfaceControl
    static let pillSurface = GoFlyThemeColor.surfaceCard
    static let checkboxOffBorder = GoFlyThemeColor.lineBorder
    static let checkboxOffFill = GoFlyThemeColor.surfaceCard
    static let progressTrack = GoFlyThemeColor.surfaceControl
    static let durationWheelSurface = GoFlyThemeColor.surfaceControl
    static let durationWheelBorder = GoFlyThemeColor.lineSeparator
    static let pillBorder = GoFlyThemeColor.lineBorder
    static let pillDotNeutral = GoFlyThemeColor.iconSecondary
    static let pillDotWarning = GoFlyThemeColor.iconWarning
    static let hairline = GoFlyThemeColor.lineSeparator
    static let snackbarActionSurface = GoFlyThemeColor.surfaceControlFloating
    static let snackbarActionBorder = GoFlyThemeColor.lineSeparator
    static let snackbarBorder = GoFlyThemeColor.lineBorder
    /// iOS contributes its own sheet scrim (~16% in the iOS 26 simulator).
    /// This supplemental layer composes with it to match the rendered Figma
    /// Overlay/Dim on presented sheets and system dialogs.
    static func systemPresentationDimSupplement(for colorScheme: ColorScheme) -> Color {
        let figmaScrim = colorScheme == .dark ? GoFlyThemeColor.commonBlack : GoFlyThemeColor.commonGray950
        return figmaScrim.opacity(0.20)
    }
}

/// Opaque content keeps labels readable over every map style and in Reduce Transparency.
/// Only map overlays receive elevation; ordinary content cards remain flat.
private struct GoFlyCard: ViewModifier {
    var floating: Bool
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .goFlyShadow(floating ? .floating : nil)
    }
}

extension View {
    func goFlyCard(floating: Bool = false, radius: CGFloat = GoFlyStyle.cornerRadius) -> some View {
        modifier(GoFlyCard(floating: floating, radius: radius))
    }
}

/// Each hold heartbeat marks native work busy for a moment, which briefly
/// revokes admission. Show a disabled state only once it has lasted `delay`,
/// so controls do not flicker; the action itself still checks admission.
/// Kept on purpose (2026-11-01): leaving heartbeats out of `nativeBusy` would
/// let commands queue behind a heartbeat that can take up to the 20 s write
/// budget, and would change FIFO admission for Start, teleport and Restore.
private struct GoFlySteadyDisabled: ViewModifier {
    let disabled: Bool
    let delay: Duration
    @State private var shownDisabled: Bool

    init(disabled: Bool, delay: Duration) {
        self.disabled = disabled
        self.delay = delay
        _shownDisabled = State(initialValue: disabled)
    }

    func body(content: Content) -> some View {
        content
            .disabled(shownDisabled)
            .task(id: disabled) {
                if disabled, !shownDisabled {
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                }
                shownDisabled = disabled
            }
    }
}

extension View {
    func goFlySteadyDisabled(_ disabled: Bool, delay: Duration = GoFlyStyle.admissionBlipDelay) -> some View {
        modifier(GoFlySteadyDisabled(disabled: disabled, delay: delay))
    }
}

struct GoFlyEmptyState: View {
    var symbol: GoFlyIconAsset?
    var message: String

    var body: some View {
        VStack(spacing: 16) {
            if let symbol {
                GoFlyIcon(symbol, size: 34, maximumSize: 44)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .frame(width: 80, height: 80)
                    .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 24))
            }
            Text(message)
                .goFlyFont(GoFlyFont.body)
                .foregroundStyle(GoFlyTextColor.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
}

/// Explicit English fallback also covers keys supplied by the service domain.
@MainActor
func goFlyString(_ key: String) -> String {
    let english = Bundle.main.path(forResource: "en", ofType: "lproj")
        .flatMap(Bundle.init(path:))?
        .localizedString(forKey: key, value: nil, table: nil)
    let fallback = english == key ? "GoFly GPS" : (english ?? "GoFly GPS")
    let selected = Bundle.main.path(forResource: GoFlyPreferences.shared.effectiveLanguage, ofType: "lproj")
        .flatMap(Bundle.init(path:))
    return selected?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
}

@MainActor
func goFlyLocalizedFormat(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: format, locale: GoFlyPreferences.shared.locale, arguments: arguments)
}

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
                    Capsule().strokeBorder(GoFlyThemeColor.lineSeparator, lineWidth: 1).allowsHitTesting(false)
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

/// Shared token-driven row shell for Figma's searchable and file lists.
/// Content remains customizable while row height and separator rendering stay consistent.
struct GoFlyListRow<Content: View>: View {
    let minimumHeight: CGFloat
    let separatorLeadingInset: CGFloat?
    let separatorTrailingInset: CGFloat
    @ViewBuilder let content: Content

    init(minimumHeight: CGFloat = 64, separatorLeadingInset: CGFloat? = nil,
         separatorTrailingInset: CGFloat = 0,
         @ViewBuilder content: () -> Content) {
        self.minimumHeight = minimumHeight
        self.separatorLeadingInset = separatorLeadingInset
        self.separatorTrailingInset = separatorTrailingInset
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .overlay(alignment: .bottom) {
                if let separatorLeadingInset {
                    Rectangle()
                        .fill(GoFlyThemeColor.lineSeparator)
                        .frame(height: 0.5)
                        .padding(.leading, separatorLeadingInset)
                        .padding(.trailing, separatorTrailingInset)
                        .accessibilityHidden(true)
                }
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
                    .strokeBorder(isEnabled ? tone.actionBorder : GoFlyThemeColor.lineSeparator,
                                  lineWidth: isEnabled ? tone.actionBorderWidth : 0.5)
                    .allowsHitTesting(false)
            }
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.76 : 1)
    }

    private var backgroundSurface: Color {
        colorScheme == .dark ? .clear : GoFlyStyle.toastActionSurface
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
        isEnabled && variant.hasBorder ? GoFlyThemeColor.lineSeparator : nil
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

// Search, status, and surface roles alias Figma 04 semantic tokens.
/// Figma 04 drop shadows. `floating`: search bar, status pill, map controls, panels,
/// snackbar and instruction card. `card`: location cards. `chip`: speed chip and small icon buttons.
enum GoFlyShadow {
    case floating, toast, card, chip
}

extension View {
    @ViewBuilder
    func goFlyShadow(_ shadow: GoFlyShadow?) -> some View {
        switch shadow {
        case .floating:
            // SwiftUI radius is half the Figma blur.
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.06), radius: 1.5, x: 0, y: 1)
                .shadow(color: GoFlyThemeColor.commonBlack.opacity(0.09), radius: 12, x: 0, y: 5)
        case .toast:
            // Figma toast shadow: black 18%, y=4, blur=16 (SwiftUI radius is half the blur).
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.18), radius: 8, x: 0, y: 4)
        case .card:
            // LocationCard: Figma black 12%, y=6, blur=20 (SwiftUI radius is half the blur).
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.12), radius: 10, x: 0, y: 6)
        case .chip:
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.06), radius: 2, x: 0, y: 1)
        case nil:
            self
        }
    }
}

enum GoFlyTextFieldState: Hashable {
    case `default`, focused, disabled

    var identifier: String {
        switch self {
        case .default: "default"
        case .focused: "focused"
        case .disabled: "disabled"
        }
    }
}

private struct GoFlyTextFieldBackground: ViewModifier {
    let state: GoFlyTextFieldState

    private var appearance: (background: Color, border: Color, borderWidth: CGFloat) {
        switch state {
        case .default:
            (GoFlyStyle.fieldSurface, GoFlyStyle.fieldBorder, 0.75)
        case .focused:
            (GoFlyStyle.fieldFocusedSurface, GoFlyStyle.fieldFocus, 1.5)
        case .disabled:
            (GoFlyStyle.disabledSurface, GoFlyThemeColor.lineInputDisabled, 0.75)
        }
    }

    func body(content: Content) -> some View {
        content
            .background(appearance.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(appearance.border, lineWidth: appearance.borderWidth)
            }
            .foregroundStyle(state == .disabled ? GoFlyTextColor.disabled : GoFlyTextColor.primary)
    }
}

extension View {
    /// `Text Field / Neutral` Figma variants share one implementation.
    func goFlyTextField(state: GoFlyTextFieldState) -> some View {
        modifier(GoFlyTextFieldBackground(state: state))
    }

    func goFlySearchField(isFocused: Bool) -> some View {
        goFlyTextField(state: isFocused ? .focused : .default)
    }
}

/// Figma progress treatment: a 6 pt capsule with semantic track and primary-fill tokens.
struct GoFlyProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)
        Capsule()
            .fill(GoFlyStyle.progressTrack)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(GoFlyStyle.primary)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .accessibilityElement()
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

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
}

/// Page and sheet title row: the title stays centered on the page whatever the
/// widths of the leading and trailing controls.
/// Every sheet grabber: capsule 8 pt from the top, content starts 20 pt below it.
enum GoFlyGrabber {
    static let topInset: CGFloat = 8
    static let capsuleHeight: CGFloat = 5
    static let contentGap: CGFloat = 20
    static let rowHeight: CGFloat = topInset + capsuleHeight + contentGap
}

/// Compatibility alias; unified implementation lives in `GoFlyNavigationBar.swift`.
typealias GoFlySheetHeader<Leading: View, Trailing: View> = GoFlySheetNavBar<Leading, Trailing>

extension View {
    /// A tap outside a text field ends editing; buttons under the tap still fire.
    func goFlyDismissesKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }
}
