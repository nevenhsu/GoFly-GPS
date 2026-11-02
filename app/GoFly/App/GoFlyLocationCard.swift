import CoreLocation
import GoFlyCore
import SwiftUI
import UIKit

public enum LocationCardPrimaryAction: Equatable, Sendable {
    case confirm
    case teleport
    case localizedTitleKey(String)

    public var titleKey: String {
        switch self {
        case .confirm: return "common.confirm" // "確認"
        case .teleport: return "map.go" // “Go”
        case .localizedTitleKey(let str): return str
        }
    }
}

/// Floating location details card (D4, D2a, E5)
///
/// Features:
/// - Minimum height 188 pt, corner radius 16 pt, double-layer soft shadow.
/// - Sits above narrowest bottom panel at y = 573, 16 pt above TabBar.
/// - Primary CTA button: solid black capsule with text "確認" (D4) or "Go".
/// - Secondary buttons: Favorite star button and Copy coordinates button.
/// - Dismiss (✕) button in top right.
struct GoFlyLocationCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let place: MapPlace
    var titleLabel: String? = nil
    var primaryActionType: LocationCardPrimaryAction = .confirm
    var primaryActionTitle: String? = nil
    var primaryEnabled: Bool = true
    /// Nil hides the primary button (place details opened without a Go action).
    var onPrimaryAction: (() -> Void)?
    var onRouteStart: (() -> Void)? = nil
    var onRouteEnd: (() -> Void)? = nil
    var onDismiss: () -> Void
    var onCopy: (() -> Void)? = nil
    var distanceFrom: GeoCoordinate? = nil
    var identifier: String = "locationCard"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(GoFlyLocationTitle.resolve(label: titleLabel, for: place))
                    .goFlyFont(.title)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    // 8 pt below the 20 pt title; the smaller lines keep 4 pt between them.
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("\(identifier).title")

                Text(place.address ?? "")
                    .goFlyFont(.footnote)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier).address")

                Text(coordinateLine)
                    .goFlyFont(.caption)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .accessibilityIdentifier("\(identifier).coordinates")
            }
            .frame(maxWidth: 277, alignment: .leading)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if let onPrimaryAction {
                    Button(action: onPrimaryAction) {
                        HStack(spacing: 8) {
                            GoFlyIcon(.play).goFlyIconSize(size: 16)
                            Text(resolvedPrimaryTitle)
                                .goFlyFont(.buttonSmall)
                                .lineLimit(1)
                        }
                        // Wider card CTA for device review; the map-pin Go stays compact.
                        .padding(.horizontal, 12)
                        .frame(minWidth: 104)
                        .frame(height: 40)
                    }
                    .buttonStyle(GoFlyButtonStyle(variant: .primary, size: .inline, expandsToFill: false))
                    .goFlySteadyDisabled(!primaryEnabled)
                    .accessibilityIdentifier("\(identifier).primaryAction")
                }

                Spacer(minLength: 0)

                if onRouteStart != nil || onRouteEnd != nil {
                    Menu {
                        if let onRouteStart { Button(goFlyString("placeDetails.setStart"), action: onRouteStart) }
                        if let onRouteEnd { Button(goFlyString("placeDetails.setEnd"), action: onRouteEnd) }
                    } label: {
                        GoFlyIcon(GoFlySymbols.flag)
                            .goFlyIconSize(size: 15)
                            .goFlyIconButtonChrome(diameter: 44)
                    }
                    .accessibilityLabel(goFlyString("placeDetails.setEnd"))
                    .accessibilityIdentifier("\(identifier).route")
                }

                GoFlyFavoriteStar(place: place, identifier: "\(identifier).favorite", isCardAction: true, allowsDelete: true)
                GoFlyCopyIconButton(coordinate: place.coordinate, identifier: "\(identifier).copy", onCopy: onCopy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : 180, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                GoFlyLocationCardBackdrop(colorScheme: colorScheme)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(GoFlyStyle.locationCardSurface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                GoFlyIcon(.close)
                    .goFlyIconSize(size: 18)
                    .goFlyIconButtonChrome(diameter: 44, showsBorder: false, variant: .clear)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 16)
            .accessibilityLabel(goFlyString("common.dismiss"))
            .accessibilityIdentifier("\(identifier).dismiss")
        }
        .goFlyShadow(.card)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var resolvedPrimaryTitle: String {
        if let primaryActionTitle { return primaryActionTitle }
        switch primaryActionType {
        case .confirm: return goFlyString("common.confirm")
        case .teleport: return goFlyString("map.go")
        case .localizedTitleKey(let str): return str
        }
    }

    private var coordinateLine: String {
        guard let distance = distanceMeters else { return place.coordinate.shortDisplayText }
        let formatted: String
        if distance < 1_000 {
            formatted = goFlyLocalizedFormat(goFlyString("placeDetails.distanceMeters"), Int(distance.rounded()))
        } else {
            formatted = goFlyLocalizedFormat(goFlyString("placeDetails.distanceKilometers"),
                                             String(format: "%.1f", arguments: [distance / 1_000]))
        }
        return "\(place.coordinate.shortDisplayText) · \(formatted)"
    }

    private var distanceMeters: Double? {
        guard let distanceFrom else { return nil }
        let from = CLLocation(latitude: distanceFrom.latitude, longitude: distanceFrom.longitude)
        let to = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        let value = from.distance(from: to)
        return value.isFinite ? value : nil
    }
}

/// Resolves the shared location title for cards and the collapsed Teleport position summary.
enum GoFlyLocationTitle {
    static func resolve(label: String? = nil, for place: MapPlace) -> String {
        if let label = nonEmpty(label) { return label }

        let name = nonEmpty(place.title)
        let address = nonEmpty(place.address)
        if let name, name != address, name != place.coordinate.displayText { return name }
        if let address { return address }
        return place.coordinate.displayText
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// Icon-only copy-coordinates button shared by the location card and the collapsed position summary.
struct GoFlyCopyIconButton: View {
    let coordinate: GeoCoordinate
    var identifier: String
    var onCopy: (() -> Void)? = nil

    var body: some View {
        Button {
            UIPasteboard.general.string = coordinate.displayText
            onCopy?()
        } label: {
            GoFlyIcon(.copy)
                .goFlyIconSize(size: 22)
                .goFlyIconButtonChrome(diameter: 44, variant: .copy)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(goFlyString("placeDetails.copy"))
        .accessibilityIdentifier(identifier)
    }
}

private struct GoFlyLocationCardBackdrop: UIViewRepresentable {
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = UIBlurEffect(style: blurStyle)
    }

    private var blurStyle: UIBlurEffect.Style {
        colorScheme == .dark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight
    }
}
