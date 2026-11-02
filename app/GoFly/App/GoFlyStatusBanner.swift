import SwiftUI
import GoFlyCore

/// Tracks native presentation state so the app can add the part of the Figma
/// dim layer that SwiftUI's system sheet/dialog scrim does not provide.
@MainActor
final class GoFlySystemPresentationDimState: ObservableObject {
    @Published private var presentedIDs: Set<String> = []

    var isPresented: Bool { !presentedIDs.isEmpty }

    func setPresented(_ presented: Bool, id: String) {
        guard presentedIDs.contains(id) != presented else { return }
        if presented {
            presentedIDs.insert(id)
        } else {
            presentedIDs.remove(id)
        }
    }
}

private struct GoFlySystemPresentationTracker: ViewModifier {
    @EnvironmentObject private var state: GoFlySystemPresentationDimState
    let isPresented: Bool
    let id: String

    func body(content: Content) -> some View {
        content.onChange(of: isPresented, initial: true) { _, presented in
            state.setPresented(presented, id: id)
        }
    }
}

extension View {
    func goFlyTracksSystemPresentation(_ isPresented: Bool, id: String) -> some View {
        modifier(GoFlySystemPresentationTracker(isPresented: isPresented, id: id))
    }
}

/// The single status presentation for the redesign (plan 4.11), Figma
/// `Toast / 系統訊息 / danger｜warn｜success`.
///
/// Severity is conveyed by icon + text + color. The toast sits at the top of a
/// sheet or the map, shows at most one primary action, and carries a close
/// button only when the caller allows dismissal (or it floats over the map).
/// Repair guidance belongs in `message`, not in a separate block lower on the
/// screen. Height follows the content so large text sizes wrap instead of clip.
struct GoFlyStatusBanner: View {
    let tone: GoFlyStatusTone
    let title: String
    var message: String?
    var actionTitle: String?
    var onAction: (() -> Void)?
    var onDismiss: (() -> Void)?
    var identifier: String?
    var actionEnabled = true
    var actionInProgress = false
    var actionProgressAccessibilityLabel: String? = nil
    var actionIdentifier: String? = nil
    var titleIdentifier: String? = nil
    var messageIdentifier: String? = nil
    var isFloating = true
    @State private var isDismissedLocally = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private static let horizontalInset: CGFloat = 14
    /// Moves the dismiss icon this far from the toast's trailing edge without shrinking its hit area.
    private static let dismissIconTrailingNudge: CGFloat = 2

