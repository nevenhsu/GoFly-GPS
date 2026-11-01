import Foundation
import Testing
import GoFlyMacCore

@Suite @MainActor struct MacSetupModelTests {
    private let device = "00008110-001234567890abcd"

    @Test func reopenRetainsOriginalIdentityWithoutCallingTheDevice() async throws {
        let original = try MacSetupTransactionIdentity(setupID: UUID(), deviceID: device, teamID: "ABCDE12345")
        let journal = ModelJournal(original)
        let runner = HeldSetupRunner()
        let model = MacSetupModel(runner: runner, journal: journal)
        #expect(!model.isRestored)
        await model.restore()
        #expect(model.isRestored)
        #expect(model.pendingTransaction == original)
        #expect(await runner.requests.isEmpty)
        #expect(!model.canApply)
        #expect(throws: MacSetupFailure.service("transaction-conflict")) {
            try model.configure(deviceID: "00008110-ffffffffffffffff",
                                options: MacSetupOptions(teamID: "ABCDE12345"))
        }
        #expect(model.pendingTransaction == original)
    }

    @Test func corruptJournalBlocksNewAuthority() async throws {
        let model = MacSetupModel(runner: HeldSetupRunner(), journal: ModelJournal(nil, corrupt: true))
        await model.restore()
        #expect(model.failure == .invalidResponse)
        #expect(throws: MacSetupFailure.invalidResponse) {
            try model.configure(deviceID: device,
                                options: MacSetupOptions(teamID: "ABCDE12345"))
        }
        #expect(!model.canApply)
    }

    @Test func onlyAProvenPreJournalApplyErrorCanRetryWithoutAStoredTransaction() async throws {
        for (code, stage, blocked) in [("device-disconnected" as String?, "preflight", false),
                                       ("device-disconnected" as String?, "install", true),
                                       (nil as String?, "preflight", true)] {
            let runner = HeldSetupRunner()
            let model = MacSetupModel(runner: runner, journal: ModelJournal(nil))
            await model.restore()
            let options = try MacSetupOptions(teamID: "ABCDE12345")
            try model.configure(deviceID: device, options: options)
            let identity = model.pendingTransaction
            model.preflight()
            #expect(await waitForRequests(1, runner))
            let preflight = try #require(await runner.requests.last)
            await runner.returnData(try response(preflight, stage: "preflight", outcome: "ready"))
            #expect(await waitForRequests(2, runner), "A ready preflight continues straight into apply.")
            let apply = try #require(await runner.requests.last)
            await runner.returnData(try response(apply, stage: stage, outcome: code == nil ? "ready" : "unknown", code: code))
            #expect(await waitUntilIdle(model))
            #expect(model.pendingTransaction == identity)
            #expect(!model.hasRecordedTransaction && !model.canApply)
            if blocked {
                #expect(model.failure == .invalidResponse)
                #expect(model.locksDevice)
            } else {
                #expect(model.failure == .service("device-disconnected"))
                #expect(!model.locksDevice)
                #expect(model.options == options)
                try model.configure(deviceID: device, options: options)
                model.preflight()
                #expect(await waitForRequests(3, runner))
                await runner.fail(.unavailable)
                #expect(await waitUntilIdle(model))
            }
        }
    }

    @Test func cancellationKeepsPhysicalApplyUntilReturnAndRestoresItsJournal() async throws {
        let runner = HeldSetupRunner()
        let journal = ModelJournal(nil)
        let model = MacSetupModel(runner: runner, journal: journal)
        await model.restore()
        let options = try MacSetupOptions(teamID: "ABCDE12345")
        try model.configure(deviceID: device, options: options)
        let original = try #require(model.pendingTransaction)
        model.apply()
        #expect(await runner.requests.isEmpty, "Apply requires an actual ready preflight for these options.")
        model.preflight()
        guard await waitForRequests(1, runner) else { Issue.record("Preflight did not reach the runner"); return }
        let preflight = try #require(await runner.requests.first)
        #expect(preflight.setupID == original.setupID)
        await runner.returnData(try response(preflight, stage: "preflight", outcome: "ready"))
        guard await waitForRequests(2, runner) else { Issue.record("Apply did not reach the runner"); return }
        let applying = try #require(await runner.requests.last)
        #expect(applying.options == options)
        #expect(applying.setupID == original.setupID)
        await journal.set(original)
        model.cancel()
        #expect(model.isBusy, "Cancellation cannot release a still-running external operation.")
        #expect(model.cancellationRequested)
        #expect(!model.canApply)
        model.apply()
        #expect(await runner.requests.count == 2)
        await runner.fail(.cancelled)
        #expect(await waitUntilIdle(model))
        #expect(model.pendingTransaction == original)
        #expect(model.failure == .cancelled)
        #expect(!model.canApply)
        #expect(model.snapshot == nil)
        model.status()
        guard await waitForRequests(3, runner) else { Issue.record("Explicit status did not reach the runner"); return }
        let status = try #require(await runner.requests.last)
        #expect(status.action == .status && status.setupID == original.setupID && status.options == nil)
        await runner.fail(.unavailable)
        #expect(await waitUntilIdle(model))
    }

    @Test func incompleteJournalCanOnlyStartWithANewTransaction() async throws {
        let runner = HeldSetupRunner()
        let original = try MacSetupTransactionIdentity(setupID: UUID(), deviceID: device, teamID: "ABCDE12345")
        let model = MacSetupModel(runner: runner, journal: ModelJournal(original))
        await model.restore()
        model.status()
        guard await waitForRequests(1, runner) else { Issue.record("Explicit status did not reach the runner"); return }
        let request = try #require(await runner.requests.last)
        await runner.returnData(try response(request, stage: "install", outcome: "unknown", code: "transaction-unknown"))
        #expect(await waitUntilIdle(model))
        #expect(model.snapshot?.stage == .install)
        #expect(model.snapshot?.outcome == .unknown)
        #expect(model.failure == .service("transaction-unknown"))
        #expect(!model.canApply && model.hasUnfinishedTransaction)
        #expect(await runner.requests.count == 1)
        try model.beginRestart(deviceID: original.deviceID, options: MacSetupOptions(teamID: original.teamID))
        guard await waitForRequests(2, runner) else { Issue.record("Fresh preflight did not reach the runner"); return }
        let restarted = try #require(await runner.requests.last)
        #expect(restarted.action == .preflight && restarted.setupID != original.setupID && restarted.options != nil)
        await runner.fail(.unavailable)
        #expect(await waitUntilIdle(model))
        #expect(model.pendingTransaction?.setupID != original.setupID)
        #expect(model.snapshot == nil, "A failed observation cannot leave apparently current progress evidence.")
    }

    @Test func restartingAnInstallWithAnAppAlreadyPresentSwitchesTheFreshTransactionToRenew() async throws {
        let runner = HeldSetupRunner()
        let original = try MacSetupTransactionIdentity(setupID: UUID(), deviceID: device,
                                                       mode: .install, teamID: "ABCDE12345")
        let journal = ModelJournal(original)
        let model = MacSetupModel(runner: runner, journal: journal)
        await model.restore()
        try model.beginRestart(deviceID: original.deviceID, options: MacSetupOptions(teamID: original.teamID))
        guard await waitForRequests(1, runner) else { Issue.record("Restart preflight did not reach the runner"); return }
        let installPreflight = try #require(await runner.requests.last)
        #expect(installPreflight.mode == .install)
        let newSetupID = try #require(installPreflight.setupID)
        await runner.returnData(try response(installPreflight, stage: "preflight", outcome: "unknown",
                                             code: "app-already-installed"))
        guard await waitForRequests(2, runner) else { Issue.record("Renewal preflight did not follow existing app discovery"); return }
        let renewPreflight = try #require(await runner.requests.last)
        #expect(renewPreflight.action == .preflight && renewPreflight.mode == .renew)
        #expect(renewPreflight.setupID == newSetupID)
        await runner.returnData(try response(renewPreflight, stage: "preflight", outcome: "ready"))
        guard await waitForRequests(3, runner) else { Issue.record("Fresh renewal apply did not follow preflight"); return }
        let apply = try #require(await runner.requests.last)
        #expect(apply.action == .apply && apply.mode == .renew && apply.setupID == newSetupID)
        let restartedIdentity = try MacSetupTransactionIdentity(setupID: newSetupID, deviceID: original.deviceID,
                                                                mode: .renew, teamID: original.teamID)
        await journal.set(restartedIdentity)
        await runner.returnData(try response(apply, stage: "install", outcome: "unknown", code: "device-disconnected"),
                                action: .apply)
        #expect(await waitUntilIdle(model))
        #expect(model.pendingTransaction == restartedIdentity)
        #expect(model.hasUnfinishedTransaction)
        #expect(model.failure == .service("device-disconnected"))
    }

    @Test func restoredSetupCannotBeHiddenByDeviceSelection() async throws {
        let original = try MacSetupTransactionIdentity(setupID: UUID(), deviceID: device, teamID: "ABCDE12345")
        let runner = HeldSetupRunner()
        let setup = MacSetupModel(runner: runner, journal: ModelJournal(original))
        let app = MacAppModel(live: SetupReadOnlyChecker(), setup: setup)
        await app.restoreSetup()
        app.checkEnvironment()
        for _ in 0..<200 where app.busy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(app.ready)
        #expect(app.route == .deviceDetail && app.selectedID == original.deviceID)
        app.openDevices(firstInstall: false)
        app.select("00008110-ffffffffffffffff")
        app.refreshDevices()
        app.navigate(.deviceList)
        #expect(app.route == .deviceDetail && app.selectedID == original.deviceID)
        #expect(await runner.requests.isEmpty)
        setup.status()
        guard await waitForRequests(1, runner) else { Issue.record("Status did not reach the runner"); return }
        #expect(app.busy)
        app.cancel()
        #expect(app.busy, "Cancelling a read-only check cannot release setup's physical operation.")
        await runner.fail(.unavailable)
        #expect(await waitUntilIdle(setup))
        #expect(app.selectedID == original.deviceID)
    }

    @Test func corruptJournalOpensTheBlockedSetupPage() async {
        let setup = MacSetupModel(runner: HeldSetupRunner(), journal: ModelJournal(nil, corrupt: true))
        let app = MacAppModel(live: SetupReadOnlyChecker(), setup: setup)
        await app.restoreSetup()
        #expect(app.route == .install)
        #expect(setup.locksDevice)
        app.navigate(.startup)
        #expect(app.route == .startup)
        app.navigate(.install)
        #expect(app.route == .install, "A corrupt transaction must remain reachable without environment readiness.")
    }

    @Test func readyPreflightContinuesIntoApplyWithoutASecondClick() async throws {
        let runner = HeldSetupRunner()
        let setup = MacSetupModel(runner: runner, journal: ModelJournal(nil))
        let app = MacAppModel(live: SetupReadOnlyChecker(), setup: setup)
        await app.restoreSetup()
        app.checkEnvironment()
        for _ in 0..<200 where app.busy { try await Task.sleep(for: .milliseconds(5)) }
        try setup.configure(deviceID: device, options: MacSetupOptions(teamID: "ABCDE12345"))
        setup.preflight()
        guard await waitForRequests(1, runner) else { Issue.record("Preflight did not reach the runner"); return }
        let request = try #require(await runner.requests.last)
        await runner.returnData(try response(request, stage: "preflight", outcome: "ready"))
        guard await waitForRequests(2, runner) else { Issue.record("Apply did not follow the ready preflight"); return }
        let apply = try #require(await runner.requests.last)
        #expect(apply.action == .apply && apply.setupID == request.setupID && apply.mode == .install)
        app.openDevices(firstInstall: true)
        #expect(app.route != .deviceList, "The device list stays locked while apply runs.")
        await runner.fail(.unavailable)
        #expect(await waitUntilIdle(setup))
    }

    @Test func rescanAfterSwappingPhonesLeavesTheUnfinishedPhoneForTheNewOne() async throws {
        let original = try MacSetupTransactionIdentity(setupID: UUID(), deviceID: device, teamID: "ABCDE12345")
        let journal = ModelJournal(original)
        let setup = MacSetupModel(runner: HeldSetupRunner(), journal: journal)
        let swapped = "00008110-ffffffffffffffff"
        let app = MacAppModel(live: SwappedPhoneChecker(phoneID: swapped, phoneName: "Lilian’s iPhone"), setup: setup,
                              preferences: UserDefaults(suiteName: "gofly.tests.\(UUID().uuidString)")!)
        await app.restoreSetup()
        app.checkEnvironment()
        for _ in 0..<200 where app.busy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(app.devicePageState == .restartRequired)
        app.refreshDevices()
        for _ in 0..<400 where app.busy || app.inspection == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(app.selectedID == swapped)
        #expect(app.devicePageState == .readyToInstall, "The new phone starts fresh instead of showing Start over.")
        #expect(!setup.hasUnfinishedTransaction)
        #expect(try await journal.readPendingTransaction() == original, "Only the producer's next apply abandons the old journal.")
        #expect(app.sidebarDevices.map(\.displayName) == ["Lilian’s iPhone"])
    }

    @Test func startOverKeepsThePhoneInTheSidebar() async throws {
        let runner = HeldSetupRunner()
        let original = try MacSetupTransactionIdentity(setupID: UUID(), deviceID: device, teamID: "ABCDE12345")
        let setup = MacSetupModel(runner: runner, journal: ModelJournal(original))
        let app = MacAppModel(live: SetupReadOnlyChecker(), setup: setup,
                              preferences: UserDefaults(suiteName: "gofly.tests.\(UUID().uuidString)")!)
        await app.restoreSetup()
        #expect(app.sidebarDevices.map(\.id) == [device])
        app.restartInterruptedSetup()
        guard await waitForRequests(1, runner) else { Issue.record("Restart preflight did not reach the runner"); return }
        #expect(!setup.hasUnfinishedTransaction && setup.isBusy)
        #expect(app.sidebarDevices.map(\.id) == [device], "The phone being restarted stays listed.")
        await runner.fail(.unavailable)
        #expect(await waitUntilIdle(setup))
    }

    @Test func onlyObservedCompleteJournalCanReleaseTheLocalSelection() async throws {
        let runner = HeldSetupRunner()
        let original = try MacSetupTransactionIdentity(setupID: UUID(), deviceID: device, teamID: "ABCDE12345")
        let journal = ModelJournal(original)
        let setup = MacSetupModel(runner: runner, journal: journal)
        await setup.restore()
        setup.resetSelection()
        #expect(setup.pendingTransaction == original, "The header alone cannot retire an unresolved transaction.")
        setup.status()
        guard await waitForRequests(1, runner) else { Issue.record("Status did not reach the runner"); return }
        let request = try #require(await runner.requests.last)
        var wire = try #require(JSONSerialization.jsonObject(with: response(request, stage: "complete", outcome: "confirmed")) as? [String: Any])
        // This is a protocol projection test, never a runtime/App/native success adapter.
        wire["payload"] = ["stage": "complete", "outcome": "confirmed",
                           "proof": ["installationConfirmed": true, "pairingImported": true, "supportObserved": true],
                           "app": ["bundleID": "com.neven.gofly.abcde12345", "build": "19",
                                   "profileSHA256": String(repeating: "1", count: 64),
                                   "executableSHA256": String(repeating: "2", count: 64)],
                           "teamID": "ABCDE12345", "expiresAt": "2030-01-01T00:00:00Z",
                           "receiptSHA256": String(repeating: "3", count: 64)]
        await runner.returnData(try JSONSerialization.data(withJSONObject: wire))
        #expect(await waitUntilIdle(setup))
        #expect(setup.snapshot?.isComplete == true)
        setup.resetSelection()
        #expect(setup.pendingTransaction == nil && !setup.hasRecordedTransaction)
        #expect(try await journal.readPendingTransaction() == original, "UI retirement must not archive or erase the authoritative journal.")
        try setup.configure(deviceID: "00008110-ffffffffffffffff",
                            options: MacSetupOptions(teamID: "ABCDE12345"))
        #expect(setup.pendingTransaction?.deviceID == "00008110-ffffffffffffffff")
        #expect(!setup.canApply, "The new choice still requires its own actual preflight.")
        setup.preflight()
        guard await waitForRequests(2, runner) else { Issue.record("New preflight did not reach the runner"); return }
        let next = try #require(await runner.requests.last)
        await runner.returnData(try response(next, stage: "preflight", outcome: "ready"))
        guard await waitForRequests(3, runner) else { Issue.record("New apply did not reach the runner"); return }
        await runner.fail(.unavailable)
        #expect(await waitUntilIdle(setup))
        #expect(setup.pendingTransaction == original && setup.hasRecordedTransaction)
        #expect(setup.failure == .service("transaction-conflict"))
        #expect(setup.snapshot == nil && !setup.canApply)
        #expect(await runner.requests.count == 3, "Rebinding an unchanged header does not automatically query either device.")
    }

    @Test func inFlightProgressReadsTheActualJournalWithoutCompletingTheApply() async throws {
        let runner = HeldSetupRunner()
        let journal = ModelJournal(nil)
        let setup = MacSetupModel(runner: runner, journal: journal)
        await setup.restore()
        try setup.configure(deviceID: device, options: MacSetupOptions(teamID: "ABCDE12345"))
        let original = try #require(setup.pendingTransaction)
        setup.preflight()
        guard await waitForRequests(1, runner) else { Issue.record("Preflight did not reach the runner"); return }
        let preflight = try #require(await runner.requests.last)
        await runner.returnData(try response(preflight, stage: "preflight", outcome: "ready"))
        guard await waitForRequests(2, runner) else { Issue.record("Apply did not reach the runner"); return }
        await journal.set(original)
        guard await waitForRequests(3, runner, attempts: 800) else {
            await runner.fail(.cancelled)
            _ = await waitUntilIdle(setup)
            Issue.record("No read-only progress observation reached the runner while apply was held")
            return
        }
        let status = try #require(await runner.requests.last)
        #expect(status.action == .status && status.setupID == original.setupID && status.options == nil)
        await runner.returnData(try response(status, stage: "install", outcome: "unknown"), action: .status)
        for _ in 0..<100 where setup.progressStage == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(setup.progressStage == .install)
        #expect(setup.isBusy && setup.snapshot == nil && !setup.canApply)
        guard await waitForRequests(4, runner, attempts: 800) else {
            setup.cancel()
            await runner.fail(.cancelled)
            _ = await waitUntilIdle(setup)
            Issue.record("Second progress observation did not reach the runner")
            return
        }
        let heldStatus = try #require(await runner.requests.last)
        setup.cancel()
        #expect(setup.isBusy)
        await runner.fail(.cancelled)
        try await Task.sleep(for: .milliseconds(20))
        #expect(setup.isBusy, "The read-only observer must also physically return before releasing the fence.")
        await runner.returnData(try response(heldStatus, stage: "handoff", outcome: "unknown"), action: .status)
        #expect(await waitUntilIdle(setup))
        #expect(setup.pendingTransaction == original && setup.failure == .cancelled)
        #expect(setup.progressStage == nil, "A late cancelled observer cannot publish new progress.")
    }


    @Test func legacySignedOnlyRenewCanStartAFullRenewFromDevicePage() async throws {
        let runner = HeldSetupRunner()
        let original = try MacSetupTransactionIdentity(setupID: UUID(), deviceID: device, mode: .renew, teamID: "ABCDE12345")
        let setup = MacSetupModel(runner: runner, journal: ModelJournal(original))
        let app = MacAppModel(live: RenewChecker(), setup: setup)
        await app.restoreSetup()
        setup.status()
        #expect(await waitForRequests(1, runner))
        let status = try #require(await runner.requests.last)
        var root = try #require(JSONSerialization.jsonObject(with: response(status, stage: "complete", outcome: "confirmed")) as? [String: Any])
        var payload = try #require(root["payload"] as? [String: Any])
        payload["proof"] = ["installationConfirmed": true, "pairingImported": false, "supportObserved": false]
        payload["app"] = ["bundleID": "com.neven.gofly.abcde12345", "build": "20",
                          "profileSHA256": String(repeating: "a", count: 64),
                          "executableSHA256": String(repeating: "b", count: 64)]
        payload["teamID"] = "ABCDE12345"
        payload["receiptSHA256"] = String(repeating: "c", count: 64)
        root["payload"] = payload
        await runner.returnData(try JSONSerialization.data(withJSONObject: root), action: .status)
        #expect(await waitUntilIdle(setup))
        #expect(setup.snapshot?.isComplete == false)
        app.checkEnvironment()
        #expect(await waitForAppCheck(app))
        app.openDevices(firstInstall: false)
        #expect(await waitForAppCheck(app))
        app.select(device)
        app.inspectSelected()
        #expect(await waitForAppCheck(app))
        app.startRenew()
        #expect(await waitForRequests(2, runner))
        let preflight = try #require(await runner.requests.last)
        #expect(preflight.action == .preflight && preflight.mode == .renew)
        #expect(preflight.setupID != original.setupID)
        await runner.fail(.cancelled)
        #expect(await waitUntilIdle(setup))
    }

    @Test func inspectionDoesNotStartRenewAndManualStartsOne() async throws {
        let runner = HeldSetupRunner()
        let journal = ModelJournal(nil)
        let setup = MacSetupModel(runner: runner, journal: journal)
        let app = MacAppModel(live: RenewChecker(), setup: setup)
        await app.restoreSetup()
        app.checkEnvironment()
        #expect(await waitForAppCheck(app))
        app.openDevices(firstInstall: false)
        #expect(await waitForAppCheck(app))
        app.select(device)
        app.inspectSelected()
        #expect(await waitForAppCheck(app))
        #expect(await runner.requests.isEmpty, "Selecting a device must not write to the phone.")

        app.startRenew()
        guard await waitForRequests(1, runner) else {
            Issue.record("Manual renew preflight did not reach the runner")
            return
        }
        let preflight = try #require(await runner.requests.last)
        #expect(preflight.mode == .renew && preflight.action == .preflight)
        await runner.returnData(try response(preflight, stage: "preflight", outcome: "ready"), action: .preflight)
        guard await waitForRequests(2, runner) else {
            Issue.record("Manual renew apply did not reach the runner")
            return
        }
        let apply = try #require(await runner.requests.last)
        #expect(apply.mode == .renew && apply.action == .apply)

        app.startRenew()
        #expect(await runner.requests.count == 2)
        await runner.fail(.cancelled)
        #expect(await waitUntilIdle(setup))
    }

    @Test func confirmedRenewRecordedAsCompletedJournalIsNotAnIntegrityFailure() async throws {
        let runner = HeldSetupRunner()
        let receipt = String(repeating: "c", count: 64)
        let completed = MacSetupSnapshot(
            mode: .renew, stage: .complete, outcome: .confirmed, appBuild: "32", teamID: "ABCDE12345",
            expiresAt: "2027-10-17T09:06:10Z", receiptSHA256: receipt, installationConfirmed: true,
            pairingImported: true, supportObserved: true, errorCode: nil)
        let setup = MacSetupModel(runner: runner, journal: CompletedJournal(completed))
        let app = MacAppModel(live: RenewChecker(), setup: setup)
        await app.restoreSetup()
        app.checkEnvironment()
        #expect(await waitForAppCheck(app))
        app.openDevices(firstInstall: false)
        #expect(await waitForAppCheck(app))
        app.select(device)
        app.inspectSelected()
        #expect(await waitForAppCheck(app))
        app.startRenew()
        guard await waitForRequests(1, runner) else { Issue.record("Renew preflight did not start"); return }
        let preflight = try #require(await runner.requests.last)
        await runner.returnData(try response(preflight, stage: "preflight", outcome: "ready"), action: .preflight)
        guard await waitForRequests(2, runner) else { Issue.record("Renew apply did not start"); return }
        let apply = try #require(await runner.requests.last)
        var done = try #require(JSONSerialization.jsonObject(with: response(apply, stage: "complete", outcome: "confirmed")) as? [String: Any])
        var payload = try #require(done["payload"] as? [String: Any])
        payload["proof"] = ["installationConfirmed": true, "pairingImported": true, "supportObserved": true]
        payload["expiresAt"] = "2027-10-17T09:06:10Z"
        payload["receiptSHA256"] = receipt
        payload["app"] = ["bundleID": "com.neven.gofly.abcde12345", "build": "32",
                          "executableSHA256": String(repeating: "a", count: 64),
                          "profileSHA256": String(repeating: "b", count: 64)]
        done["payload"] = payload
        await runner.returnData(try JSONSerialization.data(withJSONObject: done), action: .apply)
        #expect(await waitUntilIdle(setup))
        #expect(setup.failure == nil)
        #expect(setup.snapshot?.isComplete == true)
    }

    @Test func manualRenewStartsOneOperationAndDoesNotOverlap() async throws {
        let runner = HeldSetupRunner()
        let setup = MacSetupModel(runner: runner, journal: ModelJournal(nil))
        let app = MacAppModel(live: RenewChecker(), setup: setup)
        await app.restoreSetup()
        app.checkEnvironment()
        #expect(await waitForAppCheck(app))
        app.openDevices(firstInstall: false)
        #expect(await waitForAppCheck(app))
        app.select(device)
        app.inspectSelected()
        #expect(await waitForAppCheck(app))
        #expect(await runner.requests.isEmpty)
        app.startRenew()
        guard await waitForRequests(1, runner) else {
            Issue.record("Manual renew preflight did not reach the runner")
            return
        }
        app.startRenew()
        #expect(await runner.requests.count == 1)
        let preflight = try #require(await runner.requests.last)
        await runner.returnData(try response(preflight, stage: "preflight", outcome: "ready"), action: .preflight)
        guard await waitForRequests(2, runner) else {
            Issue.record("Manual renew apply did not reach the runner")
            return
        }
        app.startRenew()
        #expect(await runner.requests.count == 2)
        await runner.fail(.cancelled)
        #expect(await waitUntilIdle(setup))
    }

    @Test func wifiRenewKeepsNetworkTransportAcrossPreflightAndApply() async throws {
        let runner = HeldSetupRunner()
        let setup = MacSetupModel(runner: runner, journal: ModelJournal(nil))
        await setup.restore()
        try setup.configure(deviceID: device, options: MacSetupOptions(teamID: "ABCDE12345"),
                            mode: .renew, transport: .wifi)
        setup.preflight()
        guard await waitForRequests(1, runner) else { Issue.record("Wi-Fi preflight did not reach the runner"); return }
        let preflight = try #require(await runner.requests.first)
        #expect(preflight.transport == .wifi)
        await runner.returnData(try response(preflight, stage: "preflight", outcome: "ready"), action: .preflight)
        guard await waitForRequests(2, runner) else { Issue.record("Wi-Fi apply did not follow preflight"); return }
        let apply = try #require(await runner.requests.last)
        #expect(apply.action == .apply && apply.mode == .renew && apply.transport == .wifi)
        await runner.fail(.cancelled)
        #expect(await waitUntilIdle(setup))
    }


    @Test func bridgeStatusReaderReturnsOnlyTheCurrentJournalHeader() async throws {
        let id = UUID()
        let reader = BridgeStatusJournalReader(runner: StatusRunner(setupID: id))
        let pendingTransaction = try await reader.readPendingTransaction()
        #expect(pendingTransaction?.setupID == id)
        #expect(pendingTransaction?.deviceID == device)
        #expect(pendingTransaction?.mode == .install)
        #expect(pendingTransaction?.teamID == "ABCDE12345")
    }

    @Test func bridgeStatusReaderMapsMissingJournalToNoContinuation() async throws {
        let reader = BridgeStatusJournalReader(runner: MissingStatusRunner())
        #expect(try await reader.readPendingTransaction() == nil)
    }

    @Test func bridgeStatusReaderMapsTransactionUnknownResponseToNoContinuation() async throws {
        let reader = BridgeStatusJournalReader(runner: TransactionUnknownStatusRunner())
        #expect(try await reader.readPendingTransaction() == nil)
    }

    @Test @MainActor func completedJournalDoesNotLockRetainedState() async throws {
        let runner = CompletedLegacyStatusRunner()
        let reader = BridgeStatusJournalReader(runner: runner)
        #expect(try await reader.readPendingTransaction() == nil)
        let model = MacSetupModel(runner: runner, journal: reader)
        await model.restore()
        #expect(model.pendingTransaction == nil)
        #expect(!model.locksDevice)
        #expect(model.lastCompleted?.expiresAt == "2027-10-17T09:06:10Z")
    }

    private func waitForAppCheck(_ app: MacAppModel, attempts: Int = 400) async -> Bool {
        for _ in 0..<attempts {
            if !app.isChecking { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private func waitForRequests(_ count: Int, _ runner: HeldSetupRunner, attempts: Int = 200) async -> Bool {
        for _ in 0..<attempts {
            if await runner.requests.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private func waitUntilIdle(_ model: MacSetupModel) async -> Bool {
        for _ in 0..<200 {
            if !model.isBusy { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private func response(_ request: MacSetupRequest, stage: String, outcome: String, code: String? = nil) throws -> Data {
        var value: [String: Any] = [
            "action": request.action.rawValue,
            "requestID": request.requestID.uuidString, "setupID": request.setupID!.uuidString,
            "deviceID": request.deviceID!, "transport": request.transport?.rawValue ?? "usb",
            "status": code == nil ? "ok" : "error",
            "payload": ["stage": stage, "outcome": outcome,
                        "teamID": "ABCDE12345",
                        "proof": ["installationConfirmed": false, "pairingImported": false, "supportObserved": false]]
        ]
        if let code { value["code"] = code }
        return try JSONSerialization.data(withJSONObject: value)
    }
}

private struct StatusRunner: MacSetupRunning {
    let setupID: UUID
    func run(_ request: MacSetupRequest) async throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "requestID": request.requestID.uuidString, "action": "status",
            "setupID": setupID.uuidString, "deviceID": "00008110-001234567890abcd", "mode": "install",
            "status": "ok",
            "payload": ["stage": "install", "outcome": "inProgress",
                        "teamID": "ABCDE12345",
                        "proof": ["installationConfirmed": false, "pairingImported": false, "supportObserved": false]]
        ])
    }
}

private struct MissingStatusRunner: MacSetupRunning {
    func run(_ request: MacSetupRequest) async throws -> Data {
        throw MacSetupFailure.service("transaction-unknown")
    }
}

private struct TransactionUnknownStatusRunner: MacSetupRunning {
    func run(_ request: MacSetupRequest) async throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "requestID": request.requestID.uuidString, "action": "status", "status": "error",
            "code": "transaction-unknown",
        ])
    }
}

private struct CompletedLegacyStatusRunner: MacSetupRunning {
    func run(_ request: MacSetupRequest) async throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "requestID": request.requestID.uuidString, "action": "status", "status": "ok",
            "setupID": "4b21f244-9f20-4ece-b1ae-7811f6ff6b3d",
            "deviceID": "00008110-001234567890abcd",
            "payload": [
                "stage": "complete", "outcome": "confirmed",
                "proof": ["installationConfirmed": true, "pairingImported": true,
                          "supportObserved": true],
                "app": ["bundleID": "com.neven.gofly.abcde12345", "build": "22",
                        "executableSHA256": String(repeating: "a", count: 64),
                        "profileSHA256": String(repeating: "b", count: 64)],
                "teamID": "ABCDE12345", "expiresAt": "2027-10-17T09:06:10Z",
                "receiptSHA256": String(repeating: "c", count: 64),
            ],
        ])
    }
}

