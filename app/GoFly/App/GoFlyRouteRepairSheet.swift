import GoFlyCore
import SwiftUI

/// Shared body of the planning cards (Figma D8.a–c repair, D24.a–d start): a
/// status pill, a leg progress bar, "取消" and one primary action.
struct GoFlyPlanningCardSheet: View {
    enum PrimaryStyle { case primary, destructive }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let pillText: String
    let tone: GoFlyStatusTone
    let fraction: Double
    let progressText: String
    var showsPercent = true
    let primaryTitle: String
    var primaryStyle: PrimaryStyle = .primary
    var primaryEnabled = true
    var idPrefix: String
    var onCancel: () -> Void
    var onPrimary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                GoFlyStatusPill(text: pillText, tone: tone, identifier: "\(idPrefix).title")
                Spacer(minLength: 0)
            }
            ProgressView(value: fraction)
                .progressViewStyle(GoFlyRepairBarStyle())
                .padding(.top, 28)
                .accessibilityLabel(progressText)
                .accessibilityIdentifier("\(idPrefix).progress")
            HStack {
                Text(progressText)
                Spacer()
                if showsPercent { Text("\(Int((fraction * 100).rounded()))%").monospacedDigit() }
            }
            .goFlyFont(GoFlyFont.caption)
            .foregroundStyle(GoFlyTextColor.secondary)
            .padding(.top, 8)
            Spacer(minLength: 0)
            HStack(spacing: 20) {
                Button(action: onCancel) { Text(goFlyString("common.cancel")).frame(maxWidth: .infinity) }
                    .buttonStyle(GoFlyButtonStyle(variant: .neutral))
                    .frame(width: 120)
                    .accessibilityIdentifier("\(idPrefix).cancel")
                Button(action: onPrimary) { Text(primaryTitle).frame(maxWidth: .infinity) }
                    .buttonStyle(GoFlyButtonStyle(variant: primaryStyle == .destructive ? .danger : .primary))
                    .goFlySteadyDisabled(!primaryEnabled)
                    .accessibilityIdentifier("\(idPrefix).primary")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        // The sheet adds about 31 pt below its content; 9 pt more gives the 40 pt bottom margin.
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(221)])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(idPrefix).sheet")
    }
}

extension GoFlyPlanningCardSheet {
    /// A leg-progress card: `done` of `total` legs, `key` formats the progress text.
    init(titleKey: String, tone: GoFlyStatusTone, done: Int, total: Int, progressKey: String,
         primaryTitle: String, primaryStyle: PrimaryStyle = .primary, primaryEnabled: Bool,
         idPrefix: String, onCancel: @escaping () -> Void, onPrimary: @escaping () -> Void) {
        self.init(
            pillText: goFlyString(titleKey), tone: tone,
            fraction: total > 0 ? min(1, Double(done) / Double(total)) : 0,
            progressText: String(format: goFlyString(progressKey), done, total),
            primaryTitle: primaryTitle, primaryStyle: primaryStyle, primaryEnabled: primaryEnabled,
            idPrefix: idPrefix, onCancel: onCancel, onPrimary: onPrimary)
    }
}

/// D8.a／b／c: the route-repair sheet. Running shows attempted legs, success
/// and failure show succeeded legs; cancel keeps the original order.
struct GoFlyRouteRepairSheet: View {
    let state: RoutePlanningRepairState
    var onCancel: () -> Void
    var onDone: () -> Void
    var onDeleteFailed: () -> Void

    var body: some View {
        switch state {
        case .running(let attempted, let total):
            card(title: "route.repair.title.running", tone: .warning, done: attempted, total: total,
                 key: "route.repair.progress.attempted", primary: goFlyString("common.done"),
                 enabled: false, action: onDone)
        case .succeeded(let total):
            card(title: "route.repair.title.succeeded", tone: .success, done: total, total: total,
                 key: "route.repair.progress.succeeded", primary: goFlyString("common.done"),
                 enabled: true, action: onDone)
        case .failed(let succeeded, let total, let failedPlaces, let canDelete):
            card(title: "route.repair.title.failed", tone: .danger, done: succeeded, total: total,
                 key: "route.repair.progress.succeeded",
                 primary: String(format: goFlyString("route.repair.deleteFailed"), failedPlaces),
                 style: .destructive, enabled: canDelete, action: onDeleteFailed)
        }
    }

    private func card(title: String, tone: GoFlyStatusTone, done: Int, total: Int, key: String, primary: String,
                      style: GoFlyPlanningCardSheet.PrimaryStyle = .primary, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        GoFlyPlanningCardSheet(titleKey: title, tone: tone, done: done, total: total, progressKey: key,
                               primaryTitle: primary, primaryStyle: style, primaryEnabled: enabled,
                               idPrefix: "route.repair", onCancel: onCancel, onPrimary: action)
    }
}

/// D24.a–d: the card shown after pressing Start. Planning is gray, success starts
/// automatically, partial failure deletes the failed places and starts, and a
/// total failure clears the places.
struct GoFlyRouteStartSheet: View {
    let state: RouteStartPlanningState
    var onCancel: () -> Void
    var onDeleteFailed: () -> Void
    var onClear: () -> Void

    var body: some View {
        switch state {
        case .planning(let done, let total):
            card(title: "route.start.title.planning", tone: .neutral, done: done, total: total,
                 key: "route.repair.progress.attempted", primary: goFlyString("route.start.inProgress"),
                 enabled: false, action: {})
        case .succeeded(let total):
            card(title: "route.start.title.succeeded", tone: .success, done: total, total: total,
                 key: "route.repair.progress.succeeded", primary: goFlyString("common.done"),
                 enabled: false, action: {})
        case .partial(let succeeded, let total, let failedPlaces, let canDelete):
            card(title: "route.start.title.partial", tone: .danger, done: succeeded, total: total,
                 key: "route.repair.progress.succeeded",
                 primary: String(format: goFlyString("route.repair.deleteFailed"), failedPlaces),
                 style: .destructive, enabled: canDelete, action: onDeleteFailed)
        case .allFailed(let total):
            card(title: "route.start.title.allFailed", tone: .danger, done: 0, total: total,
                 key: "route.repair.progress.succeeded", primary: goFlyString("route.clearPlace"),
                 style: .destructive, enabled: true, action: onClear)
        }
    }

    private func card(title: String, tone: GoFlyStatusTone, done: Int, total: Int, key: String, primary: String,
                      style: GoFlyPlanningCardSheet.PrimaryStyle = .primary, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        GoFlyPlanningCardSheet(titleKey: title, tone: tone, done: done, total: total, progressKey: key,
                               primaryTitle: primary, primaryStyle: style, primaryEnabled: enabled,
                               idPrefix: "route.start", onCancel: onCancel, onPrimary: action)
    }
}

private struct GoFlyRepairBarStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = configuration.fractionCompleted ?? 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(GoFlyStyle.primary.opacity(0.2))
                Capsule().fill(GoFlyStyle.primary).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}
