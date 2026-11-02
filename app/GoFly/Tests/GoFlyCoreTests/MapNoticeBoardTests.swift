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
                                    unconfirmedID: id, unconfirmedFailure: .pairingRequired,
                                    preparedFailure: .serviceUnavailable,
                                    recoveryNoticeKey: "recovery.connectionLost")
        #expect(MapNoticeBoard.notices(for: input) == [.unconfirmedPosition(key: "error.pairingRequired", inTeleport: true)])

        var left = input
        left.notices.leaveUnconfirmed(id)
        #expect(ids(left) == ["connection", "resume"],
                "Leaving the failed point shows the connection error, which explains the other failures")
    }

    @Test func anOperationThatLostTheConnectionShowsOnlyTheConnectionError() {
        let id = UUID()
        let input = MapNoticeInputs(mode: .teleport, serviceError: .tunnelUnavailable,
                                    unconfirmedID: id, unconfirmedFailure: .operationTimedOut,
                                    preparedFailure: .serviceUnavailable,
                                    routeErrorKey: "route.error.invalidPath")
        #expect(MapNoticeBoard.notices(for: input) == [.connectionIssue(.vpnNotConnected)],
                "No teleport, service or prepared toast beside it, even without a failed probe")

        var route = input
        route.mode = .route
        #expect(MapNoticeBoard.notices(for: route) == [.connectionIssue(.vpnNotConnected)],
                "Another error toast never shows beside the connection error")

        route.isWiFiConnected = false
        #expect(MapNoticeBoard.notices(for: route) == [.connectionIssue(.wifiNotConnected)])
    }

    @Test func wiFiLossShowsTheWiFiIssueUntilDismissed() {
        var input = MapNoticeInputs(mode: .teleport, isWiFiConnected: false)
        #expect(MapNoticeBoard.notices(for: input) == [.connectionIssue(.wifiNotConnected)])
        input.notices.dismiss(.recovery)
        #expect(ids(input).isEmpty)
    }

    @Test func aLostConnectionNamesWiFiThenLocalNetworkThenTheVPN() {
        var input = MapNoticeInputs(mode: .route, recoveryNoticeKey: "recovery.connectionLost",
                                    isWiFiConnected: false, localNetworkDenied: true)
        #expect(MapNoticeBoard.notices(for: input) == [.connectionIssue(.wifiNotConnected)])
        input.isWiFiConnected = true
        #expect(MapNoticeBoard.notices(for: input) == [.connectionIssue(.localNetworkNotAllowed)])
        input.localNetworkDenied = false
        #expect(MapNoticeBoard.notices(for: input) == [.connectionIssue(.vpnNotConnected)])
        input.recoveryNoticeKey = nil
        #expect(ids(input).isEmpty, "A denied permission alone, without a failed check, shows nothing")
        input.recoveryNoticeKey = "recovery.coldClearPending"
        input.requiresColdConfirmation = true
        input.isWiFiConnected = false
        #expect(MapNoticeBoard.notices(for: input) == [.connection(key: "recovery.coldClearPending", coldConfirmation: true)])
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

    @Test func dismissingTheResumeNoticeHidesItWhileTheMovementStaysResumable() {
        let wander = ActiveMovement(kind: .wander, runState: .paused, pauseCause: .background,
                                    resumeAction: .resumeWander, canResume: true)
        var input = MapNoticeInputs(mode: .joystick, activeMovement: wander, isResumeState: true,
                                    continuationNoticeKey: "background.expired")
        #expect(ids(input) == ["resume"])
        input.notices.dismiss(.continuation)
        #expect(ids(input).isEmpty)
        input.notices.reopen(.continuation)
        #expect(ids(input) == ["resume"])
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
