import SwiftUI
import GoFlyCore

/// Shared severity vocabulary for the status pill, banners and snackbar.
/// Color is never the only signal: every tone also carries a symbol and a
/// localized accessibility label.
enum GoFlyStatusTone: String, CaseIterable, Equatable, Sendable {
    case neutral
    case active
    case danger
    case warning
    case success

    static var warn: GoFlyStatusTone { .warning }

    var tint: Color {
        switch self {
        case .neutral: GoFlyThemeColor.textSecondary
        case .active: GoFlyStyle.primary
        case .danger: GoFlyStyle.danger
        case .warning: GoFlyStyle.warning
        case .success: GoFlyStyle.success
        }
    }

    var foreground: Color {
        switch self {
        case .neutral, .active: GoFlyStyle.primary
        case .danger: GoFlyThemeColor.textDanger
        case .warning: GoFlyThemeColor.textWarning
        case .success: GoFlyThemeColor.textSuccess
        }
    }

    var symbol: GoFlyIconAsset {
        switch self {
        case .neutral: GoFlySymbols.waiting
        case .active: GoFlySymbols.location
        case .danger: GoFlySymbols.dangerFilled
        case .warning: GoFlySymbols.warningFilled
        case .success: GoFlySymbols.successFilled
        }
    }

    /// Outline symbols used by Figma's `Toast / 系統訊息` components.
    var toastSymbol: GoFlyIconAsset {
        switch self {
        case .neutral: GoFlySymbols.waiting
        case .active: GoFlySymbols.location
        case .danger: .toastDanger
        case .warning: .toastWarning
        case .success: .toastSuccess
        }
    }

    var toastDismiss: Color { GoFlyThemeColor.iconSecondary }

    /// Spoken severity, so VoiceOver does not depend on the color.
    var accessibilityKey: String { "status.tone.\(rawValue)" }

    /// Figma `StatusPill` dot uses the matching neutral, warning, danger, or success icon token.
    var pillDot: Color {
        switch self {
        case .neutral, .active: GoFlyThemeColor.iconSecondary
        case .warning: GoFlyThemeColor.iconWarning
        case .danger: GoFlyThemeColor.iconDanger
        case .success: GoFlyThemeColor.iconSuccess
        }
    }

    /// The disconnected status pill is flat in the Figma component board.
    var pillUsesFloatingShadow: Bool { self != .danger }

    var surface: Color { tint.opacity(0.12) }
    var border: Color {
        switch self {
        case .neutral: GoFlyThemeColor.lineSeparator
        case .active: GoFlyThemeColor.lineStatusInfo
        case .danger: GoFlyThemeColor.lineStatusDanger
        case .warning: GoFlyThemeColor.lineStatusWarning
        case .success: GoFlyThemeColor.lineStatusSuccess
        }
    }

    /// The compact `Button / Status action` variants use their status outline;
    /// success is intentionally neutral in Figma's Light and Dark component boards.
    var actionBorder: Color {
        switch self {
        case .neutral, .active, .success: GoFlyThemeColor.iconSecondary
        case .danger: GoFlyThemeColor.lineStatusDanger
        case .warning: GoFlyThemeColor.lineStatusWarning
        }
    }

    var actionBorderWidth: CGFloat {
        switch self {
        case .success: 1
        case .neutral, .active, .danger, .warning: 0.5
        }
    }

    /// The latest Figma toast's success outline is bound to `icon/success`;
    /// other toast outlines use their matching status line token.
    var toastBorder: Color {
        switch self {
        case .success: GoFlyThemeColor.iconSuccess
        default: border
        }
    }

    /// Toast fill from the Figma `Toast / 系統訊息` variants.
    var toastSurface: Color {
        switch self {
        case .danger: GoFlyThemeColor.surfaceStatusDanger
        case .warning: GoFlyThemeColor.surfaceStatusWarning
        case .success: GoFlyThemeColor.surfaceStatusSuccess
        case .neutral, .active: GoFlyStyle.cardSurface
        }
    }
}

/// One display state for the map and Settings service pill.
typealias GoFlySessionStatus = SessionDisplayStatus

extension SessionDisplayStatus {
    var tone: GoFlyStatusTone {
        switch self {
        case .started, .stopped: .neutral
        case .simulating: .success
        case .paused, .connecting: .warning
        case .error: .danger
        }
    }
}
