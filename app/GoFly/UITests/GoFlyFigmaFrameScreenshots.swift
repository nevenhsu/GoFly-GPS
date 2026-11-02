import Foundation
import UIKit
import XCTest

/// Captures only frames with a deterministic local fixture. Every omitted Figma
/// frame is listed in the manifest with its reason, so a missing screenshot is
/// never confused with a verified comparison.
@MainActor
final class GoFlyFigmaFrameScreenshots: XCTestCase {
    private let supportedFrames: Set<String> = [
        "R01", "R02", "R03", "R04", "R04.a", "R05", "R07", "R08",
        "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "B10", "B11",
        "C1", "C2", "C3", "C4",
        "D1", "D2", "D2.a", "D3", "D4", "D5", "D6", "D7", "D8", "D10", "D10.a",
        "D11", "D12", "D13", "D14", "D15", "D16", "D17", "D18", "D19", "D20", "D21", "D22", "D23",
        "E1", "E1.a", "E2", "E2.a", "E3", "E4", "E5",
        "F1", "F1.a", "F1.b", "F4", "F5", "F6", "F6.a", "F7", "F8", "F9"
    ]

    func testB1MapCanvasFillsTheWindowInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", "B1",
                "-gofly-ui-appearance", appearance,
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launch()
            waitForFixture(app, frame: "B1")

