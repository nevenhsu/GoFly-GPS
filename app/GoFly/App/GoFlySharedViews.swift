import SwiftUI
import UIKit

/// Opaque content keeps labels readable over every map style and in Reduce Transparency.
/// Only map overlays receive elevation; ordinary content cards remain flat.
private struct GoFlyCard: ViewModifier {
    var floating: Bool
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .goFlyShadow(floating ? .floating : nil)
    }
}

extension View {
    func goFlyCard(floating: Bool = false, radius: CGFloat = GoFlyStyle.cornerRadius) -> some View {
        modifier(GoFlyCard(floating: floating, radius: radius))
    }

    /// Standard top hairline separator for bottom bars and action footers.
    func goFlyTopHairline(height: CGFloat = 0.5) -> some View {
        overlay(alignment: .top) { GoFlyStyle.separator.frame(height: height) }
    }
}

/// Figma 04 drop shadows. `floating`: search bar, status pill, map controls, panels,
/// snackbar and instruction card. `card`: location cards. `chip`: speed chip and small icon buttons.
enum GoFlyShadow {
    case floating, toast, card, chip
}

extension View {
    @ViewBuilder
    func goFlyShadow(_ shadow: GoFlyShadow?) -> some View {
        switch shadow {
        case .floating:
            // SwiftUI radius is half the Figma blur.
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.06), radius: 1.5, x: 0, y: 1)
                .shadow(color: GoFlyThemeColor.commonBlack.opacity(0.09), radius: 12, x: 0, y: 5)
        case .toast:
            // Figma toast shadow: black 18%, y=4, blur=16 (SwiftUI radius is half the blur).
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.18), radius: 8, x: 0, y: 4)
        case .card:
            // LocationCard: Figma black 12%, y=6, blur=20 (SwiftUI radius is half the blur).
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.12), radius: 10, x: 0, y: 6)
        case .chip:
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.06), radius: 2, x: 0, y: 1)
        case nil:
            self
        }
    }
}

enum GoFlyTextFieldState: Hashable {
    case `default`, focused, disabled

    var identifier: String {
        switch self {
        case .default: "default"
        case .focused: "focused"
        case .disabled: "disabled"
        }
    }
}

private struct GoFlyTextFieldBackground: ViewModifier {
    let state: GoFlyTextFieldState

    private var appearance: (background: Color, border: Color, borderWidth: CGFloat) {
        switch state {
        case .default:
            (GoFlyStyle.fieldSurface, GoFlyStyle.fieldBorder, 0.75)
        case .focused:
            (GoFlyStyle.fieldSurface, GoFlyStyle.fieldFocus, 1.5)
        case .disabled:
            (GoFlyStyle.disabledSurface, GoFlyThemeColor.lineInputDisabled, 0.75)
        }
    }

    func body(content: Content) -> some View {
        content
            .background(appearance.background, in: RoundedRectangle(cornerRadius: GoFlyStyle.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GoFlyStyle.Radius.control, style: .continuous)
                    .strokeBorder(appearance.border, lineWidth: appearance.borderWidth)
            }
            .foregroundStyle(state == .disabled ? GoFlyTextColor.disabled : GoFlyTextColor.primary)
    }
}

extension View {
    /// `Text Field / Neutral` Figma variants share one implementation.
    func goFlyTextField(state: GoFlyTextFieldState) -> some View {
        modifier(GoFlyTextFieldBackground(state: state))
    }

    func goFlySearchField(isFocused: Bool) -> some View {
        goFlyTextField(state: isFocused ? .focused : .default)
    }
}

/// Figma progress treatment: a 6 pt capsule with semantic track and primary-fill tokens.
struct GoFlyProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)
        Capsule()
            .fill(GoFlyStyle.secondarySurface)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(GoFlyStyle.primary)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .accessibilityElement()
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

/// Shared token-driven row shell for Figma's searchable and file lists.
/// Content remains customizable while row height and separator rendering stay consistent.
struct GoFlyListRow<Content: View>: View {
    let minimumHeight: CGFloat
    let separatorLeadingInset: CGFloat?
    let separatorTrailingInset: CGFloat
    @ViewBuilder let content: Content

    init(minimumHeight: CGFloat = 64, separatorLeadingInset: CGFloat? = nil,
         separatorTrailingInset: CGFloat = 0,
         @ViewBuilder content: () -> Content) {
        self.minimumHeight = minimumHeight
        self.separatorLeadingInset = separatorLeadingInset
        self.separatorTrailingInset = separatorTrailingInset
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .overlay(alignment: .bottom) {
                if let separatorLeadingInset {
                    Rectangle()
                        .fill(GoFlyStyle.separator)
                        .frame(height: 0.5)
                        .padding(.leading, separatorLeadingInset)
                        .padding(.trailing, separatorTrailingInset)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct GoFlyEmptyState: View {
    var symbol: GoFlyIconAsset?
    var message: String

    var body: some View {
        VStack(spacing: 16) {
            if let symbol {
                GoFlyIcon(symbol, size: 34, maximumSize: 44)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .frame(width: 80, height: 80)
                    .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 24))
            }
            Text(message)
                .goFlyFont(GoFlyFont.body)
                .foregroundStyle(GoFlyTextColor.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
}

/// Every sheet grabber: capsule 8 pt from the top, content starts 20 pt below it.
enum GoFlyGrabber {
    static let topInset: CGFloat = 8
    static let capsuleHeight: CGFloat = 5
    static let contentGap: CGFloat = 20
    static let rowHeight: CGFloat = topInset + capsuleHeight + contentGap
}

/// Each hold heartbeat marks native work busy for a moment, which briefly
/// revokes admission. Show a disabled state only once it has lasted `delay`,
/// so controls do not flicker; the action itself still checks admission.
/// Kept on purpose (2026-11-01): leaving heartbeats out of `nativeBusy` would
/// let commands queue behind a heartbeat that can take up to the 20 s write
/// budget, and would change FIFO admission for Start, teleport and Restore.
private struct GoFlySteadyDisabled: ViewModifier {
    let disabled: Bool
    let delay: Duration
    @State private var shownDisabled: Bool

    init(disabled: Bool, delay: Duration) {
        self.disabled = disabled
        self.delay = delay
        _shownDisabled = State(initialValue: disabled)
    }

    func body(content: Content) -> some View {
        content
            .disabled(shownDisabled)
            .task(id: disabled) {
                if disabled, !shownDisabled {
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                }
                shownDisabled = disabled
            }
    }
}

extension View {
    func goFlySteadyDisabled(_ disabled: Bool, delay: Duration = GoFlyStyle.admissionBlipDelay) -> some View {
        modifier(GoFlySteadyDisabled(disabled: disabled, delay: delay))
    }

    /// A tap outside a text field ends editing; buttons under the tap still fire.
    func goFlyDismissesKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }

    /// A · 啟動與首次引導 and the DDI modal: the bottom action's lower edge sits
    /// 40 pt above the screen edge. Apply inside a bottom `safeAreaInset` (or a
    /// sheet), where the home-indicator inset already counts toward the 40 pt.
    func goFlyBottomActionPadding() -> some View {
        modifier(GoFlyBottomActionPadding())
    }
}

private struct GoFlyBottomActionPadding: ViewModifier {
    static let screenEdgeGap: CGFloat = 40

    func body(content: Content) -> some View {
        content.padding(.bottom, max(0, Self.screenEdgeGap - Self.bottomSafeArea))
    }

    @MainActor private static var bottomSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }
}
