#if DEBUG && targetEnvironment(simulator)
import Combine
import GoFlyCore
import SwiftUI

/// Simulator-only gallery for the redesign's shared components. It is only
/// reachable with `-gofly-ui-gallery`, so it never appears in a normal launch,
/// a device build or a release build. Used for screenshots and UI checks.
struct GoFlyComponentGallery: View {
    @State private var snackbar: GoFlySnackbarMessage?
    @State private var endResult = "idle"
    @State private var detent: GoFlySheetDetent = .half
    @State private var mode: SessionMapMode = .teleport
    @State private var sliderValue = 40.0
    @State private var sliderWidth: CGFloat = 240
    @State private var showingSystemDimPreview = false
    @StateObject private var joystick = JoystickMovementController(commands: GalleryJoystickCommands())

    var body: some View {
        if GoFlyUITestOverrides.contains("-gofly-ui-feedback-components") {
            feedbackComponentsBody
        } else if GoFlyUITestOverrides.contains("-gofly-ui-shared-components") {
            sharedComponentsBody
        } else {
            regularGalleryBody
        }
    }

    private var feedbackComponentsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Button(goFlyString("gallery.showSnackbar")) {
                    snackbar = GoFlySnackbarMessage(
                        text: goFlyString("gallery.snackbarText"),
                        actionTitle: goFlyString("common.undo"),
                        action: {})
                }
                .buttonStyle(GoFlyButtonStyle(variant: .primary))
                .accessibilityIdentifier("gallery.feedback.snackbar.show")
                Button(goFlyString("gallery.presentationDim.show")) {
                    showingSystemDimPreview = true
                }
                .buttonStyle(GoFlyButtonStyle(variant: .neutral, size: .medium))
                .accessibilityIdentifier("gallery.systemDim.show")
                bannerSection
                pillSection
                feedbackSnackbarSection
                fieldSection
            }
            .padding(16)
        }
        .background(GoFlyStyle.canvas)
        .goFlySnackbar($snackbar)
        .goFlyTracksSystemPresentation(showingSystemDimPreview, id: "gallery.systemDim")
        .sheet(isPresented: $showingSystemDimPreview) {
            GoFlySpeedSheet(
                speed: RouteSpeed(kilometersPerHour: 25)!,
                canEdit: false,
                onSpeedChanged: { _ in },
                onDismiss: { showingSystemDimPreview = false }
            )
        }
        .accessibilityIdentifier("gallery.feedbackComponents")
    }

    private var regularGalleryBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                bannerSection
                pillSection
                snackbarSection
                fieldSection
                bottomBarSection
                executionSection
                routeRunningSection
                routePausedSection
                joystickSection
                sheetSection
            }
            .padding(16)
        }
        .background(GoFlyStyle.canvas)
        .goFlySnackbar($snackbar)
        .accessibilityIdentifier("gallery")
    }

    private var sharedComponentsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                iconButtonSection
                iconTextButtonSection
                textButtonSection
                checkButtonSection
                statusActionSection
                fieldSection
            }
            .padding(16)
        }
        .background(GoFlyStyle.canvas)
        .statusBarHidden()
        .accessibilityIdentifier("gallery.sharedComponents")
    }

    private var iconButtonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(goFlyString("gallery.component.iconButtons"))
                .accessibilityIdentifier("gallery.iconButtons.heading")
            ForEach(GoFlyIconButtonVariant.allCases) { variant in
                VStack(alignment: .leading, spacing: 8) {
                    Text(goFlyString(variant.galleryTitleKey))
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                    ForEach(GoFlyIconButtonSize.allCases) { size in
                        HStack(spacing: 8) {
                            Text(goFlyString(size.galleryTitleKey))
                                .goFlyFont(GoFlyFont.caption)
                                .foregroundStyle(GoFlyTextColor.secondary)
                                .frame(width: 78, alignment: .leading)
                            iconButtonSample(variant, size: size, disabled: false)
                            iconButtonSample(variant, size: size, disabled: true)
                        }
                    }
                }
                .padding(12)
                .goFlyCard(radius: GoFlyStyle.cardRadius)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("gallery.iconButtons.\(variant.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery.iconButtons")
    }

    private func iconButtonSample(_ variant: GoFlyIconButtonVariant,
                                  size: GoFlyIconButtonSize,
                                  disabled: Bool) -> some View {
        Button {} label: {
            GoFlyIcon(variant.galleryIcon, size: size.glyph, maximumSize: size.glyph)
        }
        .buttonStyle(GoFlyIconStyle(variant: variant, size: size))
        .disabled(disabled)
        .accessibilityLabel(goFlyString("gallery.component.sample"))
        .accessibilityValue("\(goFlyString("gallery.iconButton.variant.\(variant.id)")), \(goFlyString(size.galleryTitleKey)), \(goFlyString(disabled ? "gallery.component.disabled" : "gallery.component.enabled"))")
        .accessibilityIdentifier("gallery.iconButton.\(variant.id).\(size.id).\(disabled ? "disabled" : "enabled")")
    }

    private var iconTextButtonSection: some View {
        textButtonSamples(includeIcon: true,
                          heading: goFlyString("gallery.component.iconTextButtons"),
                          identifier: "gallery.iconTextButtons")
    }

    private var textButtonSection: some View {
        textButtonSamples(includeIcon: false,
                          heading: goFlyString("gallery.component.textButtons"),
                          identifier: "gallery.textButtons")
    }

    private func textButtonSamples(includeIcon: Bool, heading: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(heading)
                .accessibilityIdentifier("\(identifier).heading")
            ForEach(GoFlyButtonVariant.allCases) { variant in
                VStack(alignment: .leading, spacing: 8) {
                    Text(goFlyString(variant.galleryTitleKey))
                        .goFlyFont(GoFlyFont.subheadlineEmphasis)
                    ForEach(GoFlyButtonSize.allCases) { size in
                        HStack(spacing: 8) {
                            Text(goFlyString(size.galleryTitleKey))
                                .goFlyFont(GoFlyFont.caption)
                                .foregroundStyle(GoFlyTextColor.secondary)
                                .frame(width: 78, alignment: .leading)
                            textButtonSample(variant, size: size, includeIcon: includeIcon, disabled: false)
                            textButtonSample(variant, size: size, includeIcon: includeIcon, disabled: true)
                        }
                    }
                }
                .padding(12)
                .goFlyCard(radius: GoFlyStyle.cardRadius)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("\(identifier).\(variant.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func textButtonSample(_ variant: GoFlyButtonVariant,
                                  size: GoFlyButtonSize,
                                  includeIcon: Bool,
                                  disabled: Bool) -> some View {
        let title = goFlyString(variant.galleryActionKey)
        return Button {} label: {
            GoFlyIconLabel(title: title, icon: includeIcon ? variant.galleryIcon : nil,
                           iconSize: size == .extraSmall ? 14 : 18, spacing: 6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .buttonStyle(GoFlyButtonStyle(variant: variant, size: size))
        .disabled(disabled)
        .accessibilityIdentifier("gallery.\(includeIcon ? "iconText" : "text")Button.\(variant.id).\(size.id).\(disabled ? "disabled" : "enabled")")
    }

    private var checkButtonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(goFlyString("gallery.component.checkButtons"))
                .accessibilityIdentifier("gallery.checkButtons.heading")
            HStack(spacing: 20) {
                Button {} label: {
                    HStack(spacing: 8) {
                        GoFlyCheckboxIcon(selected: true)
                        Text(goFlyString("gallery.component.selected"))
                            .goFlyFont(GoFlyFont.subheadline)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("gallery.component.selected"))
                .accessibilityIdentifier("gallery.check.selected")

                Button {} label: {
                    HStack(spacing: 8) {
                        GoFlyCheckboxIcon(selected: false)
                        Text(goFlyString("gallery.component.unselected"))
                            .goFlyFont(GoFlyFont.subheadline)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("gallery.component.unselected"))
                .accessibilityIdentifier("gallery.check.unselected")
            }
            .foregroundStyle(GoFlyTextColor.primary)
            .goFlyCard(radius: GoFlyStyle.cardRadius)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery.checkButtons")
    }

    private var statusActionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(goFlyString("gallery.component.statusActions"))
                .accessibilityIdentifier("gallery.statusActions.heading")
            HStack(spacing: 12) {
                Button(goFlyString("operation.retry")) {}
                    .buttonStyle(GoFlyStatusActionStyle(tone: .danger))
                    .accessibilityIdentifier("gallery.statusAction.danger")
                Button(goFlyString("common.continue")) {}
                    .buttonStyle(GoFlyStatusActionStyle(tone: .warning))
                    .accessibilityIdentifier("gallery.statusAction.warning")
                Button(goFlyString("common.undo")) {}
                    .buttonStyle(GoFlyStatusActionStyle(tone: .success))
                    .accessibilityIdentifier("gallery.statusAction.success")
            }
            .goFlyCard(radius: GoFlyStyle.cardRadius)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery.statusActions")
    }

    private var bannerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("StatusBanner")
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyString("gallery.dangerTitle"),
                message: goFlyString("gallery.dangerMessage"),
                actionTitle: goFlyString("operation.retry"),
                onAction: {},
                onDismiss: {},
                identifier: "gallery.banner.danger"
            )
            GoFlyStatusBanner(
                tone: .warning,
                title: goFlyString("gallery.warningTitle"),
                message: goFlyString("gallery.warningMessage"),
                actionTitle: goFlyString("common.continue"),
                onAction: {},
                onDismiss: {},
                identifier: "gallery.banner.warning"
            )
            GoFlyStatusBanner(
                tone: .success,
                title: goFlyString("gallery.successTitle"),
                message: goFlyString("gallery.successMessage"),
                identifier: "gallery.banner.success"
            )
        }
    }

    private var pillSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("StatusPill")
            let statuses: [GoFlySessionStatus] = [.started, .simulating, .paused, .error]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(statuses, id: \.textKey) { status in
                    GoFlyStatusPill(text: goFlyString(status.textKey), tone: status.tone,
                                    action: {}, identifier: "gallery.pill." + status.textKey)
                }
            }
        }
    }

    private var snackbarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Snackbar")
            Button(goFlyString("gallery.showSnackbar")) {
                snackbar = GoFlySnackbarMessage(
                    text: goFlyString("gallery.snackbarText"),
                    actionTitle: goFlyString("common.undo"),
                    action: {})
            }
            .buttonStyle(GoFlyButtonStyle(variant: .primary))
            .accessibilityIdentifier("gallery.snackbar.show")
            GoFlySnackbar(message: GoFlySnackbarMessage(
                text: goFlyString("gallery.snackbarText"),
                actionTitle: goFlyString("common.undo"),
                action: {}))
            .accessibilityIdentifier("gallery.snackbar.preview")
        }
    }

    private var feedbackSnackbarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Snackbar")
            GoFlySnackbar(message: GoFlySnackbarMessage(text: goFlyString("gallery.snackbarText")))
                .accessibilityIdentifier("gallery.snackbar.automatic")
            GoFlySnackbar(message: GoFlySnackbarMessage(
                text: goFlyString("gallery.snackbarText"),
                actionTitle: goFlyString("common.undo"),
                action: {}))
                .accessibilityIdentifier("gallery.snackbar.undo")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery.feedbackSnackbars")
    }

    private var fieldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(goFlyString("gallery.component.textFields"))
                .accessibilityIdentifier("gallery.textFields.heading")
            ForEach([GoFlyTextFieldState.default, .focused, .disabled], id: \.self) { state in
                HStack(spacing: 8) {
                    GoFlyIcon(.search, size: 16)
                        .foregroundStyle(state == .disabled ? GoFlyTextColor.disabled : GoFlyThemeColor.iconInputDefault)
                    Text(goFlyString(state == .focused ? "gallery.fieldFocused" : "gallery.fieldNormal"))
                        .goFlyFont(GoFlyFont.subheadline)
                        .foregroundStyle(state == .default ? GoFlyTextColor.secondary : (state == .disabled ? GoFlyTextColor.disabled : GoFlyTextColor.primary))
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .goFlyTextField(state: state)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("gallery.field.\(state.identifier)")
            }
            ProgressView(value: 0.35, total: 1)
                .progressViewStyle(GoFlyProgressStyle())
                .accessibilityIdentifier("gallery.progress")
            Slider(value: $sliderValue, in: 1...120)
                .tint(GoFlyStyle.primary)
                .frame(width: sliderWidth, alignment: .leading)
                .accessibilityIdentifier("gallery.slider")
            Button(goFlyString("gallery.slider.resize")) {
                sliderWidth = sliderWidth == 240 ? 320 : 240
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gallery.slider.resize")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery.textFields")
    }

    private var bottomBarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("BottomBar")
            GoFlyBottomBar(selection: $mode)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("gallery.bottomBar")
        }
    }

    private var executionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Execution")
            GoFlyWanderDestinationRow(title: goFlyString("gallery.executionTitle"),
                                     caption: goFlyString("joystick.wander"), canRandomize: true,
                                     onRandomDestination: {})
            GoFlyExecutionHeader(title: goFlyString("gallery.executionTitle"),
                                 detail: goFlyString("gallery.executionDetail"))
            GoFlyExecutionControls(progress: 0.42, isPaused: false, canPause: true, canResume: false,
                                   onPause: {}, onResume: {}, onEnd: {}) {
                GoFlyExecutionToggle(title: goFlyString("route.roundTrip"),
                                     symbol: GoFlySymbols.swap, isOn: true, action: {},
                                     identifier: "gallery.execution.roundTrip")
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var routeRunningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("RouteRunning")
            GoFlyRouteRunningControls(
                title: GoFlyRouteRunningControls.remainingTitle(.seconds(4_500)), fraction: 0.26,
                isRoundTrip: false, isReversed: false, speed: 25,
                onPlayback: { endResult = "playback" },
                onEnd: { endResult = "ended" })
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
                .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("gallery.routeRunning")
            Text(endResult)
                .goFlyFont(GoFlyFont.footnote)
                .accessibilityIdentifier("gallery.endResult")
        }
    }

    /// Figma D10: the interruption toast and the 76 pt resume panel.
    private var routePausedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("RoutePaused")
            GoFlyStatusBanner(
                tone: .warning,
                title: goFlyString("route.pausedToast.title"),
                message: goFlyString("route.pausedToast.message"),
                actionTitle: goFlyString("common.retry"),
                onAction: {}, onDismiss: {},
                identifier: "gallery.pausedToast")
            GoFlyResumePanel(
                title: goFlyLocalizedFormat(goFlyString("route.paused.progress"), 45),
                subtitle: goFlyLocalizedFormat(goFlyString("route.paused.remaining"), 1.2, 14),
                ctaTitle: goFlyString("route.resumeShort"),
                onResume: {}, identifier: "gallery.resumePanel")
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var joystickSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("JoystickPanel")
            GoFlyJoystickPanel(
                controller: joystick,
                cameraHeadingDegrees: 0,
                maximumHeight: 420,
                onRandomDestination: {},
                onSettings: {}
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
            }
        }
    }

    private var sheetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("BottomSheet")
            GoFlyBottomSheet(detent: $detent, availableHeight: 520, collapsedHeight: 96) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(goFlyString("gallery.sheetTitle")).goFlyFont(GoFlyFont.headline)
                    Text(goFlyString("gallery.sheetBody"))
                        .goFlyFont(GoFlyFont.subheadline)
                        .foregroundStyle(GoFlyTextColor.secondary)
                    ForEach(0..<6, id: \.self) { index in
                        Text(goFlyString("gallery.sheetRow"))
                            .goFlyFont(GoFlyFont.body)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .goFlyFont(GoFlyFont.title)
            .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
private final class GalleryJoystickCommands: JoystickCommanding {
    private let subject = PassthroughSubject<JoystickCommandEvent, Never>()
    var canBeginJoystick: Bool { true }
    var currentJoystickOrigin: GeoCoordinate? { GeoCoordinate(latitude: 25.0330, longitude: 121.5654) }
    var movementAdmissionRevision: UInt64 { 1 }
    var joystickEvents: AnyPublisher<JoystickCommandEvent, Never> { subject.eraseToAnyPublisher() }
    func beginJoystick(_ intent: JoystickMovementIntent, expectedMovementAdmissionRevision: UInt64) async -> JoystickPreparationOutcome { .cancelled }
    func joystickInputRevision(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? { nil }
    func reviseJoystickInput(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? { nil }
    func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedInputRevision: JoystickInputRevision, displacement: JoystickDisplacement) async -> JoystickStepOutcome { .cancelled }
    func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedInputRevision: JoystickInputRevision, recipe: JoystickStepRecipe) async -> JoystickRecipeStepOutcome { .cancelled }
    func releaseJoystick(executionID: UUID, lease: MovementTaskLease, disposition: JoystickReleaseDisposition) -> Bool { false }
    func resumeJoystick(executionID: UUID, lease: MovementTaskLease) -> Bool { false }
    func resumeJoystickStream(executionID: UUID, lease: MovementTaskLease) -> Bool { false }
    func waitForJoystickIdle(executionID: UUID, lease: MovementTaskLease) async -> JoystickIdleSettlement { .settled }
}
#endif
