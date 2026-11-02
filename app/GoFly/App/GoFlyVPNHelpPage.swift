import SwiftUI

/// Shared connection guide for onboarding and Settings.
struct GoFlyVPNHelpPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let onReturn: () -> Void
    @State private var externalOpenFailed = false
    @State private var externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"

    init(onReturn: @escaping () -> Void = {}) {
        self.onReturn = onReturn
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    instructionCard
                    troubleshootingCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .accessibilityIdentifier("vpn.help.content")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoFlyStyle.canvas)
        .goFlyPushedFullScreen()
        .navigationBarBackButtonHidden()
        .goFlyToastOverlay(topInset: 48) {
            if externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString(externalOpenFailureKey),
                                  identifier: "onboarding.vpn.help.externalOpenFailed")
            }
        }
        .onDisappear {
            guard scenePhase == .active else { return }
            onReturn()
        }
    }

    private var navigationHeader: some View {
        HStack {
            Button(action: returnToPreviousPage) {
                HStack(spacing: 5) {
                    GoFlyIcon(GoFlySymbols.back)
                        .goFlyIconSize(size: 16, maximum: 18)
                        .accessibilityHidden(true)
                    Text(goFlyString("common.back"))
                        .goFlyFont(GoFlyFont.body)
                }
                .foregroundStyle(GoFlyTextColor.accent)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 88, height: 45, alignment: .leading)
            .accessibilityLabel(goFlyString("common.back"))
            .accessibilityIdentifier("onboarding.vpn.help.back")

            Text(goFlyString("onboarding.vpn.help"))
                .goFlyFont(GoFlyFont.headline)
                .foregroundStyle(GoFlyTextColor.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityAddTraits(.isHeader)

            Color.clear.frame(width: 88, height: 44)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var instructionCard: some View {
        VStack(spacing: 0) {
            GoFlyVPNInstructionRow(number: 1, titleKey: "onboarding.vpn.help.step1.title",
                                   showsChevron: true, accessibilityID: "onboarding.vpn.help.step1",
                                   action: openStore)
            separator
            GoFlyVPNInstructionRow(number: 2, titleKey: "onboarding.vpn.help.step2.title",
                                   showsChevron: true, accessibilityID: "onboarding.vpn.help.step2",
                                   action: openLocalDevVPN)
            separator
            GoFlyVPNInstructionRow(number: 3, titleKey: "onboarding.vpn.help.step3.title",
                                   accessibilityID: "onboarding.vpn.help.step3")
        }
        .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var troubleshootingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goFlyString("onboarding.vpn.help.troubleshooting"))
                .goFlyFont(GoFlyFont.subheadlineEmphasis)
                .foregroundStyle(GoFlyTextColor.primary)
                .accessibilityAddTraits(.isHeader)
            Text(goFlyString("onboarding.vpn.help.reconnect"))
                .goFlyFont(GoFlyFont.footnote)
                .foregroundStyle(GoFlyTextColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var separator: some View {
        GoFlyThemeColor.lineSeparator
            .frame(height: 0.5)
            .padding(.leading, 54)
            .padding(.trailing, 16)
            .accessibilityHidden(true)
    }

    private func returnToPreviousPage() {
        dismiss()
    }

    private func openStore() {
        externalOpenFailed = false
        externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"
        GoFlyExternalLinks.openStore { externalOpenFailed = !$0 }
    }

    private func openLocalDevVPN() {
        externalOpenFailed = false
        externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"
        GoFlyExternalLinks.openLocalDevVPN { externalOpenFailed = !$0 }
    }
}

/// One consistent numbered step row shared by onboarding and the connection guide.
struct GoFlyVPNInstructionRow: View {
    let number: Int
    let titleKey: String
    var showsChevron = false
    var trailingText: String?
    var trailingIsWarning = false
    let accessibilityID: String
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { rowContents }
                .buttonStyle(.plain)
                .accessibilityIdentifier(accessibilityID + ".action")
        } else {
            rowContents
        }
    }

    private var rowContents: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .goFlyFont(GoFlyFont.captionEmphasis)
                .foregroundStyle(GoFlyTextColor.inverse)
                .frame(width: 24, height: 24)
                .background(GoFlyStyle.primary, in: Circle())
                .accessibilityHidden(true)
            Text(goFlyString(titleKey))
                .goFlyFont(GoFlyFont.subheadline)
                .foregroundStyle(GoFlyTextColor.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier(accessibilityID)
            if let trailingText {
                Text(trailingText)
                    .goFlyFont(GoFlyFont.subheadline)
                    .foregroundStyle(trailingIsWarning ? GoFlyTextColor.warning : GoFlyTextColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(accessibilityID + ".status")
            }
            if showsChevron {
                GoFlyIcon(GoFlySymbols.disclosure)
                    .goFlyIconSize(size: 14, maximum: 16)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}
