import GoFlyCore
import SwiftUI

/// Semantic aliases for the Figma 04 icon catalog. Values are typed asset
/// identifiers rather than SF Symbols; all drawing is performed by GoFlyIcon.
enum GoFlySymbols {
    static let recenter: GoFlyIconAsset = .locate
    static let fitRoute: GoFlyIconAsset = .expand
    static let location: GoFlyIconAsset = .nav
    static let place: GoFlyIconAsset = .pin
    static let sample: GoFlyIconAsset = .mapNodeWaypoint
    static let favorite: GoFlyIconAsset = .star
    static let favoriteSelected: GoFlyIconAsset = .starFilled
    static let search: GoFlyIconAsset = .search
    static let clearSearch: GoFlyIconAsset = .close
    static let settings: GoFlyIconAsset = .gear
    static let close: GoFlyIconAsset = .close
    static let back: GoFlyIconAsset = .chevronLeft
    static let disclosure: GoFlyIconAsset = .chevronRight
    static let expand: GoFlyIconAsset = .chevronDown
    static let selected: GoFlyIconAsset = .check
    static let checked: GoFlyIconAsset = .select
    static let play: GoFlyIconAsset = .play
    static let pause: GoFlyIconAsset = .pause
    static let delete: GoFlyIconAsset = .trash
    static let reorder: GoFlyIconAsset = .grip
    static let externalLink: GoFlyIconAsset = .externalLink
    static let retry: GoFlyIconAsset = .repeat
    static let reset: GoFlyIconAsset = .reset
    static let warning: GoFlyIconAsset = .alert
    static let success: GoFlyIconAsset = .success
    static let help: GoFlyIconAsset = .help
    static let network: GoFlyIconAsset = .shield
    static let device: GoFlyIconAsset = .phone
    static let language: GoFlyIconAsset = .globe
    static let appearance: GoFlyIconAsset = .moon
    static let background: GoFlyIconAsset = .terminal
    static let route: GoFlyIconAsset = .route
    static let routeList: GoFlyIconAsset = .routeList
    static let manualMovement: GoFlyIconAsset = .joystick
    static let walking: GoFlyIconAsset = .speedWalk
    static let heading: GoFlyIconAsset = .nav
    static let waiting: GoFlyIconAsset = .hourglass
    static let folder: GoFlyIconAsset = .routeFolder
    static let ellipsis: GoFlyIconAsset = .more
    static let selectItems: GoFlyIconAsset = .select
    static let swap: GoFlyIconAsset = .swapHorizontal
    static let swapVertical: GoFlyIconAsset = .swapVertical
    static let recent: GoFlyIconAsset = .history
    static let expandSheet: GoFlyIconAsset = .chevronUp
    static let collapseSheet: GoFlyIconAsset = .chevronDown
    static let successFilled: GoFlyIconAsset = .success
    static let dangerFilled: GoFlyIconAsset = .alert
    static let warningFilled: GoFlyIconAsset = .alert
    static let flag: GoFlyIconAsset = .flag
    static let joystick: GoFlyIconAsset = .joystick
}

/// Bottom-bar icons are the Figma pin, route, and joystick shared assets.
struct GoFlyTabIcon: View {
    let mode: SessionMapMode
    let selected: Bool
    var size: CGFloat = 25

    private var asset: GoFlyIconAsset {
        switch mode {
        case .teleport: .pin
        case .route: .route
        case .joystick: .joystick
        }
    }

    var body: some View { GoFlyIcon(asset, size: size, maximumSize: size * 1.5) }
}

struct GoFlyRecenterIcon: View {
    var size: CGFloat = 22
    var body: some View { GoFlyIcon(.locate, size: size, maximumSize: size * 1.5) }
}

struct GoFlySpeedIcon: View {
    var size: CGFloat = 18
    var body: some View { GoFlyIcon(.speed, size: size, maximumSize: size * 1.5) }
}

struct GoFlyRoundTripIcon: View {
    let enabled: Bool
    var size: CGFloat = 18

    var body: some View {
        GoFlyIcon(enabled ? .repeat : .repeatOff, size: size, maximumSize: size * 1.5)
    }
}

struct GoFlyStarIcon: View {
    var size: CGFloat = 18
    var filled = false

    var body: some View {
        GoFlyIcon(filled ? .starFilled : .star, size: size, maximumSize: size * 1.5)
    }
}

struct GoFlyTrashIcon: View {
    var size: CGFloat = 18
    var body: some View { GoFlyIcon(.trash, size: size, maximumSize: size * 1.5) }
}

struct GoFlyRouteFolderIcon: View {
    var size: CGFloat = 20
    var body: some View { GoFlyIcon(.routeFolder, size: size, maximumSize: size * 1.5) }
}

/// Selection artwork uses Figma's `icon/select`; the empty state is a control
/// ring, not a separately drawn icon glyph.
struct GoFlyCheckboxIcon: View {
    let selected: Bool
    var size: CGFloat = 24

    var body: some View {
        Group {
            if selected {
                Circle()
                    .fill(GoFlyStyle.primary)
                    .frame(width: size, height: size)
                    .overlay {
                        GoFlyIcon(.check, size: size * 0.7, maximumSize: size * 0.8)
                            .foregroundStyle(GoFlyTextColor.inverse)
                    }
            } else {
                Circle()
                    .strokeBorder(GoFlyThemeColor.iconSecondary, lineWidth: 1.5)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

enum GoFlySettingsIconKind {
    case location, vpn, wifi, background, language, appearance, device, support

    var asset: GoFlyIconAsset {
        switch self {
        case .location: .nav
        case .vpn: .shield
        case .wifi: .wifi
        case .background: .terminal
        case .language: .globe
        case .appearance: .moon
        case .device: .phone
        case .support: .cloudDownload
        }
    }
}

/// The common settings icon badge; its glyph comes from the shared icon catalog.
struct GoFlySettingsBadgeIcon: View {
    let kind: GoFlySettingsIconKind

    var body: some View {
        GoFlyIcon(kind.asset, size: 16, maximumSize: 22)
            .foregroundStyle(GoFlyTextColor.inverse)
            .frame(width: 32, height: 32)
            .background(GoFlyStyle.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}