    var body: some View {
        if !isDismissedLocally {
            Group {
                if !showsActionButton {
                    inlineLayout(singleLineTitle: false)
                } else if dynamicTypeSize.isAccessibilitySize {
                    stackedLayout
                } else {
                    // Inline when the title fits on one line beside the action, otherwise
                    // the action drops below the text (the accessibility-size layout).
                    ViewThatFits(in: .horizontal) {
                        inlineLayout(singleLineTitle: true)
                        stackedLayout
                    }
                }
            }
            // The dismiss button's 28 pt hit area runs to the trailing edge, so it replaces the inset.
            .padding(.leading, Self.horizontalInset)
            .padding(.trailing, showsDismissButton ? 0 : Self.horizontalInset)
            .padding(.vertical, 12)
            // The Figma 12 pt inset includes a 1 pt outline allowance in the
            // rendered 85 pt frame; keep that allowance outside the content.
            .padding(.vertical, 1)
            .background(tone.toastSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tone.toastBorder, lineWidth: 1)
            }
            .goFlyShadow(isFloating ? .toast : nil)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier ?? "statusBanner")
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                statusIcon
                textContent(singleLineTitle: false)
                if showsDismissButton { dismissButton }
            }
            if showsActionButton {
                actionButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, showsDismissButton ? Self.horizontalInset : 0)
            }
        }
    }

    private func inlineLayout(singleLineTitle: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            statusIcon
            textContent(singleLineTitle: singleLineTitle)
            // 4 pt between the action and the dismiss icon; the 8 pt gaps stay around them.
            HStack(alignment: .center, spacing: 4) {
                if showsActionButton { actionButton }
                if showsDismissButton { dismissButton }
            }
        }
    }

    private var statusIcon: some View {
        GoFlyIcon(tone.toastSymbol, size: 22, maximumSize: 28)
            .frame(minWidth: 22, minHeight: 22)
            .accessibilityHidden(true)
    }

    /// `singleLineTitle` is only used to measure the inline layout for `ViewThatFits`: the
    /// title must fit on one line, while the message may wrap (its ideal width is zero).
    private func textContent(singleLineTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .goFlyFont(GoFlyFont.subheadlineEmphasis)
                .foregroundStyle(GoFlyTextColor.primary)
                .frame(minHeight: 21, alignment: .leading)
                .lineLimit(singleLineTitle ? 1 : nil)
                .fixedSize(horizontal: singleLineTitle, vertical: true)
                .accessibilityLabel("\(goFlyString(tone.accessibilityKey)), \(title)")
                .accessibilityIdentifier(titleIdentifier
                    ?? identifier.map { "\($0).title" } ?? "statusBanner.title")
            if let message {
                Text(message)
                    .goFlyFont(GoFlyFont.footnote)
                    .foregroundStyle(colorScheme == .dark ? GoFlyTextColor.primary : GoFlyTextColor.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 0, idealWidth: singleLineTitle ? 0 : nil, maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(messageIdentifier
                        ?? identifier.map { "\($0).message" } ?? "statusBanner.message")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsActionButton: Bool { actionTitle != nil && onAction != nil }
    private var showsDismissButton: Bool { onDismiss != nil || isFloating }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let onAction {
            Button(action: onAction) {
                HStack(spacing: 5) {
                    if actionInProgress {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                    }
                    Text(actionTitle)
                }
            }
            .buttonStyle(GoFlyStatusActionStyle(tone: tone))
            .disabled(!actionEnabled)
            .accessibilityLabel(actionInProgress
                ? (actionProgressAccessibilityLabel ?? actionTitle)
                : actionTitle)
            .accessibilityIdentifier(actionIdentifier
                ?? identifier.map { "\($0).action" } ?? "statusBanner.action")
        }
    }

    private var dismissButton: some View {
        Button(action: {
            if let onDismiss {
                onDismiss()
            } else {
                isDismissedLocally = true
            }
        }) {
            // The 28 pt hit area ends exactly at the toast's trailing edge (the toast has no
            // trailing inset while this button shows), so every tappable point is inside the
            // toast; the 20 pt icon box is centred in it.
            GoFlyIcon(GoFlySymbols.close)
                .goFlyIconSize(size: 13, maximum: 16)
                .foregroundStyle(colorScheme == .dark ? GoFlyTextColor.primary : tone.toastDismiss)
                .frame(width: 20, height: 20)
                .offset(x: -Self.dismissIconTrailingNudge)
                .frame(width: 28, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(goFlyString("common.dismiss"))
        .accessibilityIdentifier(identifier.map { "\($0).dismiss" } ?? "statusBanner.dismiss")
    }
}

/// Shared top overlay container for independently dismissible floating notices.
/// The overlay does not participate in the page's layout, so it never pushes content down.
struct GoFlyToastOverlay<Content: View>: View {
    let topInset: CGFloat
    @ViewBuilder let content: () -> Content

    init(topInset: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.topInset = topInset
        self.content = content
    }

    var body: some View {
        VStack(spacing: 8) { content() }
            .padding(.horizontal, 16)
            .padding(.top, topInset)
            .frame(maxWidth: .infinity, alignment: .top)
            .accessibilityElement(children: .contain)
    }
}

extension View {
    func goFlyToastOverlay<Toast: View>(topInset: CGFloat = 8,
                                        @ViewBuilder content: @escaping () -> Toast) -> some View {
        overlay(alignment: .top) {
            GoFlyToastOverlay(topInset: topInset, content: content)
                .zIndex(50)
        }
    }

    func goFlyBottomToastOverlay<Toast: View>(bottomInset: CGFloat = 40,
                                              @ViewBuilder content: @escaping () -> Toast) -> some View {
        overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .accessibilityElement(children: .contain)
            .zIndex(50)
        }
    }
}

/// Every toast is a short title plus the key's own copy as its second line;
/// the title comes from `IssueCatalog.titleKey(for:)`.
@MainActor
func goFlyIssueTitle(for key: String) -> String { goFlyString(IssueCatalog.titleKey(for: key)) }

/// Maps an error key to its one toast button (see `IssueCatalog`). The caller
/// passes only the handlers it owns; an action without a handler shows no button.
@MainActor
func goFlyIssueButton(for key: String, retry: (() -> Void)? = nil, fix: (() -> Void)? = nil,
                      settings: (() -> Void)? = nil,
                      chooseFile: (() -> Void)? = nil) -> (title: String?, action: (() -> Void)?) {
    guard let issue = IssueCatalog.info(for: key).action else { return (nil, nil) }
    let handler: (() -> Void)?
    switch issue {
    case .retry: handler = retry
    case .fix: handler = fix
    case .settings: handler = settings
    case .chooseFile: handler = chooseFile
    }
    guard let handler else { return (nil, nil) }
    return (goFlyString(issue.localizationKey), handler)
}
