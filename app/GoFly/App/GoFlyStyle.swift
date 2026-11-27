import SwiftUI
import UIKit

/// Canonical semantic theme tokens and shared layout metrics for GoFly iOS.
/// Raw Figma variables live in `GoFlyThemeColor`; text roles live in `GoFlyTypography`.
enum GoFlyStyle {
    // MARK: - Surfaces
    static let canvas = GoFlyThemeColor.canvas
    static let cardSurface = GoFlyThemeColor.surfaceCard
    static let secondarySurface = GoFlyThemeColor.surfaceControl
    static let floatingControlSurface = GoFlyThemeColor.surfaceControlFloating
    static let disabledSurface = GoFlyThemeColor.surfaceDisabled
    static let overlayPanelSurface = GoFlyThemeColor.surfaceOverlaySheet
    static let locationCardSurface = GoFlyThemeColor.surfaceOverlayLocationCard
    static let fieldSurface = GoFlyThemeColor.surfaceInput

    // MARK: - Actions & Status
    static let primary = GoFlyThemeColor.actionPrimarySurface
    static let actionSecondarySurface = GoFlyThemeColor.actionSecondarySurface
    static let danger = GoFlyThemeColor.actionDangerSurface
    static let warning = GoFlyThemeColor.iconWarning
    static let success = GoFlyThemeColor.iconSuccess

    // MARK: - Borders & Separators
    static let border = GoFlyThemeColor.lineBorder
    static let separator = GoFlyThemeColor.lineSeparator
    static let subtleBorder = GoFlyThemeColor.lineSeparator.opacity(0.45)
    static let fieldBorder = GoFlyThemeColor.lineInputDefault
    static let fieldFocus = GoFlyThemeColor.textAccent

    // MARK: - UIKit Bridges
    static let pasteSymbolUIColor = GoFlyThemeColor.uiColor(named: "color/icon/secondary")
    static let inputSurfaceUIColor = GoFlyThemeColor.uiColor(named: "color/surface/input")
    static let inputTextUIColor = GoFlyThemeColor.uiColor(named: "color/text/secondary")
    static let primaryTextUIColor = GoFlyThemeColor.uiColor(named: "color/text/primary")
    static let accentTextUIColor = GoFlyThemeColor.uiColor(named: "color/text/accent")

    // MARK: - Radius, Spacing & Layout
    enum Radius {
        static let small: CGFloat = 12
        static let control: CGFloat = 14
        static let card: CGFloat = 16
        static let sheet: CGFloat = 20
    }

    /// Standard 4 pt spacing scale used across stacks and insets.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    /// Shared screen, sheet, and chrome layout metrics.
    enum Layout {
        static let screenHorizontal: CGFloat = Spacing.lg
        static let sheetHorizontal: CGFloat = Spacing.xl
        static let minTapTarget: CGFloat = 44
        static let hairline: CGFloat = 0.5
        static let compactSheetTop: CGFloat = 44
        static let compactSheetDetentHeight: CGFloat = 300
        static let compactSheetButtonBottom: CGFloat = 15
    }

    static let cornerRadius: CGFloat = Radius.sheet
    static let cardRadius: CGFloat = Radius.card
    static let routeListCardRadius: CGFloat = Radius.control
    static let sheetCornerRadius: CGFloat = Radius.sheet

    static let primaryButtonHeight: CGFloat = 56
    /// Longer than a heartbeat write; see `goFlySteadyDisabled`.
    static let admissionBlipDelay: Duration = .seconds(1)
    /// Visible gap between the search bar / execution header and the status pill.
    static let statusPillTopSpacing: CGFloat = 8
    /// The tappable pill sits in a 44 pt frame around its 30 pt capsule.
    static let statusPillHitInset: CGFloat = 7
    static let favoriteListTopSpacing: CGFloat = 16
    /// Primary button to the bottom edge of its sheet or panel (C2, D6, D7, D10.a, D20, E3).
    static let sheetButtonBottomSpacing: CGFloat = 40
    /// Measured gap a floating sheet adds below its content (home-indicator area),
    /// so a button padded by `favoriteEditorSaveBottomSpacing` sits 40 pt from the sheet bottom.
    private static let sheetBottomAllowance: CGFloat = 29
    static let favoriteEditorSaveBottomSpacing: CGFloat = sheetButtonBottomSpacing - sheetBottomAllowance

    // MARK: - Adaptive Helpers
    /// Figma A-section hero tiles bind to Common Color rather than the theme control surface.
    static func onboardingHeroSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? GoFlyThemeColor.commonGray900 : GoFlyThemeColor.commonGray50
    }

    /// iOS contributes its own sheet scrim (~16% in the iOS 26 simulator).
    /// This supplemental layer composes with it to match the rendered Figma
    /// Overlay/Dim on presented sheets and system dialogs.
    static func systemPresentationDimSupplement(for colorScheme: ColorScheme) -> Color {
        let figmaScrim = colorScheme == .dark ? GoFlyThemeColor.commonBlack : GoFlyThemeColor.commonGray950
        return figmaScrim.opacity(0.20)
    }
}