            let window = app.windows.firstMatch
            let map = app.descendants(matching: .any).matching(identifier: "map.canvas").firstMatch
            XCTAssertTrue(map.waitForExistence(timeout: 10))
            XCTAssertLessThanOrEqual(map.frame.minX, window.frame.minX + 1)
            XCTAssertLessThanOrEqual(map.frame.minY, window.frame.minY + 1)
            XCTAssertGreaterThanOrEqual(map.frame.maxX, window.frame.maxX - 1)
            XCTAssertGreaterThanOrEqual(map.frame.maxY, window.frame.maxY - 1)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "B1-\(appearance)-full-bleed-map"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
        #endif
    }

    func testB2PasteButtonSnapshotsInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let output = repositoryRoot.appendingPathComponent(
            "work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", "B2",
                "-gofly-ui-appearance", appearance,
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launch()
            waitForFixture(app, frame: "B2")

            let paste = app.descendants(matching: .any)["map.searchPaste"]
            XCTAssertTrue(paste.waitForExistence(timeout: 10))
            XCTAssertEqual(paste.label, "貼上")

            let screenshot = app.screenshot()
            try screenshot.pngRepresentation.write(
                to: output.appendingPathComponent("B2-\(appearance).png"), options: .atomic)
            app.terminate()
        }
        #endif
    }

    func testPasteButtonsPreserveExistingSearchHandling() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        for frame in ["B2", "B3"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", frame,
                "-gofly-ui-appearance", "light",
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launchArguments += ["-gofly-ui-pasteboard", "999, 999"]
            app.launch()
            waitForFixture(app, frame: frame)

            let paste = app.buttons[frame == "B2" ? "map.searchPaste" : "search.paste"]
            XCTAssertTrue(paste.waitForExistence(timeout: 10))
            paste.tap()

            if frame == "B2" {
                XCTAssertTrue(app.descendants(matching: .any)["map.searchPasteWarning"]
                    .waitForExistence(timeout: 10))
            } else {
                let query = app.textFields["search.query"]
                XCTAssertTrue(query.waitForExistence(timeout: 10))
                XCTAssertEqual(query.value as? String, "999, 999")
            }
            app.terminate()
        }
        #endif
    }

    func testExecutionHeadersUseSemanticTextColorsInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let output = repositoryRoot.appendingPathComponent(
            "work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for frame in ["D6", "D7", "D10", "D10.a", "E2", "E2.a", "E4"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                app.launch()
                waitForFixture(app, frame: frame)
                prepareAdditionalFixture(app, frame: frame)

                let header = app.descendants(matching: .any)
                    .matching(identifier: "execution.header").firstMatch
                XCTAssertTrue(header.waitForExistence(timeout: 20), "execution header missing for \(frame)-\(appearance)")

                if frame == "D7" {
                    let confirm = app.buttons["route.speed.confirm"]
                    let lowerSliderLabel = app.staticTexts["120 km/h"]
                    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
                    XCTAssertTrue(lowerSliderLabel.exists)
                    let upperGap = confirm.frame.minY - lowerSliderLabel.frame.maxY
                    let bottomGap = app.windows.firstMatch.frame.maxY - confirm.frame.maxY
                    XCTAssertGreaterThanOrEqual(upperGap, 16)
                    XCTAssertLessThanOrEqual(upperGap, 32)
                    XCTAssertGreaterThanOrEqual(bottomGap, 36)
                    XCTAssertLessThanOrEqual(bottomGap, 44)
                } else if frame == "D10" {
                    let notice = app.descendants(matching: .any)["map.continuationNotice"]
                    XCTAssertTrue(notice.exists)
                    XCTAssertEqual(app.buttons["map.continuationNotice.action"].label, "繼續")
                    XCTAssertTrue(app.buttons["map.continuationNotice.action"].isEnabled)
                } else if frame == "D10.a" {
                    XCTAssertFalse(app.descendants(matching: .any)["map.continuationNotice"].exists)
                    let resume = app.buttons["route.resume"]
                    XCTAssertTrue(resume.exists)
                    XCTAssertTrue(resume.isEnabled)
                }

                let screenshot = app.screenshot()
                try screenshot.pngRepresentation.write(
                    to: output.appendingPathComponent("\(frame)-\(appearance).png"), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "\(frame)-\(appearance)-execution-header-colors"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
        #endif
    }

    func testSectionAFramesInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let output = repositoryRoot.appendingPathComponent(
            "work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for frame in ["R01", "R02", "R03", "R04", "R04.a", "R05", "R07", "R08"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                if frame == "R04" { app.launchArguments.append("-gofly-ui-vpn-static") }
                if frame == "R04.a" { app.launchArguments.append("-gofly-ui-unreachable") }
                app.launch()
                waitForFixture(app, frame: frame)

                if frame == "R01" {
                    XCTAssertTrue(app.descendants(matching: .any)["setup.preparing.progress"]
                        .waitForExistence(timeout: 5))
                }
                if frame == "R02" || frame == "R03" {
                    let title = app.staticTexts["onboarding.location.title"]
                    let status = app.descendants(matching: .any)["onboarding.location.status"]
                    XCTAssertTrue(title.waitForExistence(timeout: 10))
                    XCTAssertTrue(status.waitForExistence(timeout: 5))
                    XCTAssertEqual(app.navigationBars.count, 0, "Location permission screens have no navigation bar in Figma.")
                    XCTAssertEqual(title.frame.minY, 348, accuracy: 18)
                    XCTAssertEqual(status.frame.minY, 466, accuracy: 20)
                    let primary = app.buttons["onboarding.location.allow"]
                    XCTAssertEqual(primary.frame.minX, 16, accuracy: 1)
                    XCTAssertEqual(primary.frame.width, app.windows.firstMatch.frame.width - 32, accuracy: 1)
                    if frame == "R03" {
                        XCTAssertEqual(title.label, "已允許使用定位")
                        XCTAssertEqual(status.label, "目前權限：使用 App 期間・已允許")
                    }
                }
                if frame == "R04.a" {
                    let primary = app.buttons["onboarding.vpn.check"]
                    let connect = app.buttons["onboarding.vpn.failure.vpn"]
                    let status = app.descendants(matching: .any)["onboarding.vpn.status"]
                    XCTAssertTrue(connect.waitForExistence(timeout: 10))
                    XCTAssertTrue(status.waitForExistence(timeout: 5))
                    XCTAssertEqual(primary.label, "檢查連線")
                    XCTAssertEqual(connect.label, "連線")
                    XCTAssertEqual(status.label, "連線錯誤")
                }
                if frame == "R05" {
                    app.buttons["onboarding.vpn.help.open"].tap()
                    XCTAssertTrue(app.buttons["onboarding.vpn.help.step1.action"].waitForExistence(timeout: 10))
                    XCTAssertTrue(app.descendants(matching: .any)["onboarding.vpn.help.back"].exists)
                }
                if frame == "R08" {
                    let title = app.staticTexts["setup.blocked.title"]
                    let message = app.staticTexts["setup.blocked.identity"]
                    XCTAssertTrue(message.exists)
                    XCTAssertEqual(title.label, "需要完成設定")
                    XCTAssertEqual(message.label,
                        "GoFly App 與套件不相符。請將這支 iPhone 連接 Mac App，以修復設定。")
                    XCTAssertFalse(app.buttons["setup.retry"].exists)
                    XCTAssertEqual(title.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 1)
                }

                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                let screenshot = app.screenshot()
                try screenshot.pngRepresentation.write(
                    to: output.appendingPathComponent("\(frame)-\(appearance).png"), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "\(frame)-\(appearance)-section-A"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
        #endif
    }

    func testC4FavoriteBulkDeleteShowsUndoSnackbarInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", "C4",
                "-gofly-ui-appearance", appearance,
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launch()
            waitForFixture(app, frame: "C4")
            prepareInteractiveFixture(app, frame: "C4")
            XCTAssertTrue(app.buttons["snackbar.action"].waitForExistence(timeout: 10))

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "C4-\(appearance)-delete-undo"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
        #endif
    }

    func testD22FavoriteRouteBulkDeleteShowsUndoSnackbarInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", "D22",
                "-gofly-ui-appearance", appearance,
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launch()
            waitForFixture(app, frame: "D22")
            prepareInteractiveFixture(app, frame: "D22")

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "D22-\(appearance)-delete-undo"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
        #endif
    }

    func testF1aStopFailureFixtureShowsResetAction() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-frame", "F1.a",
            "-gofly-ui-appearance", "light",
            "-gofly-ui-device-state", "stop-failure",
            "-gofly-ui-preferences-language", "zh-Hant",
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
        ]
        app.launch()
        waitForFixture(app, frame: "F1.a")
        XCTAssertTrue(app.buttons["service.reset"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "F1.a-light-stop-failure"
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }

    func testCaptureSharedToastFramesInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Shared toast frame fixtures run only in the iOS Simulator.")
        #else
        continueAfterFailure = false
        let frames = ["B7", "B10", "D8", "F1.b"]
        let output = repositoryRoot.appendingPathComponent(
            "work/gofly-ios-figma04/screenshots/ticket04-feedback-frames", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for frame in frames {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                switch frame {
                case "B7": app.launchArguments += ["-gofly-ui-device-state", "unconfirmed-point"]
                case "B10": app.launchArguments.append("-gofly-ui-wifi-disconnected")
                case "D8": app.launchArguments += ["-gofly-ui-route-outcome", "planningFailed"]
                default: break
                }
                app.launch()
                waitForFixture(app, frame: frame)
                prepareInteractiveFixture(app, frame: frame)
                prepareAdditionalFixture(app, frame: frame)

                let screenshot = app.screenshot()
                let filename = "\(frame)-\(appearance).png"
                try screenshot.pngRepresentation.write(to: output.appendingPathComponent(filename), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "ticket-04-\(filename)"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }

        let rows = frames.flatMap { frame in
            ["light", "dark"].map { appearance in
                let filename = "\(frame)-\(appearance).png"
                return "<section><h2>\(frame) · \(appearance)</h2><div class=\"pair\"><figure><figcaption>App</figcaption><img src=\"\(filename)\"></figure><figure><figcaption>Figma 04</figcaption><img src=\"../../figma/\(filename)\"></figure></div></section>"
            }
        }.joined(separator: "\n")
        let html = "<!doctype html><meta charset=\"utf-8\"><title>Ticket 04 Toast comparison</title><style>body{font:16px system-ui;margin:24px;background:#eee;color:#1c1c1e}section{margin:24px 0}h2{font-size:20px}.pair{display:flex;gap:20px;align-items:flex-start}figure{margin:0;max-width:393px}img{display:block;width:100%;height:auto;border:1px solid #aaa}</style>\(rows)"
        try Data(html.utf8).write(to: output.appendingPathComponent("index.html"), options: .atomic)
        #endif
    }

    func testCaptureSectionBFramesInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        continueAfterFailure = false
        let root = repositoryRoot
        let catalogURL = root.appendingPathComponent("app/GoFly/Resources/Figma04FrameCatalog.json")
        let catalog = try JSONDecoder().decode(FigmaCatalog.self, from: Data(contentsOf: catalogURL))
        let output = root.appendingPathComponent("work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for frame in catalog.frames.filter({ $0.id.hasPrefix("B") }) {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame.id,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                if frame.id == "B7" {
                    app.launchArguments += ["-gofly-ui-device-state", "unconfirmed-point"]
                }
                if frame.id == "B10" { app.launchArguments.append("-gofly-ui-wifi-disconnected") }
                app.launch()
                waitForFixture(app, frame: frame.id)
                prepareInteractiveFixture(app, frame: frame.id)
                prepareAdditionalFixture(app, frame: frame.id)

                if frame.id == "B7" {
                    let banner = app.descendants(matching: .any)["map.unconfirmedFailure"]
                    XCTAssertTrue(banner.waitForExistence(timeout: 10))
                    XCTAssertTrue(app.staticTexts["map.unconfirmedFailure.title"].label.contains("瞬移失敗"))
                    XCTAssertTrue(app.staticTexts["map.unconfirmedFailure.message"].label.contains("VPN 通道"))
                    XCTAssertTrue(app.buttons["map.unconfirmedFailure.action"].exists)
                    XCTAssertFalse(app.descendants(matching: .any)["map.serviceError"].exists)
                    XCTAssertFalse(app.descendants(matching: .any)["recovery.connectionBanner"].exists)
                }
                switch frame.id {
                case "B1":
                    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "中山北路二段 45 號")).firstMatch.exists)
                case "B3":
                    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.")).count, 2)
                    XCTAssertTrue(app.staticTexts["台北車站"].exists)
                    XCTAssertTrue(app.staticTexts["24.200544, 121.348432"].exists)
                    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
                case "B4":
                    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.")).count, 5)
                    XCTAssertTrue(app.staticTexts["台北車站"].exists)
                    XCTAssertTrue(app.staticTexts["台北轉運站"].exists)
                    XCTAssertTrue(app.staticTexts["京站時尚廣場"].exists)
                    XCTAssertTrue(app.staticTexts["國立台灣博物館"].exists)
                    XCTAssertTrue(app.textFields.firstMatch.value as? String == "台北")
                    let coordinateCard = app.descendants(matching: .any)["search.coordinateCard"]
                    let nearbyTitle = app.staticTexts["附近地點"]
                    let nearbyCard = app.descendants(matching: .any)["search.nearby.card"]
                    XCTAssertEqual(coordinateCard.frame.minY - app.textFields.firstMatch.frame.maxY, 12, accuracy: 3)
                    XCTAssertEqual(nearbyTitle.frame.minY - coordinateCard.frame.maxY, 16, accuracy: 4)
                    XCTAssertEqual(nearbyCard.frame.minY - nearbyTitle.frame.maxY, 8, accuracy: 3)
                case "B5":
                    XCTAssertTrue(app.staticTexts["松山機場"].exists)
                    XCTAssertTrue(app.staticTexts["台北市松山區敦化北路 340-9 號"].exists)
                    XCTAssertTrue(app.buttons["map.candidate.pin"].exists)
                    XCTAssertTrue(app.buttons["map.candidate.go"].exists)
                case "B6":
                    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已移至 台北車站")).firstMatch.exists)
                    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "模擬中 · 台北車站")).firstMatch.exists)
                case "B8", "B9":
                    let pill = app.descendants(matching: .any)["map.statusPill"]
                    XCTAssertTrue(pill.label.contains("已暫停"))
                    let recoveryTitle = app.staticTexts["map.continuationNotice.title"]
                    XCTAssertTrue(recoveryTitle.waitForExistence(timeout: 10))
                    XCTAssertTrue(recoveryTitle.label.contains("瞬移模擬已暫停"))
                    XCTAssertTrue(app.buttons["map.continuationNotice.action"].label.contains("繼續"))
                    XCTAssertTrue(app.staticTexts["台北車站"].exists)
                    if frame.id == "B8" { XCTAssertTrue(app.staticTexts["目前位置"].exists) }
                    else { XCTAssertTrue(app.staticTexts["最後模擬位置"].exists) }
                case "B10":
                    let pill = app.descendants(matching: .any)["map.statusPill"]
                    XCTAssertTrue(pill.label.contains("錯誤"))
                default:
                    break
                }

                let screenshot = app.screenshot()
                let filename = "\(frame.id)-\(appearance).png"
                try screenshot.pngRepresentation.write(to: output.appendingPathComponent(filename), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "ticket-07-\(filename)"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
        #endif
    }

    func testScreenshotArchivePreservesPreviousOutputFiles() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoFlyScreenshotArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }

        for name in ["B1-light.png", "manifest.json", "index.html"] {
            try Data(name.utf8).write(to: output.appendingPathComponent(name))
        }

        try preservePreviousRun(at: output)

        let previous = output.appendingPathComponent("previous", isDirectory: true)
        let archives = try FileManager.default.contentsOfDirectory(at: previous, includingPropertiesForKeys: nil)
        let archive = try XCTUnwrap(archives.first)
        for name in ["B1-light.png", "manifest.json", "index.html"] {
            let archived = archive.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: archived.path))
            XCTAssertEqual(try Data(contentsOf: archived), Data(name.utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent(name).path))
        }
    }

    func testAdditionalConfiguredFrameFixturesOpenExpectedSurface() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        for frame in [
            "D14", "D15", "D16", "D17", "D18", "D19", "D20", "D21", "D22", "D23",
            "E1.a", "E2", "E2.a", "E3", "E4", "E5"
        ] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", frame,
                "-gofly-ui-appearance", "light",
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            if frame == "B10" { app.launchArguments.append("-gofly-ui-wifi-disconnected") }
            if frame == "E2" || frame == "E2.a" { app.launchArguments += ["-gofly-ui-device-state", "normal"] }
            if frame == "D17" { app.launchArguments += ["-gofly-ui-gpx-file", "valid"] }
            if frame == "D18" { app.launchArguments += ["-gofly-ui-gpx-file", "large"] }
            app.launch()
            waitForFixture(app, frame: frame)
            prepareAdditionalFixture(app, frame: frame)
            app.terminate()
        }
        #endif
    }

    func testFavoritePlaceFrameFixturesShowExpectedStatesInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let output = repositoryRoot.appendingPathComponent(
            "work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for frame in ["C1", "C2", "C3", "C4"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                app.launch()
                waitForFixture(app, frame: frame)
                prepareInteractiveFixture(app, frame: frame)

                let favoriteRows = app.buttons.matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", "favorites.place."))
                switch frame {
                case "C1":
                    XCTAssertTrue(app.descendants(matching: .any)["snackbar"].waitForExistence(timeout: 10))
                    XCTAssertTrue(app.descendants(matching: .any)["snackbar"].label.contains("已刪除 1 項"))
                    XCTAssertEqual(favoriteRows.count, 7)
                case "C2":
                    XCTAssertEqual(app.textFields["favorites.editor.label"].placeholderValue, "標籤")
                    XCTAssertFalse(app.staticTexts["標籤"].exists, "C2 uses the field placeholder without a separate label")
                    XCTAssertTrue(app.buttons["favorites.editor.clear"].exists)
                    let form = app.scrollViews["favorites.editor.form"]
                    let field = app.textFields["favorites.editor.label"]
                    let info = app.descendants(matching: .any)["favorites.editor.info"]
                    let save = app.buttons["favorites.editor.save"]
                    XCTAssertEqual(field.frame.minY - form.frame.minY, 24, accuracy: 4)
                    XCTAssertEqual(info.frame.minY - field.frame.maxY, 16, accuracy: 4)
                    XCTAssertEqual(save.frame.minY - info.frame.maxY, 40, accuracy: 4)
                    XCTAssertTrue(save.exists)
                case "C3":
                    XCTAssertTrue(app.staticTexts["已選取 2 項"].exists)
                    XCTAssertTrue(app.buttons["favorites.deleteSelected"].label.contains("2"))
                    XCTAssertEqual(app.buttons.matching(
                        NSPredicate(format: "identifier BEGINSWITH %@", "favorites.checkbox.")).count, 7)
                case "C4":
                    XCTAssertTrue(app.descendants(matching: .any)["snackbar"].waitForExistence(timeout: 10))
                    XCTAssertTrue(app.descendants(matching: .any)["snackbar"].label.contains("已刪除 2 項"))
                    XCTAssertEqual(favoriteRows.count, 5)
                default:
                    break
                }

                let screenshot = app.screenshot()
                try screenshot.pngRepresentation.write(
                    to: output.appendingPathComponent("\(frame)-\(appearance).png"), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "ticket-08-\(frame)-\(appearance)"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
        #endif
    }

    func testFavoriteEditorRemainsAccessibleAtMaximumDynamicTypeWithReduceMotion() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Accessibility checks run on the iOS Simulator.")
        #else
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", "C2",
                "-gofly-ui-appearance", appearance,
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                "-UIAccessibilityReduceMotion", "YES",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launch()
            waitForFixture(app, frame: "C2")
            prepareInteractiveFixture(app, frame: "C2")
            let field = app.textFields["favorites.editor.label"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["favorites.editor.clear"].isHittable)
            XCTAssertTrue(app.buttons["favorites.editor.cancel"].isHittable)
            let save = app.buttons["favorites.editor.save"]
            let editor = app.scrollViews["favorites.editor.form"]
            for _ in 0..<6 where !save.isHittable { editor.swipeUp() }
            XCTAssertTrue(save.isHittable)
            app.terminate()
        }
        #endif
    }

    func testFavoriteBulkDeleteCanBeUndoneInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Favorite deletion undo runs on the iOS Simulator.")
        #else
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", "C4",
                "-gofly-ui-appearance", appearance,
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launch()
            waitForFixture(app, frame: "C4")
            prepareInteractiveFixture(app, frame: "C4")
            let snackbarAction = app.buttons["snackbar.action"]
            XCTAssertTrue(snackbarAction.waitForExistence(timeout: 10))
            snackbarAction.tap()
            XCTAssertEqual(app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "favorites.place.")).count, 7)
            app.terminate()
        }
        #endif
    }

    func testE4WanderFixtureShowsDestinationCard() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-frame", "E4",
            "-gofly-ui-appearance", "light",
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly-ui-favorites-store", UUID().uuidString,
            "-gofly-ui-imports-store", UUID().uuidString,
            "-gofly-ui-favorite-routes-store", UUID().uuidString,
            "-gofly-ui-preferences-store", UUID().uuidString,
            "-gofly-ui-preferences-language", "zh-Hant",
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
        ]
        app.launch()
        let locationCard = app.descendants(matching: .any)["map.wander.locationCard"]
        XCTAssertTrue(locationCard.waitForExistence(timeout: 45))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "E4-light-destination-card"
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }

    func testRoutePlanningFramesMatchFixturesInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let output = repositoryRoot.appendingPathComponent(
            "work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for frame in ["D1", "D2", "D2.a", "D3", "D4", "D5"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                app.launch()
                waitForFixture(app, frame: frame)
                prepareAdditionalFixture(app, frame: frame)

                if frame == "D5" {
                    let query = app.textFields["search.query"]
                    let currentLocation = app.buttons["route.picker.current"]
                    let favorites = app.buttons["search.favorites"]
                    XCTAssertTrue(query.waitForExistence(timeout: 10))
                    XCTAssertTrue((query.value as? String ?? "").isEmpty,
                                  "D5 starts with an empty query in Figma.")
                    XCTAssertTrue(currentLocation.waitForExistence(timeout: 10))
                    XCTAssertGreaterThanOrEqual(currentLocation.frame.height, 52,
                                                "D5 current-location shortcut shares the compact list-row height.")
                    XCTAssertTrue(favorites.waitForExistence(timeout: 10))
                    XCTAssertEqual(favorites.label, "最愛 Favorite")
                    XCTAssertGreaterThanOrEqual(favorites.frame.height, 44,
                                                 "D5 primary favorite shortcut keeps a 44 pt hit target.")
                    XCTAssertTrue(app.staticTexts["最近搜尋"].waitForExistence(timeout: 10))
                    XCTAssertGreaterThanOrEqual(
                        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.")).count,
                        1,
                        "D5 fixture includes the Figma recent-search row."
                    )
                }
                if frame == "D2" || frame == "D2.a" {
                    XCTAssertTrue(app.staticTexts["台北 101"].waitForExistence(timeout: 10))
                    if frame == "D2" {
                        XCTAssertTrue(app.staticTexts["國立故宮博物院"].exists)
                        XCTAssertFalse(app.descendants(matching: .any)["route.error"].exists,
                                       "D2 is a successful route preview fixture and must not show an error toast.")
                    }
                }

                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                let screenshot = app.screenshot()
                try screenshot.pngRepresentation.write(
                    to: output.appendingPathComponent("\(frame)-\(appearance).png"), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "ticket-09-\(frame)-\(appearance)"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
        #endif
    }

    func testD1ControlsRemainReachableAtMaximumDynamicTypeAndReduceMotion() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", "D1",
                "-gofly-ui-appearance", appearance,
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                "-UIAccessibilityReduceMotion", "YES",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launch()
            waitForFixture(app, frame: "D1")

            for identifier in ["route.node.start", "route.node.destination", "route.addNode",
                               "route.viewList", "route.favorite.toggle"] {
                let control = app.buttons[identifier]
                XCTAssertTrue(control.waitForExistence(timeout: 10), "missing D1 control: \(identifier)")
                XCTAssertTrue(control.isHittable, "D1 control is clipped at maximum Dynamic Type: \(identifier)")
            }
            app.terminate()
        }
        #endif
    }

    func testCaptureSupportedFigmaFramesInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        continueAfterFailure = false
        let root = repositoryRoot
        let catalogURL = root.appendingPathComponent("app/GoFly/Resources/Figma04FrameCatalog.json")
        let catalog = try JSONDecoder().decode(FigmaCatalog.self, from: Data(contentsOf: catalogURL))
        let output = root.appendingPathComponent("work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try preservePreviousRun(at: output)

        var captures: [CaptureRecord] = []
        for frame in catalog.frames.filter({ supportedFrames.contains($0.id) }) {
            for appearance in ["light", "dark"] {
                let nodeID = try XCTUnwrap(frame.nodeIds[appearance], "missing Figma \(appearance) variant for \(frame.id)")
                let sessionID = UUID().uuidString
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame.id,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", sessionID,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                if frame.id == "R04" { app.launchArguments.append("-gofly-ui-vpn-static") }
                if frame.id == "B10" { app.launchArguments.append("-gofly-ui-wifi-disconnected") }
                if frame.id == "B7" {
                    app.launchArguments += ["-gofly-ui-device-state", "unconfirmed-point"]
                }
                if frame.id == "D8" {
                    app.launchArguments += ["-gofly-ui-route-outcome", "planningFailed"]
                }
                if frame.id == "D17" { app.launchArguments += ["-gofly-ui-gpx-file", "valid"] }
                if frame.id == "D18" { app.launchArguments += ["-gofly-ui-gpx-file", "large"] }
                if frame.id == "F1.a" {
                    app.launchArguments += ["-gofly-ui-device-state", "stop-failure"]
                }
                app.launch()
                waitForFixture(app, frame: frame.id)
                prepareInteractiveFixture(app, frame: frame.id)
                if ["R02", "R03"].contains(frame.id) {
                    XCTAssertFalse(app.staticTexts["步驟 2／3"].exists)
                }
                if ["R04", "R04.a"].contains(frame.id) {
                    XCTAssertFalse(app.staticTexts["步驟 3／3"].exists)
                }

                if ["F4", "F5", "F6", "F6.a", "F7", "F8", "F9"].contains(frame.id) {
                    openSettingsFrame(app, frame: frame.id)
                }
                prepareAdditionalFixture(app, frame: frame.id)
                if frame.id == "F1.a" {
                    XCTAssertTrue(app.buttons["service.reset"].waitForExistence(timeout: 10))
                }

                if frame.id == "R05" {
                    let help = app.buttons["onboarding.vpn.help.open"]
                    XCTAssertTrue(help.waitForExistence(timeout: 10))
                    help.tap()
                    XCTAssertTrue(app.buttons["onboarding.vpn.help.step1.action"].waitForExistence(timeout: 10))
                    XCTAssertTrue(app.descendants(matching: .any)["onboarding.vpn.help.back"].waitForExistence(timeout: 5))
                    XCTAssertFalse(app.buttons["onboarding.vpn.help.openSettings"].exists)
                    XCTAssertFalse(app.buttons["onboarding.vpn.help.openVPN"].exists)
                }
                if frame.id == "R04.a" {
                    XCTAssertTrue(app.descendants(matching: .any)["onboarding.vpn.failure"].waitForExistence(timeout: 10))
                }
                if frame.id == "B10" {
                    XCTAssertTrue(app.descendants(matching: .any)["recovery.connectionBanner"].waitForExistence(timeout: 10))
                }
                if frame.id == "B2" {
                    let company = app.staticTexts["公司"].firstMatch
                    let testPlace = app.staticTexts["測試點 A"].firstMatch
                    XCTAssertTrue(company.waitForExistence(timeout: 10))
                    XCTAssertTrue(testPlace.waitForExistence(timeout: 10))
                    XCTAssertLessThan(company.frame.minY, testPlace.frame.minY,
                                      "B2 favorites must follow the Figma order")
                }
                if frame.id == "B7" {
                    let banner = app.descendants(matching: .any)["map.unconfirmedFailure"]
                    XCTAssertTrue(banner.waitForExistence(timeout: 10))
                    XCTAssertTrue(app.staticTexts["map.unconfirmedFailure.title"].label.contains("瞬移失敗"))
                    XCTAssertTrue(app.staticTexts["map.unconfirmedFailure.message"].label.contains("VPN 通道"))
                    XCTAssertTrue(app.buttons["map.unconfirmedFailure.action"].exists)
                    XCTAssertFalse(app.descendants(matching: .any)["map.serviceError"].exists)
                    XCTAssertFalse(app.descendants(matching: .any)["recovery.connectionBanner"].exists)
                }

                // Allow the offline tile renderer and SwiftUI transitions to settle.
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                let screenshot = app.screenshot()
                let filename = "\(frame.id)-\(appearance).png"
                let relativePath = "work/gofly-ios-figma04/screenshots/\(filename)"
                try screenshot.pngRepresentation.write(to: output.appendingPathComponent(filename), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "\(frame.id)-\(appearance)"
                attachment.lifetime = .keepAlways
                add(attachment)
                captures.append(CaptureRecord(
                    frame: frame.id,
                    name: frame.name,
                    appearance: appearance,
                    figmaNodeID: nodeID,
                    screenshotPath: relativePath,
                    expectedFigmaPath: "work/gofly-ios-figma04/figma/\(filename)",
                    fixtureFlags: app.launchArguments
                ))
                app.terminate()
            }
        }

        let unavailable = catalog.frames.filter { !supportedFrames.contains($0.id) }.map {
            UnavailableRecord(frame: $0.id, name: $0.name, reason: unavailableReason(for: $0.id))
        }
        let conflicts = [
            "B11: the earlier ticket 00 record says Dark is missing, but the current catalog and read-only render include Dark node 322:40470; capture the current render and retain this documentation conflict for review.",
            "R06: no frame or rendered variant exists in the current Figma 04 catalog; it is excluded from the screenshot matrix."
        ]
        let manifest = ScreenshotManifest(
            fileKey: catalog.fileKey,
            pageNodeID: catalog.pageNodeId,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            captures: captures,
            unavailable: unavailable,
            figmaConflicts: conflicts
        )
        let data = try JSONEncoder.prettyPrinted.encode(manifest)
        try data.write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        try writeIndex(catalog: catalog, captures: captures, unavailable: unavailable,
                       conflicts: conflicts, output: output)
        #endif
    }

    func testCaptureD19ThroughD23InBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        continueAfterFailure = false
        let output = repositoryRoot.appendingPathComponent("work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for frame in ["D19", "D20", "D21", "D22", "D23"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                app.launch()
                waitForFixture(app, frame: frame)
                prepareInteractiveFixture(app, frame: frame)
                prepareAdditionalFixture(app, frame: frame)
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))

                let screenshot = app.screenshot()
                try screenshot.pngRepresentation.write(
                    to: output.appendingPathComponent("\(frame)-\(appearance).png"), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "\(frame)-\(appearance)-section-D4"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
        #endif
    }

    func testD19D20D23RemainReachableAtMaximumDynamicTypeWithReduceMotion() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Accessibility checks run on the iOS Simulator.")
        #else
        for frame in ["D19", "D20", "D23"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                    "-UIAccessibilityReduceMotion", "YES",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                app.launch()
                waitForFixture(app, frame: frame)

                switch frame {
                case "D19":
                    XCTAssertTrue(app.textFields["favoriteRoutes.search"].isHittable)
                    XCTAssertTrue(app.buttons.matching(
                        NSPredicate(format: "identifier BEGINSWITH %@", "favoriteRoutes.edit.")).firstMatch.isHittable)
                case "D20":
                    prepareAdditionalFixture(app, frame: frame)
                    XCTAssertTrue(app.buttons["favoriteRoutes.editor.cancel"].isHittable)
                    let content = app.scrollViews["favoriteRoutes.editor.content"]
                    XCTAssertTrue(content.exists)
                    let save = app.buttons["favoriteRoutes.editor.save"]
                    for _ in 0..<8 where !save.isHittable { content.swipeUp() }
                    XCTAssertTrue(save.isHittable)
                    XCTAssertFalse(app.keyboards.firstMatch.exists)
                case "D23":
                    let back = app.buttons["route.list.back"]
                    XCTAssertTrue(back.isHittable)
                    let scroll = app.scrollViews.firstMatch
                    XCTAssertTrue(scroll.exists)
                    let add = app.buttons["route.list.addWaypoint"]
                    let reverse = app.buttons["route.list.reverse"]
                    for _ in 0..<8 where !add.isHittable || !reverse.isHittable { scroll.swipeUp() }
                    XCTAssertTrue(add.isHittable)
                    XCTAssertTrue(reverse.isHittable)
                default:
                    break
                }

                app.terminate()
            }
        }
        #endif
    }

    func testCaptureSectionD3GPXFramesInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let output = repositoryRoot.appendingPathComponent(
            "work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for frame in ["D11", "D12", "D13", "D14", "D15", "D16", "D17", "D18"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                if frame == "D17" { app.launchArguments += ["-gofly-ui-gpx-file", "valid"] }
                if frame == "D18" { app.launchArguments += ["-gofly-ui-gpx-file", "large"] }
                app.launch()
                waitForFixture(app, frame: frame)
                prepareAdditionalFixture(app, frame: frame)

                switch frame {
                case "D11":
                    XCTAssertTrue(app.descendants(matching: .any)["imports.content"].exists)
                    XCTAssertTrue(app.buttons["imports.import"].exists)
                case "D12":
                    XCTAssertTrue(app.descendants(matching: .any)["imports.actions"].waitForExistence(timeout: 10))
                    XCTAssertTrue(app.buttons["imports.points.showAll"].exists)
                    XCTAssertTrue(app.buttons["imports.delete"].exists)
                    XCTAssertFalse(app.buttons["imports.import"].isHittable)
                case "D13":
                    XCTAssertTrue(app.buttons["imports.point.0"].exists)
                case "D17":
                    XCTAssertTrue(app.buttons["snackbar.dismiss"].waitForExistence(timeout: 10))
                    XCTAssertFalse(app.buttons["snackbar.action"].exists)
                    let toast = app.descendants(matching: .any)["snackbar"]
                    let importButton = app.buttons["imports.import"]
                    XCTAssertEqual(importButton.frame.minY - toast.frame.maxY, 16, accuracy: 3)
                case "D18":
                    XCTAssertTrue(app.descendants(matching: .any)["imports.error"].waitForExistence(timeout: 10))
                    XCTAssertEqual(app.buttons["imports.error.action"].label, "重試")
                default:
                    break
                }

                let filename = "\(frame)-\(appearance).png"
                let screenshot = frame == "D16" ? XCUIScreen.main.screenshot() : app.screenshot()
                try screenshot.pngRepresentation.write(to: output.appendingPathComponent(filename), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "ticket-13-\(filename)"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
        #endif
    }

    func testD13PointsStayScrollableAtMaximumDynamicTypeWithReduceMotion() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only on the iOS Simulator.")
        #else
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", "D13",
                "-gofly-ui-appearance", appearance,
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                "-UIAccessibilityReduceMotion", "YES",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launch()
            waitForFixture(app, frame: "D13")
            let initialRouteError = app.buttons["route.error.dismiss"]
            if initialRouteError.waitForExistence(timeout: 1) { initialRouteError.tap() }
            prepareAdditionalFixture(app, frame: "D13")

            let firstPoint = app.buttons["imports.point.0"]
            let laterPoint = app.buttons["imports.point.15"]
            let list = app.scrollViews.firstMatch
            XCTAssertTrue(firstPoint.waitForExistence(timeout: 10))
            XCTAssertTrue(firstPoint.isHittable)
            XCTAssertTrue(list.exists)
            for _ in 0..<12 where !laterPoint.isHittable { list.swipeUp() }
            XCTAssertTrue(laterPoint.isHittable, "later GPX points must remain reachable with maximum text size")
            XCTAssertTrue(app.staticTexts["imports.points.readOnly"].exists)
            let back = app.descendants(matching: .any)["imports.points.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(back.isHittable, app.debugDescription)
            app.terminate()
        }
        #endif
    }

    func testCaptureD13PointsFrameInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only on the iOS Simulator.")
        #else
        let output = repositoryRoot.appendingPathComponent(
            "work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", "D13",
                "-gofly-ui-appearance", appearance,
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            app.launch()
            waitForFixture(app, frame: "D13")
            let initialRouteError = app.buttons["route.error.dismiss"]
            if initialRouteError.waitForExistence(timeout: 1) { initialRouteError.tap() }
            prepareAdditionalFixture(app, frame: "D13")
            XCTAssertTrue(app.staticTexts["imports.points.readOnly"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["imports.points.back"].exists)

            let screenshot = app.screenshot()
            try screenshot.pngRepresentation.write(
                to: output.appendingPathComponent("D13-\(appearance).png"), options: .atomic)
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "ticket-13-D13-\(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        #endif
    }

    func testCaptureSectionF1FramesInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        continueAfterFailure = false
        let output = repositoryRoot.appendingPathComponent("work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for frame in ["F1", "F1.a", "F1.b"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                if frame == "F1.a" {
                    app.launchArguments += ["-gofly-ui-device-state", "stop-failure"]
                }
                app.launch()
                waitForFixture(app, frame: frame)
                prepareInteractiveFixture(app, frame: frame)
                prepareAdditionalFixture(app, frame: frame)
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))

                let screenshot = app.screenshot()
                try screenshot.pngRepresentation.write(
                    to: output.appendingPathComponent("\(frame)-\(appearance).png"), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "\(frame)-\(appearance)-section-F1"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
        #endif
    }

    func testSectionF1RemainsReachableAtMaximumDynamicTypeWithReduceMotion() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Accessibility checks run on the iOS Simulator.")
        #else
        for frame in ["F1", "F1.a", "F1.b"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                    "-UIAccessibilityReduceMotion", "YES",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                if frame == "F1.a" {
                    app.launchArguments += ["-gofly-ui-device-state", "stop-failure"]
                }
                app.launch()
                waitForFixture(app, frame: frame)
                prepareInteractiveFixture(app, frame: frame)
                prepareAdditionalFixture(app, frame: frame)

                let backButton = app.buttons["settings.back"]
                XCTAssertTrue(backButton.waitForExistence(timeout: 10))
                XCTAssertTrue(backButton.isHittable)

                let primaryOrReset = frame == "F1.a" ? app.buttons["service.reset"] : app.buttons["service.primary"]
                XCTAssertTrue(primaryOrReset.waitForExistence(timeout: 10))
                XCTAssertGreaterThanOrEqual(primaryOrReset.frame.height, 44)

                if frame == "F1.b" {
                    let toast = app.descendants(matching: .any)["service.resetSucceeded"]
                    XCTAssertTrue(toast.waitForExistence(timeout: 10))
                }

                app.terminate()
            }
        }
        #endif
    }

    func testCaptureSectionF2SubpagesInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        continueAfterFailure = false
        let output = repositoryRoot.appendingPathComponent("work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for frame in ["F4", "F5", "F6", "F6.a", "F7", "F8", "F9"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                app.launch()
                waitForFixture(app, frame: frame)
                prepareInteractiveFixture(app, frame: frame)
                openSettingsFrame(app, frame: frame)
                prepareAdditionalFixture(app, frame: frame)
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))

                let screenshot = app.screenshot()
                try screenshot.pngRepresentation.write(
                    to: output.appendingPathComponent("\(frame)-\(appearance).png"), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "\(frame)-\(appearance)-section-F2"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
        #endif
    }

    func testSectionF2SubpagesRemainReachableAtMaximumDynamicTypeWithReduceMotion() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Accessibility checks run on the iOS Simulator.")
        #else
        for frame in ["F4", "F5", "F6", "F6.a", "F7", "F8", "F9"] {
            for appearance in ["light", "dark"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", UUID().uuidString,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                    "-UIAccessibilityReduceMotion", "YES",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                app.launch()
                waitForFixture(app, frame: frame)
                prepareInteractiveFixture(app, frame: frame)
                openSettingsFrame(app, frame: frame)
                prepareAdditionalFixture(app, frame: frame)

                if frame == "F6.a" {
                    let confirm = app.buttons["settings.background.duration.confirm"]
                    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
                    XCTAssertTrue(confirm.isHittable)
                } else {
                    let pageBackID: String
                    switch frame {
                    case "F4": pageBackID = "settings.location.page.back"
                    case "F5": pageBackID = "settings.vpn.page.back"
                    case "F6": pageBackID = "settings.background.page.back"
                    case "F7": pageBackID = "settings.language.page.back"
                    case "F8": pageBackID = "settings.appearance.page.back"
                    default: pageBackID = "settings.device.page.back"
                    }
                    let backButton = app.descendants(matching: .any)[pageBackID]
                    XCTAssertTrue(backButton.waitForExistence(timeout: 10))
                    XCTAssertTrue(backButton.isHittable)
                }
                app.terminate()
            }
        }
        #endif
    }

    private func preservePreviousRun(at output: URL) throws {
        let manager = FileManager.default
        let previousFiles = try manager.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
            .filter { ["png", "json", "html"].contains($0.pathExtension.lowercased()) }
        guard !previousFiles.isEmpty else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let archive = output.appendingPathComponent("previous", isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)
        try manager.createDirectory(at: archive, withIntermediateDirectories: true)
        for file in previousFiles {
            try manager.copyItem(at: file, to: archive.appendingPathComponent(file.lastPathComponent))
        }
        for file in previousFiles {
            try manager.removeItem(at: file)
        }
    }

    private func writeIndex(catalog: FigmaCatalog, captures: [CaptureRecord],
                            unavailable: [UnavailableRecord], conflicts: [String], output: URL) throws {
        let captureKeys = Set(captures.map { "\($0.frame)-\($0.appearance)" })
        let unavailableByFrame = Dictionary(uniqueKeysWithValues: unavailable.map { ($0.frame, $0.reason) })
        let frameRows = catalog.frames.map { frame -> String in
            let section = frame.id.first == "R" ? "A" : String(frame.id.prefix(1))
            let light = comparisonCells(frame: frame, appearance: "light", available: captureKeys,
                                        unavailableReason: unavailableByFrame[frame.id])
            let dark = comparisonCells(frame: frame, appearance: "dark", available: captureKeys,
                                       unavailableReason: unavailableByFrame[frame.id])
            return """
            <tr data-section="\(escapeHTML(section))" data-frame="\(escapeHTML(frame.id))">
              <th scope="row"><strong>\(escapeHTML(frame.id))</strong><br><span>\(escapeHTML(frame.name))</span></th>
              \(light)
              \(dark)
            </tr>
            """
        }.joined(separator: "\n")
        let conflictNotice = conflicts.map { "<li>\(escapeHTML($0))</li>" }.joined()
        let html = """
        <!doctype html>
        <html lang="zh-Hant">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>GoFly Figma 04 · App 對照</title>
          <style>
            :root { color-scheme: light; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
            body { margin: 20px; color: #202124; background: #f6f7f9; }
            header { position: sticky; top: 0; z-index: 2; padding: 12px 0; background: #f6f7f9; }
            h1 { margin: 0 0 10px; font-size: 21px; }
            .meta, .notes { color: #555; }
            .notes { max-width: 1000px; }
            table { width: 100%; border-collapse: separate; border-spacing: 0; background: white; }
            th, td { padding: 10px; border-right: 1px solid #ddd; border-bottom: 1px solid #ddd; vertical-align: top; }
            thead th { position: sticky; top: 77px; z-index: 1; background: #e9ebef; text-align: left; }
            tbody th { min-width: 130px; text-align: left; }
            tbody th span { display: inline-block; margin-top: 5px; color: #555; font-weight: 400; }
            img { display: block; width: min(19vw, 220px); min-width: 135px; height: auto; border: 1px solid #d4d6da; background: #eee; }
            .missing { width: min(19vw, 220px); min-width: 135px; min-height: 180px; padding: 8px; box-sizing: border-box; color: #855b00; background: #fff6d9; }
            .conflict { color: #a11; font-weight: 600; }
            tr[hidden] { display: none; }
          </style>
        </head>
        <body>
          <header>
            <h1>GoFly · Figma 04 對照</h1>
            <div class="meta">Frame × Light／Dark · Figma 截圖與 App fixture 輸出</div>
            <label>Section <select id="section-filter"><option value="all">全部</option><option>A</option><option>B</option><option>C</option><option>D</option><option>E</option><option>F</option></select></label>
          </header>
          <ul class="notes">\(conflictNotice)</ul>
          <table>
            <thead><tr><th>Frame</th><th>Light · Figma</th><th>Light · App</th><th>Dark · Figma</th><th>Dark · App</th></tr></thead>
            <tbody>\(frameRows)</tbody>
          </table>
          <script>
            document.getElementById('section-filter').addEventListener('change', function () {
              document.querySelectorAll('tbody tr').forEach(function (row) {
                row.hidden = this.value !== 'all' && row.dataset.section !== this.value;
              }, this);
            });
          </script>
        </body>
        </html>
        """
        try html.write(to: output.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    private func comparisonCells(frame: FigmaFrame, appearance: String,
                                 available: Set<String>, unavailableReason: String?) -> String {
        let key = "\(frame.id)-\(appearance)"
        let nodeID = frame.nodeIds[appearance]
        let figmaCell: String
        if nodeID != nil {
            let conflict = frame.id == "B11" && appearance == "dark"
            let note = conflict ? "<span class=\"conflict\">Conflict: not approved</span>" : ""
            figmaCell = "<td>\(note)<img loading=\"lazy\" src=\"../figma/\(escapeHTML(key)).png\" alt=\"Figma \(escapeHTML(key))\"></td>"
        } else {
            figmaCell = "<td><div class=\"missing\">No rendered Figma \(escapeHTML(appearance)) variant recorded.</div></td>"
        }
        let appCell: String
        if available.contains(key) {
            appCell = "<td><img loading=\"lazy\" src=\"./\(escapeHTML(key)).png\" alt=\"App \(escapeHTML(key))\"></td>"
        } else {
            let reason = unavailableReason ?? "No deterministic fixture recorded."
            appCell = "<td><div class=\"missing\">\(escapeHTML(reason))</div></td>"
        }
        return figmaCell + appCell
    }

    private func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func waitForFixture(_ app: XCUIApplication, frame: String) {
        let fixture = app.descendants(matching: .any)["figma.fixture.\(frame)"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 15), "frame fixture did not open: \(frame)")
        switch frame {
        case "R02", "R03":
            XCTAssertTrue(app.buttons["onboarding.location.allow"].waitForExistence(timeout: 10))
        case "R04", "R04.a", "R05":
            XCTAssertTrue(app.buttons["onboarding.vpn.check"].waitForExistence(timeout: 10))
        case "B7":
            XCTAssertTrue(app.descendants(matching: .any)["map.unconfirmedFailure"].waitForExistence(timeout: 15))
        case "D8":
            XCTAssertTrue(app.descendants(matching: .any)["route.error"].waitForExistence(timeout: 15))
        case "F1.b":
            XCTAssertTrue(app.buttons["service.primary"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any)["service.resetSucceeded"].waitForExistence(timeout: 10))
        case "F1":
            XCTAssertTrue(app.buttons["service.primary"].waitForExistence(timeout: 10))
        case "R07":
            XCTAssertTrue(app.descendants(matching: .any)["setup.mac.status"].waitForExistence(timeout: 10))
        case "R08":
            XCTAssertTrue(app.staticTexts["setup.blocked.title"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["setup.retry"].exists)
        case "B1", "B2", "B5", "B10", "D1", "D6", "E1":
            XCTAssertTrue(app.otherElements["map.canvas"].waitForExistence(timeout: 10))
            if frame == "B2" {
                let pill = app.descendants(matching: .any)["map.statusPill"]
                XCTAssertTrue(pill.waitForExistence(timeout: 10))
                let predicate = NSPredicate(format: "label CONTAINS %@", "模擬中")
                expectation(for: predicate, evaluatedWith: pill)
                waitForExpectations(timeout: 20)
            }
            if frame == "B5" {
                let card = app.descendants(matching: .any)["map.teleport.locationCard"]
                XCTAssertTrue(card.waitForExistence(timeout: 15))
                let primary = app.buttons["map.teleport.locationCard.primaryAction"]
                let favorite = app.buttons["map.teleport.locationCard.favorite"]
                XCTAssertTrue(primary.exists)
                XCTAssertTrue(primary.isHittable, "B5 primary action must be visible above the sheet")
                XCTAssertTrue(app.buttons["map.teleport.locationCard.favorite"].exists)
                XCTAssertTrue(app.buttons["map.teleport.locationCard.copy"].exists)
                XCTAssertTrue(app.buttons["map.teleport.locationCard.dismiss"].exists)
                XCTAssertEqual(primary.frame.minX, card.frame.minX + 16, accuracy: 2,
                               "B5 primary action should align to the card's left inset")
                XCTAssertLessThan(primary.frame.maxX, favorite.frame.minX,
                                   "B5 primary action should stay left of secondary actions")
                XCTAssertTrue(app.buttons["map.recenter"].exists)
                XCTAssertEqual(card.frame.width, app.windows.firstMatch.frame.width - 32, accuracy: 1)
                XCTAssertEqual(card.frame.height, 180, accuracy: 1)
                XCTAssertEqual(app.buttons["map.teleport.locationCard.primaryAction"].frame.width, 77, accuracy: 1)
                for identifier in ["map.teleport.locationCard.primaryAction", "map.teleport.locationCard.favorite",
                                   "map.teleport.locationCard.copy", "map.teleport.locationCard.dismiss"] {
                    XCTAssertGreaterThanOrEqual(app.buttons[identifier].frame.width, 44, "undersized target: \(identifier)")
                    XCTAssertGreaterThanOrEqual(app.buttons[identifier].frame.height, 44, "undersized target: \(identifier)")
                }
            }
            if frame == "D6" {
                XCTAssertTrue(app.buttons["route.cancel"].waitForExistence(timeout: 20))
            }
        case "B3":
            XCTAssertTrue(app.otherElements["search.panel"].waitForExistence(timeout: 10))
        case "B4":
            XCTAssertTrue(app.otherElements["search.panel"].waitForExistence(timeout: 10))
            let result = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "search.result.")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 10))
        case "B6":
            XCTAssertTrue(app.descendants(matching: .any)["snackbar"].waitForExistence(timeout: 10))
        case "D5":
            XCTAssertTrue(app.descendants(matching: .any)["search.panel"].waitForExistence(timeout: 10))
        case "D19":
            XCTAssertTrue(app.descendants(matching: .any)["favoriteRoutes.content"].waitForExistence(timeout: 10))
        case "D23":
            XCTAssertTrue(app.descendants(matching: .any)["route.list"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["route.list.addWaypoint"].exists)
            XCTAssertTrue(app.buttons["route.list.reverse"].exists)
            let list = app.descendants(matching: .any)["route.list.nodes"]
            let add = app.buttons["route.list.addWaypoint"]
            XCTAssertEqual(add.frame.minY - list.frame.maxY, 12, accuracy: 3)
        case "E1.a":
            XCTAssertTrue(app.descendants(matching: .any)["joystick.panel"].waitForExistence(timeout: 10))
        case "E2":
            XCTAssertTrue(app.buttons["joystick.stopWander"].waitForExistence(timeout: 45))
            XCTAssertTrue(app.staticTexts["漫步中"].exists)
        case "E2.a":
            XCTAssertTrue(app.descendants(matching: .any)["joystick.panel"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["漫步中"].waitForExistence(timeout: 30))
        case "E4":
            XCTAssertTrue(app.descendants(matching: .any)["map.wander.locationCard"].waitForExistence(timeout: 45))
        case "C1", "C2", "C3", "C4":
            let firstFavorite = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "favorites.place.")).firstMatch
            XCTAssertTrue(firstFavorite.waitForExistence(timeout: 15), "favorite seed missing for \(frame)")
        default:
            break
        }
    }

    private func prepareInteractiveFixture(_ app: XCUIApplication, frame: String) {
        switch frame {
        case "C1":
            let extraEdit = app.buttons["favorites.edit.24.000001, 120.000001"]
            XCTAssertTrue(extraEdit.waitForExistence(timeout: 10))
            XCTAssertTrue(extraEdit.isHittable)
            extraEdit.tap()
            XCTAssertTrue(app.buttons["favorites.editor.delete"].waitForExistence(timeout: 10))
            app.buttons["favorites.editor.delete"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["snackbar"].waitForExistence(timeout: 10))
        case "C2":
            let edit = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "favorites.edit.")).firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 10))
            edit.tap()
            XCTAssertTrue(app.descendants(matching: .any)["favorites.editor.form"].waitForExistence(timeout: 10))
        case "C3":
            let select = app.buttons["favorites.select"]
            XCTAssertTrue(select.waitForExistence(timeout: 10))
            select.tap()
            let checkboxes = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "favorites.checkbox."))
            XCTAssertEqual(checkboxes.count, 7)
            checkboxes.element(boundBy: 1).tap()
            checkboxes.element(boundBy: 3).tap()
            XCTAssertFalse(checkboxes.element(boundBy: 0).isSelected)
            XCTAssertTrue(checkboxes.element(boundBy: 1).isSelected)
            XCTAssertTrue(checkboxes.element(boundBy: 3).isSelected)
            XCTAssertTrue(app.buttons["favorites.deleteSelected"].waitForExistence(timeout: 10))
        case "C4":
            let select = app.buttons["favorites.select"]
            XCTAssertTrue(select.waitForExistence(timeout: 10))
            select.tap()
            let checkboxes = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "favorites.checkbox."))
            XCTAssertEqual(checkboxes.count, 7)
            XCTAssertGreaterThanOrEqual(checkboxes.element(boundBy: 1).frame.width, 44)
            checkboxes.element(boundBy: 1).tap()
            checkboxes.element(boundBy: 3).tap()
            let delete = app.buttons["favorites.deleteSelected"]
            XCTAssertTrue(delete.waitForExistence(timeout: 10))
            XCTAssertTrue(delete.isEnabled)
            delete.tap()
            XCTAssertTrue(app.buttons["snackbar.action"].waitForExistence(timeout: 10))
        default:
            break
        }
    }

    private func prepareAdditionalFixture(_ app: XCUIApplication, frame: String) {
        switch frame {
        case "B8", "B9", "E5":
            XCTAssertTrue(app.descendants(matching: .any)["map.continuationNotice"].waitForExistence(timeout: 20))
        case "B11":
            XCTAssertTrue(app.descendants(matching: .any)["map.statusPill"].waitForExistence(timeout: 10))
        case "D4":
            XCTAssertTrue(app.descendants(matching: .any)["map.candidate.pin"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.buttons["map.route.confirmCard.primaryAction"].label, "確認")
        case "D7":
            let speed = app.buttons["route.speedChip"]
            XCTAssertTrue(speed.waitForExistence(timeout: 20))
            speed.tap()
            XCTAssertTrue(app.descendants(matching: .any)["route.speed.value"].waitForExistence(timeout: 10))
        case "D6":
            XCTAssertTrue(app.buttons["route.cancel"].waitForExistence(timeout: 20))
        case "D10":
            XCTAssertTrue(app.buttons["route.cancel"].waitForExistence(timeout: 20))
            XCTAssertEqual(app.buttons["map.continuationNotice.action"].label, "繼續")
            XCTAssertTrue(app.descendants(matching: .any)["map.continuationNotice"].waitForExistence(timeout: 10))
        case "D10.a":
            XCTAssertTrue(app.buttons["route.cancel"].waitForExistence(timeout: 20))
            XCTAssertTrue(app.buttons["route.resume"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.descendants(matching: .any)["map.continuationNotice"].exists)
        case "D11":
            openImports(app)
        case "D15":
            XCTAssertTrue(app.descendants(matching: .any)["route.importedSummary"].waitForExistence(timeout: 10))
        case "D12":
            openImportsAndFirstRecord(app)
            XCTAssertTrue(app.buttons["imports.load"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["imports.actions.cancel"].exists)
        case "D13":
            openImportsAndFirstRecord(app)
            let points = app.buttons.matching(identifier: "imports.points.showAll").firstMatch
            XCTAssertTrue(points.waitForExistence(timeout: 10))
            points.tap()
            XCTAssertTrue(app.buttons["imports.point.0"].waitForExistence(timeout: 10))
        case "D14":
            openImportsAndFirstRecord(app)
            let export = app.buttons.matching(identifier: "imports.export").firstMatch
            XCTAssertTrue(export.waitForExistence(timeout: 10))
            export.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        case "D16":
            openImports(app)
            let importButton = app.buttons["imports.import"]
            XCTAssertTrue(importButton.waitForExistence(timeout: 10))
            importButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(3))
        case "D17":
            openImports(app)
            app.buttons["imports.import"].tap()
            XCTAssertTrue(app.buttons["snackbar.dismiss"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons["snackbar.action"].exists)
        case "D18":
            openImports(app)
            app.buttons["imports.import"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["imports.error"].waitForExistence(timeout: 15))
            XCTAssertEqual(app.buttons["imports.error.action"].label, "重試")
        case "D20":
            let edit = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "favoriteRoutes.edit.")).firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 10))
            edit.tap()
            XCTAssertTrue(app.descendants(matching: .any)["favoriteRoutes.editor.content"].waitForExistence(timeout: 10))
            let label = app.textFields["favoriteRoutes.editor.label"]
            XCTAssertTrue(label.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["路線標籤"].exists)
            let info = app.staticTexts.matching(identifier: "favoriteRoutes.editor.source").firstMatch
            let save = app.buttons["favoriteRoutes.editor.save"]
            XCTAssertTrue(info.exists)
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            XCTAssertTrue(save.isHittable)
            let clearLabel = app.buttons["favoriteRoutes.editor.clearLabel"]
            XCTAssertTrue(clearLabel.waitForExistence(timeout: 5))
            XCTAssertTrue(clearLabel.isHittable)
            XCTAssertEqual(label.placeholderValue, "路線名稱")
            XCTAssertFalse(app.keyboards.firstMatch.exists, "D20 opens without automatically presenting the keyboard")
        case "D21":
            selectFavoriteRoutes(app, indexes: [1, 3])
        case "D22":
            selectFavoriteRoutes(app, indexes: [1, 3])
            let delete = app.buttons["favoriteRoutes.deleteSelected"]
            XCTAssertTrue(delete.waitForExistence(timeout: 10))
            XCTAssertTrue(delete.isEnabled)
            delete.tap()
            XCTAssertTrue(app.buttons["snackbar.action"].waitForExistence(timeout: 10))
        case "E3":
            let speed = app.buttons["joystick.speed"]
            XCTAssertTrue(speed.waitForExistence(timeout: 10))
            speed.tap()
            XCTAssertTrue(app.descendants(matching: .any)["route.speed.value"].waitForExistence(timeout: 10))
        default:
            break
        }
    }

    private func openImports(_ app: XCUIApplication) {
        let imports = app.buttons["route.importedRoutes"]
        XCTAssertTrue(imports.waitForExistence(timeout: 10))
        imports.tap()
        XCTAssertTrue(app.descendants(matching: .any)["imports.content"].waitForExistence(timeout: 10))
    }

    private func openImportsAndFirstRecord(_ app: XCUIApplication) {
        openImports(app)
        let record = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "imports.record.")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
    }

    private func selectFavoriteRoutes(_ app: XCUIApplication, indexes: [Int]) {
        XCTAssertTrue(app.descendants(matching: .any)["favoriteRoutes.content"].waitForExistence(timeout: 10))
        let select = app.buttons["favoriteRoutes.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        let checkboxes = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "favoriteRoutes.checkbox."))
        XCTAssertTrue(checkboxes.firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(checkboxes.count, indexes.max() ?? -1)
        for index in indexes {
            let checkbox = checkboxes.element(boundBy: index)
            XCTAssertGreaterThanOrEqual(checkbox.frame.width, 44)
            checkbox.tap()
        }
        XCTAssertEqual(app.staticTexts["已選取 \(indexes.count) 項"].label, "已選取 \(indexes.count) 項")
    }

    private func openSettingsFrame(_ app: XCUIApplication, frame: String) {
        let settingsID: String
        let pageID: String
        switch frame {
        case "F4": settingsID = "settings.location"; pageID = "settings.location.page"
        case "F5": settingsID = "settings.vpn"; pageID = "settings.vpn.page"
        case "F6", "F6.a": settingsID = "settings.background"; pageID = "settings.background.page"
        case "F7": settingsID = "settings.language"; pageID = "settings.language.page"
        case "F8": settingsID = "settings.appearance"; pageID = "settings.appearance.page"
        default: settingsID = "settings.device"; pageID = "settings.device.page"
        }
        let row = app.descendants(matching: .any)[settingsID]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "settings entry missing: \(settingsID)")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)[pageID].waitForExistence(timeout: 10),
                      "settings page missing: \(pageID)")

        if frame == "F6.a" {
            let duration = app.descendants(matching: .any)["settings.background.duration"]
            XCTAssertTrue(duration.waitForExistence(timeout: 10))
            duration.tap()
            XCTAssertTrue(app.buttons["settings.background.duration.confirm"].waitForExistence(timeout: 10))
        }
    }

    private func unavailableReason(for frame: String) -> String {
        switch frame {
        case "R07", "R08": "Requires Mac setup identity or pairing transaction data; the fixture intentionally bypasses setup storage and real device APIs."
        case "B3", "B4", "B5": "Requires deterministic MapKit search, coordinate resolution, and place-sheet state injection."
        case "B6", "B7", "B8", "B9", "B11": "Requires a deterministic position command, connection interruption, or recovery state."
        case "C1", "C2", "C3", "C4": "Requires seeded favorite-place persistence and edit/delete undo state."
        case "D1", "D2", "D2.a", "D3", "D4", "D5", "D6", "D7", "D8", "D10", "D10.a", "D11", "D12", "D13", "D14", "D15", "D16", "D17", "D18", "D19", "D20", "D21", "D22", "D23": "Requires route planning, GPX/share importers, interruption state, or seeded route/favorite data."
        case "E1", "E1.a", "E2", "E2.a", "E3", "E4", "E5": "Requires deterministic joystick, wander-planning, destination, or recovery state."
        case "F1", "F1.a", "F1.b", "F4", "F5", "F6", "F6.a", "F7", "F8", "F9": "Settings pages depend on OS permission/service status and have no injected status fixture yet."
        default: "No deterministic fixture exists yet."
        }
    }

    private var repositoryRoot: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root
    }
}

private struct FigmaCatalog: Decodable {
    let fileKey: String
    let pageNodeId: String
    let frames: [FigmaFrame]
}

private struct FigmaFrame: Decodable {
    let id: String
    let name: String
    let nodeIds: [String: String]
}

private struct ScreenshotManifest: Encodable {
    let fileKey: String
    let pageNodeID: String
    let generatedAt: String
    let captures: [CaptureRecord]
    let unavailable: [UnavailableRecord]
    let figmaConflicts: [String]
}

private struct CaptureRecord: Encodable {
    let frame: String
    let name: String
    let appearance: String
    let figmaNodeID: String
    let screenshotPath: String
    let expectedFigmaPath: String
    let fixtureFlags: [String]
}

private struct UnavailableRecord: Encodable {
    let frame: String
    let name: String
    let reason: String
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
