import GoFlyCore
import SwiftUI

@MainActor
func goFlyRouteRoleTitle(_ role: RouteNodeRole) -> String {
    switch role {
    case .start: goFlyString("route.origin")
    case .destination: goFlyString("route.destination")
    case .waypoint(let number): goFlyLocalizedFormat(goFlyString("route.waypoint"), number)
    }
}

@MainActor
func goFlyRouteEditTitle(_ role: RouteNodeRole) -> String {
    switch role {
    case .start: goFlyString("route.editOrigin")
    case .destination: goFlyString("route.editDestination")
    case .waypoint(let number): goFlyLocalizedFormat(goFlyString("route.editWaypoint"), number)
    }
}

struct GoFlyRouteNodeList: View {
    let draft: RouteDraft
    var selectedID: RouteNodeID? = nil
    let isEditable: Bool
    let viewport: CGRect
    /// The first tap selects a field; tapping it again opens D5 for the selected field.
    var onEdit: (RouteNodeID) -> Void
    var onDelete: (RouteNodeID) -> Void
    var onMove: (RouteNodeID, Int) -> Void
    var onScroll: (RouteNodeID, UnitPoint) -> Void
    /// Reports when a row drag starts and ends so the container can stop user scrolling.
    var onDraggingChange: (Bool) -> Void = { _ in }
    /// The all-locations list (D23) shows only the place name; the planning panel adds the role above it.
    var showsRoleLabel = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @GestureState private var gestureIsActive = false
    @State private var draggingID: RouteNodeID?
    @State private var originalOrder: [RouteNodeID] = []
    @State private var previewOrder: [RouteNodeID] = []
    @State private var rowFrames: [RouteNodeID: CGRect] = [:]
    @State private var listFrame: CGRect = .zero
    @State private var dragHeight: CGFloat = 60
    @State private var pointer = CGPoint.zero
    @State private var autoscroll: Task<Void, Never>?

