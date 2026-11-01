import Testing
@testable import GoFlyCore

struct IssueCatalogTests {
    @Test func connectionAndTimeoutErrorsShareRetry() {
        for key in ["error.serviceUnavailable", "error.tunnelUnavailable", "error.operationTimedOut"] {
            #expect(IssueCatalog.info(for: key).action == .retry, "\(key)")
            #expect(IssueCatalog.info(for: key).scope == .app)
        }
    }

    @Test func routePlanningFailureRepairsOrderInsteadOfRetrying() {
        #expect(IssueCatalog.info(for: "route.error.planningFailed").action == .fix)
        #expect(IssueCatalog.info(for: "error.tunnelUnavailable").action == .retry)
    }

    @Test func setupErrorsOpenSettings() {
        for key in ["error.pairingRequired", "error.identityMismatch", "error.developerModeRequired",
                    "error.devicePreparationRequired", "error.storageUnavailable"] {
            #expect(IssueCatalog.info(for: key).action == .settings, "\(key)")
        }
        #expect(IssueCatalog.info(for: "error.deviceRequired").action == nil)
    }

    @Test func storeReadWriteFailuresRetryAndCorruptionHasNoButton() {
        for store in ["favorites", "imports", "favoriteRoutes", "recovery"] {
            #expect(IssueCatalog.info(for: "\(store).error.writeFailed").action == .retry)
            #expect(IssueCatalog.info(for: "\(store).error.unavailable").action == .retry)
            #expect(IssueCatalog.info(for: "\(store).error.corruptArchive").action == nil)
            #expect(IssueCatalog.info(for: "\(store).error.limitExceeded").action == nil)
            #expect(IssueCatalog.info(for: "\(store).error.writeFailed").scope == .data)
        }
    }

    @Test func fileErrorsChooseAFile() {
        #expect(IssueCatalog.info(for: "gpx.error.tooFewPoints").action == .chooseFile)
        #expect(IssueCatalog.info(for: "imports.error.hashMismatch").action == .chooseFile)
        #expect(IssueCatalog.info(for: "favoriteRoutes.error.hashMismatch").action == nil)
    }

    @Test func validationErrorsHaveNoButtonAndStayOffThePill() {
        let keys = ["route.error.missingStart", "route.error.missingDestination", "favorites.error.invalidLabel",
                    "imports.error.noSelection", "imports.error.busy", "favoriteRoutes.error.nothingToUndo"]
        for key in keys {
            #expect(IssueCatalog.info(for: key).kind == .validation, "\(key)")
            #expect(IssueCatalog.info(for: key).action == nil)
        }
        let errors = SessionStatusErrors(connection: .reachable, route: .missingStart,
                                         dataErrors: ["imports.error.busy"])
        #expect(errors.isEmpty)
        #expect(SessionStatusErrors(connection: .reachable, route: .planningFailed).isEmpty,
                "D8 owns route-planning failure in its floating toast, not the shared session pill")
    }

    @Test func modeErrorsAreScopedToTheirMode() {
        #expect(IssueCatalog.info(for: "route.error.planningFailed").scope == .route)
        #expect(IssueCatalog.info(for: "joystick.error.noCandidate").scope == .joystick)
        #expect(IssueCatalog.info(for: "joystick.error.noCandidate").action == .retry)
    }
}
