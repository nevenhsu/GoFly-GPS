import SwiftUI

/// The teleport pin, also used for a wander replacement picked on the map.
/// A committed wander destination is the route's ring node instead.
struct GoFlyPlacePinIcon: View {
    var body: some View {
        ZStack(alignment: .top) {
            Capsule().fill(GoFlyStyle.surface)
                .frame(width: 5, height: 24).padding(.top, 18)
            Capsule().fill(GoFlyStyle.primary)
                .frame(width: 2, height: 23).padding(.top, 18)
            Circle().fill(GoFlyStyle.primary)
                .frame(width: 24, height: 24)
                .overlay { Circle().fill(GoFlyThemeColor.commonWhite).frame(width: 8, height: 8) }
                .shadow(color: GoFlyThemeColor.commonBlack.opacity(0.16), radius: 2, y: 2)
        }
        .frame(width: 30, height: 44, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
