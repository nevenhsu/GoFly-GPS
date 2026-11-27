import GoFlyCore
import SwiftUI
import UniformTypeIdentifiers

struct GoFlyImportedRoutesView: View {
    @EnvironmentObject private var imports: ImportedRoutesStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: RouteExecutionController
    var onLoaded: () -> Void
    var onFocusPoint: (GeoCoordinate) -> Void = { _ in }
    @State private var showingImporter = false
    @State private var actionRecord: ImportedRouteRecord?
    @State private var showingActions = false
    @State private var showingPoints = false
    @State private var snackbar: GoFlySnackbarMessage?
    @State private var shareItem: DiagnosticsShareItem?
    @State private var fileOperationInProgress = false
    @State private var fileTask: Task<Void, Never>?
    @State private var fileErrorKey: String?
    @State private var loadFailureKey: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if fileOperationInProgress || imports.isBusy || imports.isValidatingSelection {
                        ProgressView(goFlyString(imports.isValidatingSelection ? "imports.validating" : "imports.working"))
                            .accessibilityIdentifier("imports.working")
                    }
                    if imports.loadState == .loading {
                        ProgressView(goFlyString("imports.loading"))
                    } else if imports.loadState == .ready, imports.records.isEmpty {
                        GoFlyEmptyState(symbol: nil, message: goFlyString("imports.empty"))
                            .accessibilityIdentifier("imports.empty")
                    }
                    if !imports.records.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(imports.records.reversed().enumerated()), id: \.element.id) { index, record in
                                GoFlyListRow(minimumHeight: 64,
                                             separatorLeadingInset: index < imports.records.count - 1 ? 16 : nil,
                                             separatorTrailingInset: 16) {
                                    recordCard(record)
                                }
                            }
                        }
                        .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: GoFlyStyle.Radius.small, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: GoFlyStyle.Radius.small, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: GoFlyStyle.Radius.small, style: .continuous).strokeBorder(GoFlyStyle.border, lineWidth: GoFlyStyle.Layout.hairline) }
                    }
                }
                .padding(16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("imports.content")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                GoFlyLiveContainerPickerHint()
                importButton
            }
                .opacity(showingActions ? 0 : 1)
                .accessibilityHidden(showingActions)
                .allowsHitTesting(!showingActions)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 6)
                .background(GoFlyStyle.canvas)
                // Same bottom bar as the pairing import page (R07.s): divider, small print, button.
                .goFlyTopHairline()
        }
        .goFlySnackbar($snackbar, bottomPadding: 83)
        .background(GoFlyStyle.canvas.ignoresSafeArea())
        .goFlyPushedFullScreen()
        .overlay(alignment: .top) {
            if let failure = currentFailureKey {
                GoFlyToastOverlay(topInset: 54) {
                    notice(failure, identifier: "imports.error")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let actionRecord, showingActions {
                GoFlyImportedRouteActionSheet(
                    title: actionRecord.filename,
                    detail: goFlyImportedRouteMetadata(actionRecord),
                    canLoad: !isBusy && controller.canEdit && selectedSnapshot != nil && executionFailureKey == nil,
                    canExport: !isBusy && selectedSnapshot != nil,
                    canDelete: !isBusy && imports.canMutate,
                    onLoad: { showingActions = false; loadSelected() },
                    onViewAllPoints: {
                        showingActions = false
                        showingPoints = true
                    },
                    onExport: { showingActions = false; exportSelected() },
                    onDelete: { showingActions = false; deleteSelected() },
                    onCancel: { showingActions = false }
                )
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.goFlyGPX, .xml]) { result in
            switch result {
            case .success(let url): importURL(url)
            case .failure(let error): presentFileError(error)
            }
        }
        .goFlyTracksSystemPresentation(shareItem != nil || showingImporter,
                                       id: "imports.presentation")
        .navigationDestination(isPresented: $showingPoints) {
            if let snapshot = selectedSnapshot {
                GoFlyGPXPointsView(document: snapshot.document, title: snapshot.record.filename, onFocus: onFocusPoint)
            }
        }
        .sheet(item: $shareItem) { item in
            GoFlyShareSheet(url: item.url)
        }
        .onDisappear {
            fileTask?.cancel()
            fileTask = nil
        }
    }

    private var header: some View {
        GoFlySheetNavBar(title: goFlyString("imports.title")) {
            Button { dismiss() } label: {
                if isShowingReturnLabel {
                    GoFlyIconLabel(title: goFlyString("mode.route"), icon: .chevronLeft)
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                } else {
                    Text(goFlyString("common.dismiss"))
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                }
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .buttonStyle(.plain)
            .foregroundStyle(isShowingReturnLabel ? GoFlyTextColor.accent : GoFlyTextColor.primary)
            .accessibilityLabel(goFlyString(isShowingReturnLabel ? "common.back" : "common.dismiss"))
            .accessibilityIdentifier("imports.back")
        } trailing: {
            EmptyView()
        }
        .padding(.horizontal, 16)
    }

    private var isShowingReturnLabel: Bool {
        showingActions || shareItem != nil || showingImporter || snackbar != nil || currentFailureKey != nil
    }

    private var isBusy: Bool { fileOperationInProgress || imports.isBusy || imports.isValidatingSelection }

    private var selectedSnapshot: ImportedRouteSnapshot? {
        guard imports.loadState == .ready, !imports.isValidatingSelection, let snapshot = imports.selectedSnapshot,
              imports.selectedID == snapshot.record.id else { return nil }
        return snapshot
    }

    private var currentFailureKey: String? {
        if case .blocked(let failure) = imports.loadState { return failure.localizationKey }
        return fileErrorKey ?? loadFailureKey ?? imports.error?.localizationKey
    }

    private var executionFailureKey: String? {
        guard let snapshot = selectedSnapshot else { return nil }
        do { _ = try PlannedRoute(imported: snapshot.document); return nil }
        catch let failure as ImportedRouteExecutionFailure { return failure.localizationKey }
        catch { return "imports.error.unavailable" }
    }

    private var importButton: some View {
        Button {
            do {
                if let fixture = try GoFlyGPXFileAccess.uiTestImportURL() { importURL(fixture) }
                else { showingImporter = true }
            } catch { presentFileError(error) }
        } label: {
            Text(goFlyString("imports.import"))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(GoFlyButtonStyle(variant: .primary))
        .disabled(isBusy || !imports.canMutate)
        .accessibilityIdentifier("imports.import")
    }

    private func recordCard(_ record: ImportedRouteRecord) -> some View {
        Button {
            fileErrorKey = nil
            loadFailureKey = nil
            actionRecord = record
            fileTask = Task {
                await imports.select(record.id)
                guard !Task.isCancelled else { return }
                if let key = executionFailureKey { loadFailureKey = key }
                showingActions = true
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.filename).goFlyFont(GoFlyFont.bodyEmphasis).lineLimit(2)
                    Text(record.start.displayText + " → " + record.end.displayText + " · "
                         + goFlyLocalizedFormat(goFlyString("imports.pointsFormat"),
                                                record.pointCount.formatted(.number.locale(GoFlyPreferences.shared.locale))))
                        .goFlyFont(GoFlyFont.footnote).foregroundStyle(GoFlyTextColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let failure = imports.unavailable[record.id] {
                        Text(goFlyString(failure.localizationKey))
                            .goFlyFont(GoFlyFont.footnote).foregroundStyle(GoFlyTextColor.danger)
                            .accessibilityIdentifier("imports.unavailable.\(record.id.uuidString)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                GoFlyIcon(GoFlySymbols.disclosure)
                    .goFlyFont(GoFlyFont.footnoteEmphasis)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || imports.loadState != .ready)
        .accessibilityIdentifier("imports.record.\(record.id.uuidString)")
    }

    private func deleteSelected() {
        guard !isBusy, let record = actionRecord else { return }
        fileTask = Task {
            guard await imports.delete(record.id) else { return }
            snackbar = GoFlySnackbarMessage(text: goFlyString("imports.deleted"),
                actionTitle: imports.canUndo ? goFlyString("imports.undo") : nil,
                action: imports.canUndo ? { Task { _ = await imports.undoDelete() } } : nil)
        }
    }

    private func notice(_ key: String, identifier: String) -> some View {
        let button = goFlyIssueButton(for: key, retry: { Task { await imports.load() } },
                                      chooseFile: { showingImporter = true })
        // File-level failures such as an oversized GPX are outside IssueCatalog,
        // but the D18 design still provides a Retry action. Reopen the picker so
        // the user can retry with a valid file.
        let actionTitle = button.title ?? goFlyString("common.retry")
        let action = button.action ?? { showingImporter = true }
        return GoFlyStatusBanner(tone: .danger, title: goFlyIssueTitle(for: key), message: goFlyString(key),
                                 actionTitle: actionTitle, onAction: action, identifier: identifier)
    }

    private func importURL(_ url: URL) {
        guard !isBusy else { return }
        fileOperationInProgress = true
        fileErrorKey = nil
        loadFailureKey = nil
        fileTask = Task {
            defer { fileOperationInProgress = false }
            do {
                _ = try await GoFlyGPXFileAccess.importFile(url, into: imports)
            }
            catch { presentFileError(error) }
        }
    }

    private func loadSelected() {
        guard let id = imports.selectedID else { return }
        loadRoute(id)
    }

    private func loadRoute(_ id: UUID) {
        guard !isBusy, controller.canEdit else { return }
        // The admission revision must be captured before the async selection
        // revalidation. A late validation result cannot overwrite a newer
        // draft or a transfer hold.
        guard let admission = controller.beginImportedLoad() else { return }
        fileOperationInProgress = true
        loadFailureKey = nil
        fileTask = Task {
            defer { fileOperationInProgress = false }
            await imports.select(id)
            guard !Task.isCancelled, let snapshot = imports.selectedSnapshot,
                  imports.selectedID == id, snapshot.record.id == id, controller.canEdit else { return }
            if controller.loadImportedRoute(snapshot, expectedAdmissionRevision: admission) { onLoaded() }
            else { loadFailureKey = controller.error?.localizationKey }
        }
    }

    private func exportSelected() {
        guard !isBusy, let snapshot = selectedSnapshot else { return }
        fileOperationInProgress = true
        fileErrorKey = nil
        fileTask = Task {
            defer { fileOperationInProgress = false }
            do {
                let data = try await imports.exportSelected()
                try Task.checkCancellation()
                let url = try GoFlyGPXFileAccess.shareURL(data: data, filename: snapshot.record.filename)
                shareItem = DiagnosticsShareItem(url: url)
            } catch { presentFileError(error) }
        }
    }

    private func presentFileError(_ error: any Error) {
        if error is CancellationError || (error as? CocoaError)?.code == .userCancelled { return }
        if let failure = error as? GoFlyGPXFileFailure { fileErrorKey = failure.localizationKey }
        else if let failure = error as? ImportedRoutesFailure { fileErrorKey = failure.localizationKey }
        else if let failure = error as? GPXFailure { fileErrorKey = failure.localizationKey }
        else { fileErrorKey = "imports.file.unavailable" }
    }
}

private struct GoFlyImportedRouteActionSheet: View {
    let title: String
    let detail: String
    let canLoad: Bool
    let canExport: Bool
    let canDelete: Bool
    let onLoad: () -> Void
    let onViewAllPoints: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        GoFlyActionSheet(
            title: title, detail: detail,
            items: [
                GoFlyActionSheetItem(title: goFlyString("imports.action.loadRoute"), icon: .playOutline,
                                     identifier: "imports.load", enabled: canLoad, perform: onLoad),
                GoFlyActionSheetItem(title: goFlyString("imports.action.viewAllPoints"), icon: .asset(.routeList),
                                     identifier: "imports.points.showAll", perform: onViewAllPoints),
                GoFlyActionSheetItem(title: goFlyString("imports.action.exportRoute"), icon: .asset(.externalLink),
                                     identifier: "imports.export", enabled: canExport, perform: onExport),
                GoFlyActionSheetItem(title: goFlyString("imports.action.deleteRoute"), icon: .asset(.trash),
                                     identifier: "imports.delete", enabled: canDelete, isDestructive: true,
                                     perform: onDelete)
            ],
            cancelIdentifier: "imports.actions.cancel",
            identifier: "imports.actions",
            onCancel: onCancel)
    }
}

@MainActor
func goFlyImportedRouteMetadata(_ record: ImportedRouteRecord) -> String {
    goFlyLocalizedFormat(goFlyString("imports.metadata"),
                         goFlyString("imports.kind.\(record.kind.rawValue)"), record.pointCount)
}