    private var order: [RouteNodeID] { draft.nodes.map(\.id) }
    private var visibleOrder: [RouteNodeID] { draggingID == nil ? order : previewOrder }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleOrder.enumerated()), id: \.element) { index, id in
                if let node = draft.nodes.first(where: { $0.id == id }) {
                    row(node)
                        .opacity(draggingID == id ? 0 : 1)
                        .frame(height: draggingID == id ? dragHeight : nil)
                        .overlay {
                            if draggingID == id {
                                let shape = rowShape(at: index)
                                shape
                                    .fill(GoFlyStyle.surface)
                                    .overlay { shape.strokeBorder(GoFlyStyle.primary, lineWidth: 2) }
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityHidden(draggingID == id)
                    .id(id)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { rowFrames[id] = $0 }
                    if index < visibleOrder.count - 1 {
                        Rectangle().fill(GoFlyThemeColor.lineSeparator)
                            .frame(height: 0.5)
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { listFrame = $0 }
        .overlay(alignment: .topLeading) {
            if let id = draggingID, let node = draft.nodes.first(where: { $0.id == id }) {
                row(node)
                    .frame(width: listFrame.width, height: dragHeight)
                    .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: GoFlyThemeColor.commonBlack.opacity(0.18), radius: 10, y: 5)
                    .scaleEffect(1.02)
                    .position(x: listFrame.width / 2, y: pointer.y - listFrame.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.nodes.list")
        .onChange(of: rowFrames) { _, _ in updateProjection() }
        .onChange(of: draggingID != nil) { _, dragging in onDraggingChange(dragging) }
        .onChange(of: gestureIsActive) { _, active in if !active { cancelDrag() } }
        .onChange(of: draft.nodes) { _, _ in cancelDrag() }
        .onChange(of: isEditable) { _, editable in if !editable { cancelDrag() } }
        .onChange(of: dynamicTypeSize) { _, _ in cancelDrag() }
        .onChange(of: viewport.width) { _, _ in cancelDrag() }
        .onDisappear { cancelDrag() }
        .task {
#if DEBUG && targetEnvironment(simulator)
            guard GoFlyUITestOverrides.frame == "D2.a",
                  let id = draft.nodes.dropFirst().first?.id else { return }
            for _ in 0..<30 {
                if let frame = rowFrames[id] {
                    originalOrder = order
                    previewOrder = order
                    dragHeight = frame.height
                    pointer = CGPoint(x: frame.midX, y: frame.midY + 16)
                    draggingID = id
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
#endif
        }
    }

    /// Only the first row's top and the last row's bottom follow the card radius;
    /// rows in between stay square so a border or highlight joins the card.
    private func rowShape(at index: Int) -> UnevenRoundedRectangle {
        let isFirstRow = index == 0
        let isLastRow = index == visibleOrder.count - 1
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirstRow ? GoFlyStyle.routeListCardRadius : 0,
            bottomLeadingRadius: isLastRow ? GoFlyStyle.routeListCardRadius : 0,
            bottomTrailingRadius: isLastRow ? GoFlyStyle.routeListCardRadius : 0,
            topTrailingRadius: isFirstRow ? GoFlyStyle.routeListCardRadius : 0,
            style: .continuous)
    }

    private func row(_ node: RouteNode) -> some View {
        let role = draft.role(of: node.id) ?? .start
        let isSelected = isEditable && selectedID == node.id
        let index = visibleOrder.firstIndex(of: node.id) ?? 0
        let selectionShape = rowShape(at: index)
        return HStack(spacing: 0) {
            GoFlyIcon(GoFlySymbols.reorder)
                .goFlyIconSize(size: 18)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .gesture(dragGesture(for: node.id))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(goFlyLocalizedFormat(goFlyString("route.reorderNode"), goFlyRouteRoleTitle(role), title(node.value, role: role)))
                .accessibilityHint(goFlyString("route.dragHint"))
                .accessibilityAction(named: Text(goFlyString("route.moveUp"))) { move(node.id, by: -1) }
                .accessibilityAction(named: Text(goFlyString("route.moveDown"))) { move(node.id, by: 1) }
                .accessibilityAction(named: Text(removeTitle(node, role: role))) {
                    if isEditable, draft.canRemove(nodeID: node.id) { onDelete(node.id) }
                }
                .accessibilityIdentifier("route.handle.\(node.id.rawValue.uuidString)")
            Button { if isEditable { onEdit(node.id) } } label: {
                VStack(alignment: .leading, spacing: 1) {
                    if showsRoleLabel {
                        Text(goFlyRouteRoleTitle(role)).goFlyFont(GoFlyFont.captionEmphasis).foregroundStyle(GoFlyTextColor.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    }
                    GoFlyRouteNodeTitleText(value: node.value, role: role,
                                            lineLimit: dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEditable || draggingID != nil)
            .accessibilityLabel(goFlyRouteEditTitle(role))
            .accessibilityValue(title(node.value, role: role))
            .accessibilityHint(goFlyString("route.fieldSearchHint"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(editIdentifier(role))
            if isEditable {
                GoFlyRouteNodeDeleteButton(
                    label: removeTitle(node, role: role),
                    identifier: "route.delete.\(node.id.rawValue.uuidString)",
                    enabled: draft.canRemove(nodeID: node.id) && draggingID == nil
                ) { if draft.canRemove(nodeID: node.id) { onDelete(node.id) } }
            } else {
                Spacer().frame(width: 16)
            }
        }
        .frame(minHeight: showsRoleLabel ? 60 : 46)
        .background {
            if isSelected {
                selectionShape
                    .fill(colorScheme == .dark ? GoFlyThemeColor.surfaceControlActive : GoFlyStyle.cardSurface)
                    .overlay {
                        selectionShape.strokeBorder(GoFlyStyle.primary, lineWidth: 1.5)
                    }
            }
        }
        .foregroundStyle(isEditable ? GoFlyTextColor.primary : GoFlyTextColor.disabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.row.\(node.id.rawValue.uuidString)")
    }

    private func dragGesture(for id: RouteNodeID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($gestureIsActive) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard isEditable, case .second(true, let drag) = value, let drag else { return }
                if draggingID == nil { beginDrag(id, at: drag.startLocation) }
                guard draggingID == id else { return }
                pointer = drag.location
                updateProjection()
            }
            .onEnded { _ in finishDrag() }
    }

    private func beginDrag(_ id: RouteNodeID, at point: CGPoint) {
        guard let frame = rowFrames[id], isEditable else { return }
        originalOrder = order
        previewOrder = order
        dragHeight = frame.height
        pointer = point
        draggingID = id
        autoscroll?.cancel()
        autoscroll = Task { @MainActor in
            while !Task.isCancelled, draggingID != nil {
                updateProjection()
                scrollAtEdge()
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func updateProjection() {
        guard let id = draggingID, originalOrder == order else { return }
        // The grip is centered in its row, so the row center follows the finger. Measuring an
        // offset from the drag's start would lose the movement made before the drag phase began.
        let center = pointer.y
        let remaining = previewOrder.filter { $0 != id }
        let target = remaining.filter { other in rowFrames[other].map { $0.midY < center } ?? false }.count
        var next = remaining
        next.insert(id, at: min(target, next.count))
        if next != previewOrder { previewOrder = next }
    }

    private func acceptsDrop(at point: CGPoint) -> Bool {
        guard viewport.width > 0, viewport.height > 0 else { return false }
        // Keep the first and last preview slots reachable when the finger crosses the clipped
        // card edge. The preview order still determines the destination; distant drops cancel.
        return viewport.insetBy(dx: 0, dy: -max(16, dragHeight)).contains(point)
    }

    private func scrollAtEdge() {
        guard viewport.height > 0, let id = draggingID else { return }
        let remaining = previewOrder.filter { $0 != id }
        let visible = remaining.indices.filter { index in
            rowFrames[remaining[index]].map { $0.intersects(viewport.insetBy(dx: 0, dy: 1)) } ?? false
        }
        if pointer.y > viewport.maxY - 40, let last = visible.last {
            if last + 1 < remaining.count { onScroll(remaining[last + 1], .bottom) }
            else if let frame = rowFrames[id], frame.maxY > viewport.maxY { onScroll(id, .bottom) }
        } else if pointer.y < viewport.minY + 40, let first = visible.first {
            if first > 0 { onScroll(remaining[first - 1], .top) }
            else if let frame = rowFrames[id], frame.minY < viewport.minY { onScroll(id, .top) }
        }
    }

    private func finishDrag() {
        guard let id = draggingID else { return }
        updateProjection()
        let target = previewOrder.firstIndex(of: id)
        let canCommit = isEditable && originalOrder == order && acceptsDrop(at: pointer)
        cancelDrag()
        if canCommit, let target {
            withAnimation(.easeInOut(duration: 0.2)) { onMove(id, target) }
        }
    }

    private func cancelDrag() {
        autoscroll?.cancel()
        autoscroll = nil
        draggingID = nil
        originalOrder = []
        previewOrder = []
    }

    private func move(_ id: RouteNodeID, by offset: Int) {
        guard isEditable, draggingID == nil, let index = order.firstIndex(of: id), order.indices.contains(index + offset) else { return }
        onMove(id, index + offset)
    }

    private func title(_ value: RouteNodeValue, role: RouteNodeRole) -> String {
        goFlyRouteNodeTitle(value, role: role)
    }

    private func removeTitle(_ node: RouteNode, role: RouteNodeRole) -> String {
        let deletes: Bool = if case .waypoint = role { true } else { role == .destination && node.value == .empty }
        if deletes { return goFlyLocalizedFormat(goFlyString("route.deleteNode"), goFlyRouteRoleTitle(role)) }
        return goFlyLocalizedFormat(goFlyString("route.clearNode"), goFlyRouteRoleTitle(role))
    }
    private func editIdentifier(_ role: RouteNodeRole) -> String {
        switch role { case .start: "route.node.start"; case .destination: "route.node.destination"; case .waypoint(let n): "route.node.waypoint.\(n)" }
    }
}

/// The bordered, scrollable route node card shared by the planning panel (D1/D2)
/// and the full-screen route list, so rows, dragging and edge autoscroll stay identical.
/// The caller owns the `ScrollViewReader` so its own controls can scroll the list too.
struct GoFlyRouteNodeCard: View {
    @ObservedObject var controller: RouteExecutionController
    let proxy: ScrollViewProxy
    @Environment(\.colorScheme) private var colorScheme
    /// Scroll height: the rows' height up to the space available, then the list scrolls.
    let height: CGFloat
    var lightSurface: Color = GoFlyStyle.cardSurface
    var onEditNode: (RouteNodeID) -> Void
    var showsRoleLabel = true
    /// Lets a parent ScrollView stop scrolling while a row is dragged.
    var onDraggingChange: (Bool) -> Void = { _ in }
    var onContentHeightChange: (CGFloat) -> Void = { _ in }

    @State private var visibleScrollFrame: CGRect = .zero
    @State private var draggingHeight: CGFloat?

    var body: some View {
        ScrollView {
            GoFlyRouteNodeList(
                draft: controller.draft,
                selectedID: controller.selectedNodeID,
                isEditable: controller.canEdit,
                viewport: visibleScrollFrame,
                onEdit: onEditNode,
                onDelete: { _ = controller.removeNode(id: $0) },
                onMove: { _ = controller.moveNode(id: $0, toIndex: $1) },
                onScroll: { id, anchor in
                    withAnimation(.linear(duration: 0.12)) { proxy.scrollTo(id, anchor: anchor) }
                },
                onDraggingChange: { dragging in
                    draggingHeight = dragging ? height : nil
                    onDraggingChange(dragging)
                },
                showsRoleLabel: showsRoleLabel
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { onContentHeightChange($0) }
        }
        .scrollIndicators(.visible)
        // A short list never rubber-bands; while a row is dragged the card keeps its height
        // and stops user scrolling so the pan cannot shift rows under the finger.
        // Edge autoscroll still runs through `proxy.scrollTo`.
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(draggingHeight != nil)
        .frame(height: draggingHeight ?? height)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
        .background(
            colorScheme == .dark ? GoFlyStyle.secondarySurface : lightSurface,
            in: RoundedRectangle(cornerRadius: GoFlyStyle.routeListCardRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: GoFlyStyle.routeListCardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.routeListCardRadius, style: .continuous)
                .strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}
