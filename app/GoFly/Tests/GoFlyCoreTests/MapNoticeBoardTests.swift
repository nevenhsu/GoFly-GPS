import Foundation
import Testing
@testable import GoFlyCore

struct MapNoticeBoardTests {
    private func ids(_ input: MapNoticeInputs) -> [String] { MapNoticeBoard.notices(for: input).map(\.id) }

    @Test func aRunningOrFailedSilentRepairOwnsTheMap() {
        let paused = ActiveMovement(kind: .route, runState: .interrupted, pauseCause: .connection,
                                    resumeAction: .retryInterruptedRoute, canResume: true)
        let input = MapNoticeInputs(mode: .route, activeMovement: paused, isResumeState: true,
                                    serviceError: .tunnelUnavailable,
                                    recoveryNoticeKey: "recovery.connectionLost", repairOwnsNotice: true)
        #expect(ids(input) == ["connection"], "No second service-error or resume notice")
    }

    @Test func theTeleportTabsFailedPointOwnsTheMap() {
        let id = UUID()
        let input = MapNoticeInputs(mode: .teleport, isResumeState: true, serviceError: .tunnelUnavailable,
                                    unconfirmedID: id, unconfirmedFailure: .operationTimedOut,
                                    preparedFailure: .serviceUnavailable,
                                    recoveryNoticeKey: "recovery.connectionLost")
        #expect(MapNoticeBoard.notices(for: input) == [.unconfirmedPosition(key: "error.operationTimedOut", inTeleport: true)])

        var left = input
        left.notices.leaveUnconfirmed(id)
        #expect(ids(left) == ["serviceError", "preparedOperationFailed", "connection", "resume"],
                "Leaving the failed point lets the others show again")
    }

    @Test func wiFiLossShowsTheConnectionLostNoticeUntilDismissed() {
        var input = MapNoticeInputs(mode: .teleport, isWiFiConnected: false)
        #expect(MapNoticeBoard.notices(for: input) == [.connection(key: "recovery.connectionLost", coldConfirmation: false)])
        input.notices.dismiss(.recovery)
        #expect(ids(input).isEmpty)
    }

    @Test func aPauseThePersonPressedHasNoResumeNotice() {
        let route = ActiveMovement(kind: .route, runState: .paused, pauseCause: .user,
                                   resumeAction: .resumeRoute, canResume: true)
        #expect(ids(MapNoticeInputs(mode: .route, activeMovement: route, isResumeState: true)).isEmpty)

        let background = ActiveMovement(kind: .route, runState: .paused, pauseCause: .background,
                                        resumeAction: .resumeRoute, canResume: false)
        let notices = MapNoticeBoard.notices(for: MapNoticeInputs(mode: .route, activeMovement: background, isResumeState: true))
        #expect(notices == [.resume(.init(titleKey: "route.pausedToast.title", messageKey: "route.pausedToast.message",
                                          actionTitleKey: "common.continue", action: .resumeRoute, actionEnabled: false))])
    }

    @Test func resumeNoticesWaitForTheSceneToSettle() {
        let hold = ActiveMovement(kind: .positionHold, runState: .paused, pauseCause: .background,
                                  resumeAction: .retryPositionHold, canResume: true)
        #expect(ids(MapNoticeInputs(mode: .teleport, sceneSettled: false, activeMovement: hold, isResumeState: true)).isEmpty)
        #expect(ids(MapNoticeInputs(mode: .teleport, activeMovement: hold, isResumeState: true)) == ["resume"])
    }

    @Test func aContinuationNoticeWithoutAMovementOpensSettings() {
        let notices = MapNoticeBoard.notices(for: MapNoticeInputs(mode: .joystick, continuationNoticeKey: "background.unavailable"))
        #expect(notices == [.resume(.init(titleKey: "background.unavailable", messageKey: "status.repairGuidance",
                                          actionTitleKey: "common.retry", action: nil, actionEnabled: true))])
    }

    @Test func tabScopedErrorsShowOnlyInTheirTab() {
        let input = MapNoticeInputs(mode: .teleport, joystickErrorKey: "joystick.error.originUnavailable",
                                    wanderError: .planningFailed, routeErrorKey: "route.error.planningFailed")
        #expect(ids(input).isEmpty)
        var route = input; route.mode = .route
        #expect(ids(route) == ["routeError"])
        var joystick = input; joystick.mode = .joystick
        #expect(ids(joystick) == ["wanderPlanningFailed", "joystickError"])
    }

    @Test func aCancelledOperationIsNeverANotice() {
        #expect(ids(MapNoticeInputs(mode: .teleport, serviceError: .operationCancelled,
                                    preparedFailure: .operationCancelled)).isEmpty)
    }
}
