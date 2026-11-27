import SwiftUI
import UIKit

/// A one-off result. Plain messages disappear after about two seconds; one with
/// an action (undo) stays about five. Anything that blocks the person belongs in
/// `GoFlyStatusBanner`. `bottomPadding` places it above the sheet or button.
struct GoFlySnackbarMessage: Identifiable {
    let id = UUID()
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    /// Figma `Snackbar / 2 秒自動消失` vs `Snackbar / 可復原` (about 5 seconds).
    var defaultDuration: Duration { action == nil ? .seconds(2) : .seconds(5) }
}

struct GoFlySnackbar: View {
    let message: GoFlySnackbarMessage
    var onDismiss: () -> Void = {}
    var body: some View {
        HStack(spacing: 8) {
            GoFlyIcon(.toastSuccess, size: 24)
                .goFlyIconSize(size: 24)
                .accessibilityHidden(true)
            Text(message.text)
                .goFlyFont(GoFlyFont.subheadline)
                .foregroundStyle(GoFlyTextColor.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle = message.actionTitle, let action = message.action {
                Button {
                    action()
                    onDismiss()
                } label: {
                    Text(actionTitle)
                }
                .buttonStyle(GoFlyStatusActionStyle(tone: .success))
                .accessibilityIdentifier("snackbar.action")
            }
            Button(action: onDismiss) {
                GoFlyIcon(GoFlySymbols.close)
                    .goFlyIconSize(size: 14, maximum: 16)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goFlyString("common.dismiss"))
            .accessibilityIdentifier("snackbar.dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .background(GoFlyStyle.cardSurface,
                    in: RoundedRectangle(cornerRadius: GoFlyStyle.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.Radius.control, style: .continuous)
                .strokeBorder(GoFlyStyle.border, lineWidth: 1)
        }
        .goFlyShadow(.floating)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("snackbar")
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: message.text)
        }
    }
}

private struct GoFlySnackbarModifier: ViewModifier {
    @Binding var message: GoFlySnackbarMessage?
    let bottomPadding: CGFloat
    let duration: Duration?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldReduceMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return reduceMotion || GoFlyUITestOverrides.contains("-gofly-ui-reduce-motion")
        #else
        return reduceMotion
        #endif
    }

    private var animation: Animation? { shouldReduceMotion ? nil : .easeOut(duration: 0.2) }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    GoFlySnackbar(message: message) { self.message = nil }
                        .padding(.horizontal, 16)
                        .padding(.bottom, bottomPadding)
                        .transition(shouldReduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .task(id: message.id) {
                            try? await Task.sleep(for: duration ?? message.defaultDuration)
                            guard !Task.isCancelled else { return }
                            withAnimation(animation) { self.message = nil }
                        }
                }
            }
            .animation(animation, value: message?.id)
    }
}

extension View {
    func goFlySnackbar(_ message: Binding<GoFlySnackbarMessage?>,
                       bottomPadding: CGFloat = 12,
                       duration: Duration? = nil) -> some View {
        modifier(GoFlySnackbarModifier(message: message, bottomPadding: bottomPadding, duration: duration))
    }
}