private struct RenewChecker: MacChecking {
    func check(_ request: CheckRequest) async throws -> Data {
        let payload: [String: Any]
        switch request.action {
        case .environment:
            payload = ["ready": true, "checks": [], "teams": [["teamID": "ABCDE12345", "teamName": "Test Team", "isFreeProvisioningTeam": true]], "xcodeVersion": "27.1"]
        case .devices:
            payload = ["devices": [["id": "00008110-001234567890abcd", "name": "iPhone", "transport": "usb"]]]
        case .inspect:
            payload = ["device": ["id": "00008110-001234567890abcd", "name": "iPhone", "transport": "usb"],
                       "developerMode": true, "installed": true, "vpnInstalled": true]
        case .registeredDevices:
            payload = ["devices": []]
        }
        return try JSONSerialization.data(withJSONObject: [
            "requestID": request.requestID, "status": "ok", "payload": payload
        ])
    }
}

/// A Mac with one USB phone attached that has no GoFly yet.
private struct SwappedPhoneChecker: MacChecking {
    let phoneID: String
    let phoneName: String
    func check(_ request: CheckRequest) async throws -> Data {
        let payload: [String: Any]
        switch request.action {
        case .devices:
            payload = ["devices": [["id": phoneID, "name": "", "transport": "usb"]]]
        case .inspect:
            payload = ["device": ["id": phoneID, "name": phoneName, "transport": "usb"],
                       "developerMode": true, "installed": false, "vpnInstalled": false]
        default:
            return try await SetupReadOnlyChecker().check(request)
        }
        return try JSONSerialization.data(withJSONObject: ["requestID": request.requestID,
                                                           "status": "ok", "payload": payload])
    }
}

