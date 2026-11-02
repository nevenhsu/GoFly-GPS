import GoFlyCore
import SwiftUI

/// D23 full-screen route overview. The rows show route order and role while
/// preserving the existing tap-to-select/edit behavior from the route planner.
struct GoFlyRouteListView: View {
    @ObservedObject var controller: RouteExecutionController
    var onEditNode: (RouteNodeID) -> Void
    var onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var contentHeight: CGFloat = 46
    @State private var draggingRow = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        routeCard(using: proxy)
                        footer(using: proxy)
                            .padding(.top, 4)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
                // A dragged row must not also scroll the page.
                .scrollDisabled(draggingRow)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GoFlyStyle.canvas)
        .goFlyPushedFullScreen()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.list")
    }

    private var header: some View {
        GoFlySheetHeader(title: goFlyString("route.list.title")) {
            Button(action: onDismiss) {
                GoFlyIconLabel(title: goFlyString("common.back"), icon: .chevronLeft)
                    .goFlyFont(GoFlyFont.body)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(GoFlyTextColor.accent)
            .accessibilityIdentifier("route.list.back")
        } trailing: {
            Button { _ = controller.clearRoute() } label: {
                Text(goFlyString("route.list.clear"))
                    .goFlyFont(GoFlyFont.body)
                    .foregroundStyle(GoFlyTextColor.danger)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!controller.canEdit)
            .accessibilityIdentifier("route.list.clear")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    /// The same rows as the planning panel (grip, place name, ✕, drag to reorder), without the role label.
    private func routeCard(using proxy: ScrollViewProxy) -> some View {
        GoFlyRouteNodeCard(controller: controller, proxy: proxy, height: max(contentHeight, 46),
                           onEditNode: onEditNode, showsRoleLabel: false,
                           onDraggingChange: { draggingRow = $0 },
                           onContentHeightChange: { contentHeight = $0 })
            .padding(.horizontal, 16)
            .accessibilityIdentifier("route.list.nodes")
    }

    /// Figma D23: the two planning actions sit directly below the location card.
    @ViewBuilder
    private func footer(using proxy: ScrollViewProxy) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                addWaypointButton(using: proxy)
                reverseButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        } else {
            HStack(spacing: 16) {
                addWaypointButton(using: proxy)
                Spacer(minLength: 0)
                reverseButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func addWaypointButton(using proxy: ScrollViewProxy) -> some View {
        Button {
            addWaypoint(using: proxy)
        } label: {
            HStack(spacing: 6) {
                Text("＋")
                Text(goFlyString("route.addStop"))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(GoFlyButtonStyle(variant: .ghostPrimary, size: .inline, expandsToFill: false))
        .disabled(!controller.canAddNode)
        .accessibilityIdentifier("route.list.addWaypoint")
        .accessibilityHint(controller.draft.nodes.count == RouteDraft.maximumNodeCount
            ? goFlyString("route.nodeLimit") : "")
    }

    private var reverseButton: some View {
        Button { _ = controller.reverseNodes() } label: {
            GoFlyIconLabel(title: goFlyString("route.exchange"), icon: GoFlySymbols.swapVertical)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(GoFlyButtonStyle(variant: .ghostSecondary, size: .inline, expandsToFill: false))
        .disabled(!controller.canEdit || controller.draft.nodes.count < 2)
        .accessibilityIdentifier("route.list.reverse")
    }

    private func addWaypoint(using proxy: ScrollViewProxy) {
        let existingIDs = Set(controller.draft.nodes.map(\.id))
        guard controller.addEmptyWaypoint(),
              let newID = controller.draft.nodes.first(where: { !existingIDs.contains($0.id) })?.id else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(newID, anchor: .bottom) }
        }
    }
}
