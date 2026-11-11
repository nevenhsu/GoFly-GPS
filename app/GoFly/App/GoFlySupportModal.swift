import GoFlyCore
import SwiftUI

/// Figma `Light · Modal / 裝置支援（DDI）` (DDI.1–3, DDI.5–6): one fixed-height
/// sheet shared by onboarding (R04) and the map. Two steps, download then
/// activate. The progress bar and a two-line error slot are always laid out,
/// so the height never jumps between states. Onboarding cannot be dismissed or
/// skipped; the map shows a close button in every state.
struct GoFlySupportModal: View {
    /// `macSetup` (DDI.4): a Mac-installed build's onboarding shows the modal
    /// already ready, since the Mac App installed support; nothing downloads.
    enum Context { case onboarding, map, macSetup }

    static let height: CGFloat = 451

    let context: Context
    @ObservedObject var preparation: GoFlySupportPreparation
    let onRetry: () -> Void
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            GoFlySupportHero()
            Text(goFlyString(titleKey))
                .goFlyFont(GoFlyFont.wheel)
                .fontWeight(.semibold)
                .foregroundStyle(GoFlyTextColor.primary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("support.modal.title")
            Text(goFlyString(messageKey))
                .goFlyFont(GoFlyFont.subheadline)
                .foregroundStyle(GoFlyTextColor.secondary)
                .multilineTextAlignment(.center)
                // Always reserves two lines so every context and state keeps
                // the same layout inside the fixed-height sheet.
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            GoFlySupportProgressSection(preparation: preparation, errorIdentifier: "support.modal.error",
                                        phaseOverride: context == .macSetup ? .ready : nil)
                .padding(.top, 24)
            Spacer(minLength: 24)
            Button(action: onRetry) {
                HStack(spacing: 8) {
                    if phase.isWorking { ProgressView() }
                    Text(goFlyString(context == .macSetup ? "onboarding.next" : phase.actionKey))
                }
            }
            .buttonStyle(GoFlyButtonStyle(variant: .primary))
            .disabled(phase.isWorking)
            .accessibilityIdentifier("support.modal.action")
        }
        .padding(.top, 32)
        .padding(.horizontal, 16)
        .goFlyBottomActionPadding()
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            if context == .map, let onClose {
                Button(action: onClose) {
                    GoFlyIcon(.close)
                        .goFlyIconSize(size: 18)
                        .goFlyIconButtonChrome(diameter: 44, showsBorder: false, variant: .clear)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 16)
                .accessibilityLabel(goFlyString("common.dismiss"))
                .accessibilityIdentifier("support.modal.close")
            }
        }
        .presentationDetents([.height(Self.height)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(GoFlyStyle.sheetCornerRadius)
        .presentationBackground(GoFlyStyle.cardSurface)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("support.modal")
    }

    // MARK: State mapping

    private var phase: GoFlySupportPreparation.Phase { context == .macSetup ? .ready : preparation.phase }

    private var messageKey: String {
        switch context {
        case .onboarding: "support.modal.message.onboarding"
        case .map: "support.modal.message.map"
        case .macSetup: "support.modal.message.macSetup"
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private var titleKey: String {
        switch (context, isFailed) {
        case (.onboarding, false): "support.modal.title.onboarding"
        case (.onboarding, true): "support.modal.title.onboardingFailed"
        case (.map, false): "support.modal.title.map"
        case (.map, true): "support.modal.title.mapFailed"
        case (.macSetup, _): "support.modal.title.macSetup"
        }
    }
}

extension GoFlySupportPreparation.Phase {
    /// Download or activation is running (idle counts: a run is about to start).
    var isWorking: Bool {
        switch self {
        case .downloading, .activating, .idle: true
        case .failed, .ready: false
        }
    }

    /// The modal's primary button title for this phase.
    var actionKey: String {
        switch self {
        case .idle, .downloading: "support.modal.downloading"
        case .activating, .ready: "support.modal.activating"
        case .failed: "common.retry"
        }
    }
}

/// The DDI modal's 72 pt cloud hero, also used by the settings F11 card.
struct GoFlySupportHero: View {
    var body: some View {
        GoFlyIcon(.cloudDownload, size: 36)
            .goFlyIconSize(size: 36, maximum: 36)
            .foregroundStyle(GoFlyTextColor.iconAccent)
            .frame(width: 72, height: 72)
            .background(GoFlyStyle.canvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The DDI step card (download, then activate) and its fixed two-line error
/// slot. Shared by the modal (DDI.1–6) and the settings F11 card (F11.a/F11.b).
struct GoFlySupportProgressSection: View {
    @ObservedObject var preparation: GoFlySupportPreparation
    var errorIdentifier: String
    /// DDI.4 shows a fixed ready state without reading the live run.
    var phaseOverride: GoFlySupportPreparation.Phase? = nil

    var body: some View {
        VStack(spacing: 0) {
            steps
            Text(errorText)
                .goFlyFont(GoFlyFont.footnote)
                .foregroundStyle(GoFlyTextColor.danger)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .top)
                .padding(.top, 12)
                .accessibilityHidden(errorText.isEmpty)
                .accessibilityIdentifier(errorIdentifier)
        }
    }

    private var steps: some View {
        VStack(spacing: 0) {
            // Activation follows the download within a moment, so one row
            // covers both: its trailing text reads 「啟用中…」 while mounting.
            GoFlySupportStepRow(state: downloadState, titleKey: "support.step.download",
                                trailing: downloadTrailing, progress: downloadProgress,
                                identifier: "support.step.download")
        }
        .background(GoFlyStyle.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var phase: GoFlySupportPreparation.Phase { phaseOverride ?? preparation.phase }

    private var errorText: String {
        if case .failed(_, let key) = phase { return goFlyString(key) }
        return ""
    }

    private var downloadState: GoFlySupportStepRow.State {
        switch phase {
        case .idle, .downloading, .activating: .active
        case .ready: .done
        case .failed: .failed
        }
    }

    /// The bar is always present: blue while downloading or activating, full
    /// green when ready, red where a failed run stopped.
    private var downloadProgress: GoFlySupportStepRow.Progress {
        switch phase {
        case .idle: .init(fraction: 0, tone: .active)
        case .downloading(let received, let total):
            .init(fraction: total.map { $0 > 0 ? Double(received) / Double($0) : 0 } ?? 0, tone: .active)
        case .activating: .init(fraction: 1, tone: .active)
        case .ready: .init(fraction: 1, tone: .done)
        case .failed(.activate, _): .init(fraction: 1, tone: .failed)
        case .failed(.download, _): .init(fraction: preparation.downloadFraction, tone: .failed)
        }
    }

    private var downloadTrailing: (String, GoFlySupportStepRow.TrailingTone) {
        switch phase {
        case .idle: (goFlyString("support.step.waiting"), .disabled)
        case .downloading(let received, let total):
            if let total { (Self.megabytes(received, of: total), .secondary) }
            else { (goFlyString("support.step.downloading"), .secondary) }
        case .activating: (goFlyString("support.step.activating"), .secondary)
        case .ready: (goFlyString("support.step.done"), .success)
        case .failed: (goFlyString("support.step.failed"), .danger)
        }
    }

    private static func megabytes(_ received: Int64, of total: Int64) -> String {
        let mb = { (value: Int64) in Double(value) / 1_048_576 }
        return String(format: "%.1f / %.0f MB", mb(received), max(1, mb(total).rounded()))
    }
}

/// One row of the DDI modal's step card: state glyph, title, trailing status,
/// and an optional progress bar under the title.
struct GoFlySupportStepRow: View {
    enum State { case pending, active, done, failed }
    enum TrailingTone {
        case secondary, disabled, success, danger

        var color: Color {
            switch self {
            case .secondary: GoFlyTextColor.secondary
            case .disabled: GoFlyTextColor.disabled
            case .success: GoFlyTextColor.success
            case .danger: GoFlyTextColor.danger
            }
        }
    }
    struct Progress {
        enum Tone { case active, done, failed }
        let fraction: Double
        let tone: Tone
    }

    let state: State
    let titleKey: String
    let trailing: (String, TrailingTone)
    let progress: Progress?
    let identifier: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                glyph
                    .frame(width: 24, height: 24)
                Text(goFlyString(titleKey))
                    .goFlyFont(GoFlyFont.body)
                    .foregroundStyle(state == .pending ? GoFlyTextColor.secondary : GoFlyTextColor.primary)
                Spacer(minLength: 8)
                let tone = trailing.1
                Text(trailing.0)
                    .goFlyFont(GoFlyFont.subheadline)
                    .foregroundStyle(tone.color)
                    .monospacedDigit()
            }
            if let progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(GoFlyThemeColor.lineSeparator)
                        Capsule().fill(progressColor(progress.tone))
                            .frame(width: proxy.size.width * min(1, max(0, progress.fraction)))
                    }
                }
                .frame(height: 4)
                .animation(.linear(duration: 0.2), value: progress.fraction)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .pending:
            Circle().fill(GoFlyTextColor.disabled).frame(width: 10, height: 10)
        case .active:
            ProgressView().controlSize(.small)
        case .done:
            GoFlyIcon(.supportStepDone, size: 24).goFlyIconSize(size: 24, maximum: 24)
        case .failed:
            GoFlyIcon(.alert, size: 22).goFlyIconSize(size: 22, maximum: 22)
                .foregroundStyle(GoFlyTextColor.danger)
        }
    }


    private func progressColor(_ tone: Progress.Tone) -> Color {
        switch tone {
        case .active: GoFlyStyle.primary
        case .done: GoFlyTextColor.success
        case .failed: GoFlyTextColor.danger
        }
    }
}