private struct SetupReadOnlyChecker: MacChecking {
    func check(_ request: CheckRequest) async throws -> Data {
        guard request.action == .environment else { throw CheckFailure.unavailable }
        return try JSONSerialization.data(withJSONObject: ["requestID": request.requestID,
            "status": "ok", "payload": ["ready": true, "checks": [], "teams": [["teamID": "ABCDE12345", "teamName": "Test Team", "isFreeProvisioningTeam": true]], "xcodeVersion": "27.1"]])
    }
}

private actor ModelJournal: MacSetupJournalReading {
    var value: MacSetupTransactionIdentity?
    let corrupt: Bool
    init(_ value: MacSetupTransactionIdentity?, corrupt: Bool = false) { self.value = value; self.corrupt = corrupt }
    func set(_ value: MacSetupTransactionIdentity?) { self.value = value }
    func readPendingTransaction() async throws -> MacSetupTransactionIdentity? {
        if corrupt { throw MacSetupFailure.invalidResponse }
        return value
    }
}

private actor CompletedJournal: MacSetupJournalReading {
    let completed: MacSetupSnapshot
    init(_ completed: MacSetupSnapshot) { self.completed = completed }
    func readPendingTransaction() async throws -> MacSetupTransactionIdentity? { nil }
    func readState() async throws -> MacSetupJournalState {
        MacSetupJournalState(pendingTransaction: nil, completed: completed)
    }
}

private actor HeldSetupRunner: MacSetupRunning {
    private(set) var requests: [MacSetupRequest] = []
    private var pending: [(MacSetupRequest, CheckedContinuation<Data, any Error>)] = []
    func run(_ request: MacSetupRequest) async throws -> Data {
        requests.append(request)
        return try await withCheckedThrowingContinuation { pending.append((request, $0)) }
    }
    func fail(_ error: MacSetupFailure) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().1.resume(throwing: error)
    }
    func returnData(_ data: Data, action: MacSetupAction? = nil) {
        guard let index = pending.firstIndex(where: { action == nil || $0.0.action == action }) else { return }
        pending.remove(at: index).1.resume(returning: data)
    }
}
