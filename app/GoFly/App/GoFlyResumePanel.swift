import SwiftUI

/// Compact bottom panel for route and joystick-wander recovery (D10, E5).
///
/// Features:
/// - Maximum map and location visibility (76 pt visible height).
/// - Shows interrupted state title on the left.
/// - Single primary "Resume" action button on the right (e.g., "繼續").
struct GoFlyResumePanel: View {
    let title: String
    var subtitle: String? = nil
    let ctaTitle: String
    let onResume: () -> Void
    var isEnabled: Bool = true
    /// Panel height below the grabber: 64 inside a sheet (12 pt grabber), 88 when the panel owns the bottom (D10).
    var contentHeight: CGFloat = 76
    var identifier: String = "resumePanel"

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .goFlyFont(GoFlyFont.title)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("\(identifier).title")
                if let subtitle {
                    Text(subtitle)
                        .goFlyFont(GoFlyFont.footnote)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("\(identifier).subtitle")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onResume) {
                Text(ctaTitle)
                    .goFlyFont(GoFlyFont.subheadlineEmphasis)
                    .foregroundStyle(isEnabled ? GoFlyTextColor.inverse : GoFlyTextColor.disabled)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(isEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledSurface, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityIdentifier("\(identifier).action")
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        // The hosting panel already supplies the panel background.
        .frame(height: contentHeight, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
