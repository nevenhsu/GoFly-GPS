import GoFlyCore
import SwiftUI

/// Place details: the shared `GoFlyLocationCard`; only the primary button title differs.
struct GoFlyPlaceDetailsView: View {
    let place: MapPlace
    var titleLabel: String? = nil
    var onDismiss: () -> Void
    var embedded = false
    /// Current simulated position, used only to show the Figma distance line.
    var distanceFrom: GeoCoordinate?
    var canGo = false
    var primaryTitleKey = "map.go"
    var onGo: (() -> Void)? = nil
    var onRouteStart: (() -> Void)? = nil
    var onRouteEnd: (() -> Void)? = nil

    var body: some View {
        if embedded {
            card
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        GoFlyFavoriteFailureNotice()
                        card.padding(.horizontal, 16)
                    }
                }
                .background(GoFlyStyle.cardSurface)
                .navigationTitle(goFlyString("search.placeDetails"))
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var card: some View {
        GoFlyLocationCard(
            place: place,
            titleLabel: titleLabel,
            primaryActionType: .localizedTitleKey(primaryTitleKey),
            primaryActionTitle: goFlyString(primaryTitleKey),
            primaryEnabled: canGo,
            onPrimaryAction: onGo,
            onRouteStart: onRouteStart,
            onRouteEnd: onRouteEnd,
            onDismiss: onDismiss,
            distanceFrom: distanceFrom,
            identifier: "placeDetails")
    }
}
