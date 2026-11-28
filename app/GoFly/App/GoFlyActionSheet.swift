import SwiftUI

/// Leading icon for a `GoFlyActionSheet` row.
enum GoFlyActionSheetIcon {
    case asset(GoFlyIconAsset)
    /// Outline play glyph matching the stroke weight of the other action rows
    /// (`icon/play` in the asset catalog is solid-filled for primary buttons).
    case playOutline
}

/// One row of a `GoFlyActionSheet`.
struct GoFlyActionSheetItem: Identifiable {
    let title: String
    let icon: GoFlyActionSheetIcon?
    let identifier: String
    var enabled = true
    var isDestructive = false
    let perform: () -> Void
    var id: String { identifier }

    init(
        title: String,
        icon: GoFlyActionSheetIcon? = nil,
        identifier: String,
        enabled: Bool = true,
        isDestructive: Bool = false,
        perform: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.identifier = identifier
        self.enabled = enabled
        self.isDestructive = isDestructive
        self.perform = perform
    }
}

/// Figma `ActionSheet` (D12 路線動作, E6 漫步中搜尋地點): a dimmed backdrop, a
/// 16 pt floating card with a left-aligned header, hairline dividers, 52 pt rows
/// with leading 20 pt icons, and a matching 16 pt / 52 pt Cancel card below.
/// The system `confirmationDialog` renders differently, so GoFly draws its own.
struct GoFlyActionSheet: View {
    var isPresented: Bool = true
    let title: String
    var detail: String? = nil
    let items: [GoFlyActionSheetItem]
    var cancelIdentifier: String
    var identifier: String
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cornerRadius: CGFloat = GoFlyStyle.Radius.card

    private var shouldReduceMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return reduceMotion || GoFlyUITestOverrides.contains("-gofly-ui-reduce-motion")
        #else
        return reduceMotion
        #endif
    }

    private var backdropAnimation: Animation? {
        shouldReduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private var sheetAnimation: Animation? {
        guard !shouldReduceMotion else { return nil }
        return isPresented
            ? .spring(response: 0.34, dampingFraction: 0.88)
            : .spring(response: 0.26, dampingFraction: 0.95)
    }

    private var cardTransition: AnyTransition {
        shouldReduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var borderColor: Color {
        GoFlyThemeColor.lineSeparator.opacity(colorScheme == .dark ? 0.85 : 0.6)
    }

    private var shadowColor: Color {
        GoFlyThemeColor.commonBlack.opacity(colorScheme == .dark ? 0.42 : 0.14)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                if isPresented {
                    GoFlyThemeColor.commonBlack.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture(perform: onCancel)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .animation(backdropAnimation, value: isPresented)

            ZStack(alignment: .bottom) {
                if isPresented {
                    cardStack
                        .transition(cardTransition)
                }
            }
            .animation(sheetAnimation, value: isPresented)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(isPresented)
        .zIndex(60)
    }

    private var cardStack: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                header

                headerDivider

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { rowSeparator(hasIcon: item.icon != nil) }
                    row(item)
                }
            }
            .background(GoFlyThemeColor.surfaceControlFloating)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: shadowColor, radius: 12, x: 0, y: 8)

            cancelButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .goFlyFont(detail == nil ? .footnoteEmphasis : .subheadlineEmphasis)
                .foregroundStyle(detail == nil ? GoFlyTextColor.secondary : GoFlyTextColor.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .goFlyFont(.footnote)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, detail == nil ? 13 : 14)
        .padding(.bottom, 12)
        .padding(.horizontal, 20)
        .accessibilityAddTraits(.isHeader)
    }

    private var headerDivider: some View {
        Rectangle()
            .fill(GoFlyThemeColor.lineSeparator)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }

    private func row(_ item: GoFlyActionSheetItem) -> some View {
        let textForeground = item.isDestructive ? GoFlyTextColor.danger : GoFlyTextColor.primary
        let iconForeground = item.isDestructive ? GoFlyThemeColor.iconDanger : GoFlyThemeColor.iconSecondary
        return Button(action: item.perform) {
            HStack(spacing: 14) {
                if let icon = item.icon {
                    actionIcon(icon)
                        .foregroundStyle(item.enabled ? iconForeground : GoFlyThemeColor.iconDisabled)
                }
                Text(item.title)
                    .goFlyFont(.body)
                    .foregroundStyle(item.enabled ? textForeground : GoFlyTextColor.disabled)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(GoFlyActionSheetButtonStyle(reduceMotion: shouldReduceMotion))
        .disabled(!item.enabled)
        .accessibilityIdentifier(item.identifier)
    }

    @ViewBuilder
    private func actionIcon(_ icon: GoFlyActionSheetIcon) -> some View {
        switch icon {
        case .asset(let asset):
            GoFlyIcon(asset, size: 20)
        case .playOutline:
            GoFlyActionSheetPlayOutlineIcon()
        }
    }

    private func rowSeparator(hasIcon: Bool) -> some View {
        Rectangle()
            .fill(GoFlyThemeColor.lineSeparator)
            .frame(height: 0.5)
            .padding(.leading, hasIcon ? 54 : 20)
            .padding(.trailing, 20)
            .accessibilityHidden(true)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text(goFlyString("common.cancel"))
                .goFlyFont(.bodyEmphasis)
                .foregroundStyle(GoFlyTextColor.primary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(GoFlyActionSheetButtonStyle(reduceMotion: shouldReduceMotion))
        .background(GoFlyThemeColor.surfaceControlFloating)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: shadowColor, radius: 12, x: 0, y: 8)
        .accessibilityIdentifier(cancelIdentifier)
    }
}

private struct GoFlyActionSheetButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let pressedFill = GoFlyThemeColor.commonBlack.opacity(colorScheme == .dark ? 0.18 : 0.06)
        configuration.label
            .background(configuration.isPressed ? pressedFill : Color.clear)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func goFlyActionSheet(
        isPresented: Bool,
        title: String,
        detail: String? = nil,
        items: [GoFlyActionSheetItem],
        cancelIdentifier: String,
        identifier: String,
        onCancel: @escaping () -> Void
    ) -> some View {
        overlay(alignment: .bottom) {
            GoFlyActionSheet(
                isPresented: isPresented,
                title: title,
                detail: detail,
                items: items,
                cancelIdentifier: cancelIdentifier,
                identifier: identifier,
                onCancel: onCancel
            )
        }
    }
}

/// 20 pt outline play glyph matching Figma `icon/play-outline` (1.65 pt stroke).
private struct GoFlyActionSheetPlayOutlineIcon: View {
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 20

    var body: some View {
        let size = min(scaledSize, 32)
        PlayOutlineShape()
            .stroke(style: StrokeStyle(lineWidth: 1.65 * (size / 20), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct PlayOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 20
        let sy = rect.height / 20
        var path = Path()
        path.move(to: CGPoint(x: 6 * sx, y: 4.2 * sy))
        path.addLine(to: CGPoint(x: 16.2 * sx, y: 10 * sy))
        path.addLine(to: CGPoint(x: 6 * sx, y: 15.8 * sy))
        path.closeSubpath()
        return path
    }
}

/// Small print under every file-import button: a LiveContainer install needs its
/// "Fix File Picker" option, or the system picker cannot hand files to GoFly.
struct GoFlyLiveContainerPickerHint: View {
    var body: some View {
        Text(goFlyString("import.liveContainerHint"))
            .goFlyFont(GoFlyFont.footnote)
            .foregroundStyle(GoFlyTextColor.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("import.liveContainerHint")
    }
}
