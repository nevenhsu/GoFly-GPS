import SwiftUI
import UIKit

/// Names and asset paths from Figma 04 · iOS Redesign / 0 · 共用元件（Icon）.
/// The 53 `icon/*` vectors are template assets. Map and speed artwork keeps its
/// authored colors and is exposed through the same rendering entry point.
enum GoFlyIconAsset: String, CaseIterable, Identifiable {
    case alert = "icon/alert"
    case arrowRight = "icon/arrow-right"
    case batteryFull = "icon/battery-full"
    case bookmark = "icon/bookmark"
    case check = "icon/check"
    case chevronDown = "icon/chevron-down"
    case chevronLeft = "icon/chevron-left"
    case chevronRight = "icon/chevron-right"
    case chevronUp = "icon/chevron-up"
    case close = "icon/close"
    case copy = "icon/copy"
    case directionForward = "icon/direction-forward"
    case directionReverse = "icon/direction-reverse"
    case expand = "icon/expand"
    case externalLink = "icon/external-link"
    case flag = "icon/flag"
    case gear = "icon/gear"
    case globe = "icon/globe"
    case grip = "icon/grip"
    case help = "icon/help"
    case history = "icon/history"
    case hourglass = "icon/hourglass"
    case joystick = "icon/joystick"
    case locate = "icon/locate"
    case mac = "icon/mac"
    case moon = "icon/moon"
    case more = "icon/more"
    case nav = "icon/nav"
    case paste = "icon/paste"
    case pause = "icon/pause"
    case phone = "icon/phone"
    case pin = "icon/pin"
    case play = "icon/play"
    case radius = "icon/radius"
    case `repeat` = "icon/repeat"
    case repeatOff = "icon/repeat-off"
    case reset = "icon/reset"
    case route = "icon/route"
    case routeFolder = "icon/route-folder"
    case routeList = "icon/route-list"
    case search = "icon/search"
    case select = "icon/select"
    case shield = "icon/shield"
    case shuffle = "icon/shuffle"
    case signal = "icon/signal"
    case speed = "icon/speed"
    case star = "icon/star"
    case starFilled = "icon/star-filled"
    case stop = "icon/stop"
    case success = "icon/success"
    case swapHorizontal = "icon/swap-horizontal"
    case swapVertical = "icon/swap-vertical"
    case terminal = "icon/terminal"
    case trash = "icon/trash"
    case wifi = "icon/wifi"

    /// Dual-color status glyphs exported from the current Figma Toast component.
    /// Unlike the reusable monochrome icon catalog, these preserve authored
    /// Light/Dark fills and strokes through asset-catalog appearances.
    case toastDanger = "status-toast/danger"
    case toastWarning = "status-toast/warning"
    case toastSuccess = "status-toast/success"

    case mapCandidatePin = "map/candidate-pin"
    case mapNodeEnd = "map/node-end"
    case mapNodeStart = "map/node-start"
    case mapNodeWaypoint = "map/node-waypoint"
    case mapRealLocation = "map/real-location"
    case mapSimulationLight = "map/sim-light"
    case mapSimulationDark = "map/sim-dark"
    case mapSimulationWaitingLight = "map/sim-light-wait"
    case mapSimulationWaitingDark = "map/sim-dark-wait"
    case speedWalk = "speed/walk"
    case speedBicycle = "speed/bicycle"
    case speedScooter = "speed/scooter"
    case speedCar = "speed/car"

    var id: String { rawValue }
    var assetName: String { rawValue.replacingOccurrences(of: "/", with: "-") }
    var isTemplate: Bool { rawValue.hasPrefix("icon/") }
    static var figmaIconCases: [GoFlyIconAsset] { allCases.filter(\.isTemplate) }
}

struct GoFlyIconSizeOverride {
    let size: CGFloat
    let maximum: CGFloat
}

private struct GoFlyIconSizeOverrideKey: EnvironmentKey {
    static let defaultValue: GoFlyIconSizeOverride? = nil
}

extension EnvironmentValues {
    var goFlyIconSizeOverride: GoFlyIconSizeOverride? {
        get { self[GoFlyIconSizeOverrideKey.self] }
        set { self[GoFlyIconSizeOverrideKey.self] = newValue }
    }
}

extension View {
    func goFlyIconSize(size: CGFloat, maximum: CGFloat = 32) -> some View {
        environment(\.goFlyIconSizeOverride, GoFlyIconSizeOverride(size: size, maximum: maximum))
    }
}

/// The single SwiftUI/UIKit entry point for Figma icon, map, speed, and status-toast assets.
/// `@ScaledMetric` lets artwork grow with Dynamic Type while leaving layout to
/// the containing button or row, so glyphs are never clipped by a fixed slot.
struct GoFlyIcon: View {
    let asset: GoFlyIconAsset
    private let requestedSize: CGFloat
    private let maximumSize: CGFloat
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 20
    @Environment(\.goFlyIconSizeOverride) private var sizeOverride

    init(_ asset: GoFlyIconAsset, size: CGFloat = 20, maximumSize: CGFloat? = nil) {
        self.asset = asset
        requestedSize = size
        self.maximumSize = maximumSize ?? max(size, 32)
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    private var displayedSize: CGFloat {
        guard let sizeOverride else { return min(scaledSize, maximumSize) }
        let scale = scaledSize / requestedSize
        return min(sizeOverride.size * scale, sizeOverride.maximum)
    }

    var body: some View {
        Image(asset.assetName)
            .resizable()
            .renderingMode(asset.isTemplate ? .template : .original)
            .aspectRatio(contentMode: .fit)
            .frame(width: displayedSize, height: displayedSize)
            .accessibilityHidden(true)
    }

    static func uiImage(_ asset: GoFlyIconAsset) -> UIImage? {
        UIImage(named: asset.assetName)?.withRenderingMode(asset.isTemplate ? .alwaysTemplate : .alwaysOriginal)
    }
}

/// Consistent inline icon-and-title content for shared buttons and list rows.
struct GoFlyIconLabel: View {
    let title: String
    let icon: GoFlyIconAsset?
    var iconSize: CGFloat = 18
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: icon == nil ? 0 : spacing) {
            if let icon {
                GoFlyIcon(icon, size: iconSize)
            }
            Text(title)
        }
        .contentShape(Rectangle())
    }
}

/// Figma map artwork is multi-color and intentionally bypasses template tinting.
struct GoFlyMapAssetView: View {
    let asset: GoFlyIconAsset
    var size: CGFloat = 24

    var body: some View {
        GoFlyIcon(asset, size: size, maximumSize: size * 1.5)
    }
}
