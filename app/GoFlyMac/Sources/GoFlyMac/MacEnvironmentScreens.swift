import AppKit
import SwiftUI
import GoFlyMacCore

private func macText(_ key: String) -> String { MacLocalization.text(key) }

struct MacEnvironmentScreen: View {
    @Bindable var model: MacAppModel
    let step: MacEnvironmentStep

    var body: some View {
        HStack(spacing: 0) {
            EnvironmentProgressSidebar(model: model, selected: step)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        screenContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 48).padding(.top, 20).padding(.bottom, 32)
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoFlyStyle.canvas)
        }
        .background(GoFlyStyle.canvas)
        .accessibilityIdentifier("environment-\(step.rawValue)")
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                model.checkEnvironment()
            }
        }
    }

    private var crumb: String {
        switch step {
        case .overview: macText("env.e01.crumb")
        case .updateMacOS: macText("env.e02.crumb")
        case .getXcode, .waitForXcode: macText("env.e03.crumb")
        case .firstLaunch: macText("env.e05.crumb")
        case .iosPlatform: macText("env.e06.crumb")
        case .appleAccount: macText("env.e07.crumb")
        case .selectTeam: macText("env.e08.crumb")
        }
    }

    private var title: String {
        switch step {
        case .overview: macText("env.e01.title")
        case .updateMacOS: macText("env.e02.title")
        case .getXcode: macText("env.e03.title")
        case .waitForXcode: macText("env.e04.title")
        case .firstLaunch: macText("env.e05.title")
        case .iosPlatform: macText("env.e06.title")
        case .appleAccount: macText("env.e07.title")
        case .selectTeam: macText("env.e08.title")
        }
    }

    private var subtitle: String {
        switch step {
        case .overview: macText("env.e01.subtitle")
        case .updateMacOS: macText("env.e02.subtitle")
        case .getXcode: macText("env.e03.subtitle")
        case .waitForXcode: macText("env.e04.subtitle")
        case .firstLaunch: macText("env.e05.subtitle")
        case .iosPlatform: macText("env.e06.subtitle")
        case .appleAccount: macText("env.e07.subtitle")
        case .selectTeam: macText("env.e08.subtitle")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(crumb).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                Spacer(minLength: 12)
                if step == .iosPlatform {
                    Text(macText("env.e06.badge"))
                        .font(GoFlyStyle.font(10, bold: true))
                        .foregroundStyle(MacColorSystem.annotation)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(MacColorSystem.warningSurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(MacColorSystem.warningBorder, lineWidth: 0.75))
                }
            }
            Text(title).font(GoFlyStyle.font(28, bold: true)).padding(.top, 8)
            Text(subtitle).font(GoFlyStyle.font(14)).foregroundStyle(GoFlyStyle.muted)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
        }
        .padding(.bottom, step == .overview ? 28 : 26)
    }

    @ViewBuilder private var screenContent: some View {
        switch step {
        case .overview:
            EnvironmentOverview(model: model)
        case .updateMacOS:
            EnvironmentGuideColumns(rows: [
                .init(title: "env.e02.step1", detail: "env.e02.step1.detail"),
                .init(title: "env.e02.step2", detail: "env.e02.step2.detail"),
                .init(title: "env.e02.step3", detail: "env.e02.step3.detail"),
                .init(title: "env.e02.step4", detail: "env.e02.step4.detail"),
            ]) {
                SystemWindowPreview(kind: .softwareUpdate, caption: "env.e02.caption")
            }
            .overlay(alignment: .top) {
                EnvironmentInfoBanner(title: "env.e02.banner.title", detail: "env.e02.banner.body", kind: .warning)
                    .offset(y: -84)
            }
            .padding(.top, 84)
        case .getXcode:
            EnvironmentGuideColumns(rows: [
                .init(title: "env.e03.step1"),
                .init(title: "env.e03.step2", detail: "env.e03.step2.detail"),
                .init(title: "env.e03.step3", detail: "env.e03.step3.detail"),
                .init(title: "env.e03.step4", detail: "env.e03.step4.detail"),
            ]) {
                SystemWindowPreview(kind: .appStore, caption: "env.e03.caption")
            }
        case .waitForXcode:
            VStack(spacing: 0) {
                EnvironmentStatusRow(icon: "ellipsis", title: "env.e04.row.download", detail: "env.e04.row.waiting", pending: true)
                Rule()
                EnvironmentStatusRow(icon: "circle", title: "env.e04.row.detect", detail: "env.e04.row.advance", pending: false)
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 20)
            EnvironmentInfoBanner(title: "env.e04.banner.title", detail: "env.e04.banner.body", kind: .info)
        case .firstLaunch:
            EnvironmentGuideColumns(rows: [
                .init(title: "env.e05.step1"),
                .init(title: "env.e05.step2"),
                .init(title: "env.e05.step3", detail: "env.e05.step3.detail"),
                .init(title: "env.e05.step4", detail: "env.e05.step4.detail"),
            ]) {
                SystemWindowPreview(kind: .license, caption: "env.e05.caption")
            }
        case .iosPlatform:
            EnvironmentGuideColumns(rows: [
                .init(title: "env.e06.step1", detail: "env.e06.step1.detail"),
                .init(title: "env.e06.step2"),
                .init(title: "env.e06.step3", detail: "env.e06.step3.detail"),
                .init(title: "env.e06.step4", detail: "env.e06.step4.detail"),
            ]) {
                SystemWindowPreview(kind: .platforms, caption: "env.e06.caption")
            }
        case .appleAccount:
            EnvironmentGuideColumns(rows: [
                .init(title: "env.e07.step1", detail: "env.e07.step1.detail"),
                .init(title: "env.e07.step2"),
                .init(title: "env.e07.step3"),
                .init(title: "env.e07.step4", detail: "env.e07.step4.detail"),
                .init(title: "env.e07.step5", detail: "env.e07.step5.detail"),
            ]) {
                SystemWindowPreview(kind: .accounts, caption: "env.e07.caption")
            }
        case .selectTeam:
            EnvironmentTeamSelection(model: model)
        }
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            switch step {
            case .overview:
                EnvironmentActionButton(title: "env.e01.action", primary: true,
                                        enabled: model.canBeginEnvironmentPreparation) {
                    model.startEnvironmentPreparation()
                }
            case .updateMacOS:
                EnvironmentActionButton(title: "env.common.retry") { model.checkEnvironment() }
                EnvironmentActionButton(title: "env.e02.action", primary: true) { openSoftwareUpdate() }
            case .getXcode:
                EnvironmentActionButton(title: "env.common.retry") { model.checkEnvironment() }
                EnvironmentActionButton(title: "env.e03.action", primary: true) {
                    if NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/id497799835")!) {
                        model.waitForXcodeInstall()
                    }
                }
            case .waitForXcode:
                EnvironmentActionButton(title: "env.common.retry") { model.checkEnvironment() }
                EnvironmentActionButton(title: "env.e04.action", enabled: false) {}
            case .firstLaunch, .iosPlatform:
                EnvironmentActionButton(title: "env.common.retry") { model.checkEnvironment() }
                EnvironmentActionButton(title: step == .firstLaunch ? "env.e05.action" : "env.e06.action",
                                        primary: true) { openXcode() }
            case .appleAccount:
                EnvironmentActionButton(title: "env.e07.action.create") {
                    _ = NSWorkspace.shared.open(URL(string: "https://account.apple.com/account")!)
                }
                EnvironmentActionButton(title: "env.common.retry") { model.checkEnvironment() }
                EnvironmentActionButton(title: "env.e07.action.settings", primary: true) { openXcode() }
            case .selectTeam:
                EnvironmentActionButton(title: "env.e08.action", primary: true,
                                        enabled: model.selectedTeam != nil) {
                    model.returnToDevices()
                }
            }
        }
        .padding(.horizontal, 48).frame(height: 80)
        .overlay(alignment: .top) { Rule() }
    }

    private func openXcode() {
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app"))
    }

    private func openSoftwareUpdate() {
        _ = NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)
    }
}

private struct EnvironmentProgressSidebar: View {
    @Bindable var model: MacAppModel
    let selected: MacEnvironmentStep

    private let items: [(MacEnvironmentStep, String, String, Int)] = [
        (.updateMacOS, "env.step.macos", "macos-version", 1),
        (.getXcode, "env.step.xcode", "xcode-installed", 2),
        (.firstLaunch, "env.step.components", "xcode-first-launch", 3),
        (.iosPlatform, "env.step.ios", "ios-platform", 4),
        (.appleAccount, "env.step.account", "apple-account", 5),
        (.selectTeam, "env.step.team", "apple-account", 6),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("GoFly").font(GoFlyStyle.font(17, bold: true))
                Text(macText("app.forMac")).font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted)
            }
            .padding(.horizontal, 24).padding(.top, 40).padding(.bottom, 42)
            Text(macText("env.nav.title")).font(GoFlyStyle.font(12, bold: true)).foregroundStyle(GoFlyStyle.muted)
                .padding(.horizontal, 24).padding(.bottom, 10)
            ForEach(items, id: \.0) { step, titleKey, checkID, number in
                let passed = isPassed(step, checkID: checkID)
                Button { model.navigate(.environment(step)) } label: {
                    HStack(spacing: 10) {
                        statusIcon(passed: passed, current: selected == step, number: number)
                        Text(macText(titleKey)).font(GoFlyStyle.font(12, bold: selected == step))
                            .foregroundStyle(GoFlyStyle.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(height: 34).frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).goFlyRowFocus().padding(.horizontal, 12)
            }
            Spacer(minLength: 12)
        }
        .frame(width: 240).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(GoFlyStyle.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(GoFlyStyle.divider).frame(width: 0.5) }
    }

    @ViewBuilder private func statusIcon(passed: Bool, current: Bool, number: Int) -> some View {
        if passed {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(GoFlyStyle.success)
                .frame(width: 20, height: 20)
        } else {
            Text(String(number)).font(GoFlyStyle.font(10, bold: current))
                .foregroundStyle(current ? MacColorSystem.primaryActionText : GoFlyStyle.muted)
                .frame(width: 20, height: 20)
                .background(current ? MacColorSystem.primaryActionSurface : GoFlyStyle.disabledSurface, in: Circle())
        }
    }

    private func isPassed(_ step: MacEnvironmentStep, checkID: String) -> Bool {
        if step == .selectTeam { return model.selectedTeam != nil }
        return model.environment?.checks.first(where: { $0.id == checkID })?.passed == true
    }
}

private struct EnvironmentOverview: View {
    @Bindable var model: MacAppModel

    private var rows: [(String, String, String, Int)] {
        [
            ("env.e01.row.macos", "macos-version", "macos", 1),
            ("env.e01.row.space", "available-space", "space", 1),
            ("env.e01.row.xcode", "xcode-installed", "xcode", 2),
            ("env.e01.row.components", "xcode-first-launch", "components", 3),
            ("env.e01.row.ios", "ios-platform", "ios", 4),
            ("env.e01.row.account", "apple-account", "account", 5),
            ("env.e01.row.team", "team", "team", 6),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let check = model.environment?.checks.first(where: { $0.id == row.1 })
                let passed = row.2 == "team" ? model.selectedTeam != nil : check?.passed == true
                HStack(spacing: 14) {
                    overviewStatus(passed: passed, index: row.3, failedStorage: row.2 == "space" && check?.passed == false)
                    Text(macText(row.0)).font(GoFlyStyle.font(13, bold: true))
                    Spacer(minLength: 16)
                    Text(overviewDetail(row.2, check: check)).font(GoFlyStyle.font(12))
                        .foregroundStyle(row.2 == "space" && !passed ? GoFlyStyle.warning : GoFlyStyle.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 18).frame(height: 50)
                if row.0 != rows.last?.0 { Rule().padding(.leading, 52) }
            }
        }
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 20)
        EnvironmentInfoBanner(title: "env.e01.banner.title", detail: "env.e01.banner.body", kind: .info)
    }

    @ViewBuilder private func overviewStatus(passed: Bool, index: Int, failedStorage: Bool) -> some View {
        if passed {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(GoFlyStyle.success)
                .frame(width: 20, height: 20)
        } else if failedStorage {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(GoFlyStyle.warning)
                .frame(width: 20, height: 20)
        } else {
            Text(String(index)).font(GoFlyStyle.font(10, bold: true)).foregroundStyle(GoFlyStyle.muted)
                .frame(width: 20, height: 20).background(GoFlyStyle.disabledSurface, in: Circle())
        }
    }

    private func overviewDetail(_ kind: String, check: EnvironmentCheck?) -> String {
        switch kind {
        case "macos": return check?.passed == true ? macText("env.status.macosReady") : macText("env.status.macosNeedsUpdate")
        case "space": return check?.detail ?? macText("env.status.unknown")
        case "xcode": return check?.passed == true ? macText("env.status.xcodeInstalled") : macText("env.status.xcodeMissing")
        case "components": return check?.passed == true ? macText("env.status.componentsReady") : macText("env.status.componentsMissing")
        case "ios": return check?.passed == true ? macText("env.status.iosReady") : macText("env.status.iosMissing")
        case "account": return check?.passed == true ? macText("env.status.accountReady") : macText("env.status.accountMissing")
        case "team":
            if let team = model.selectedTeam { return team.teamName }
            return model.environment?.teams.isEmpty == true ? macText("env.status.teamAutomatic") : macText("env.status.teamChoose")
        default: return macText("env.status.unknown")
        }
    }
}

private struct EnvironmentInfoBanner: View {
    enum Kind { case info, warning }
    let title: String
    let detail: String
    let kind: Kind

    private var foreground: Color { kind == .info ? MacColorSystem.info : MacColorSystem.warning }
    private var background: Color { kind == .info ? MacColorSystem.infoSurface : MacColorSystem.warningSurface }
    private var border: Color { kind == .info ? MacColorSystem.infoBorder : MacColorSystem.warningBorder }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind == .info ? "info.circle.fill" : "exclamationmark.circle.fill")
                .font(GoFlyStyle.font(14, bold: true)).foregroundStyle(foreground).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(macText(title)).font(GoFlyStyle.font(12, bold: true)).foregroundStyle(GoFlyStyle.ink)
                Text(macText(detail)).font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted)
                    .lineSpacing(1).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 0.75))
    }
}

private struct GuideRow: Identifiable {
    let id = UUID()
    let title: String
    var detail: String? = nil
}

private struct EnvironmentStatusRow: View {
    let icon: String
    let title: String
    let detail: String
    let pending: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(GoFlyStyle.font(10, bold: true))
                .foregroundStyle(pending ? MacColorSystem.primaryActionText : GoFlyStyle.disabled)
                .frame(width: 20, height: 20)
                .background(pending ? MacColorSystem.primaryActionSurface : GoFlyStyle.disabledSurface, in: Circle())
            Text(macText(title)).font(GoFlyStyle.font(13, bold: true))
            Spacer(minLength: 12)
            Text(macText(detail)).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
        }
        .padding(.horizontal, 18).frame(height: 50)
    }
}

private struct EnvironmentGuideColumns<Preview: View>: View {
    let rows: [GuideRow]
    @ViewBuilder let preview: Preview

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                EnvironmentInstructionCard(rows: rows).frame(width: 420)
                Text("點這裡").font(GoFlyStyle.font(10, bold: true)).foregroundStyle(MacColorSystem.accentText)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(MacColorSystem.annotation, in: Capsule()).frame(width: 64)
                    .padding(.top, 188)
                preview.frame(width: 300)
            }
            VStack(alignment: .leading, spacing: 24) {
                EnvironmentInstructionCard(rows: rows)
                preview.frame(maxWidth: 300)
            }
        }
    }
}

private struct EnvironmentInstructionCard: View {
    let rows: [GuideRow]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(macText(row.title)).font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = row.detail {
                        Text(macText(detail)).font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, row.detail == nil ? 13 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                if index < rows.count - 1 { Rule().padding(.leading, 18) }
            }
        }
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SystemWindowPreview: View {
    enum Kind { case softwareUpdate, appStore, license, platforms, accounts }
    let kind: Kind
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mockWindow
                .frame(height: 210)
                .background(MacColorSystem.mockWindow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GoFlyStyle.line, lineWidth: 0.75))
            Text(macText(caption)).font(GoFlyStyle.font(10)).foregroundStyle(GoFlyStyle.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 300)
    }

    @ViewBuilder private var mockWindow: some View {
        switch kind {
        case .softwareUpdate:
            VStack(spacing: 8) {
                mockIcon
                Text(macText("env.e02.mock.title")).font(GoFlyStyle.font(12, bold: true))
                Text(macText("env.e02.mock.body")).font(GoFlyStyle.font(10)).foregroundStyle(GoFlyStyle.muted)
                Text(macText("env.e02.mock.note")).font(GoFlyStyle.font(9)).foregroundStyle(GoFlyStyle.muted)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    MockSystemButton(title: "env.e02.mock.later")
                    MockSystemButton(title: "env.e02.mock.update", blue: true, highlighted: true)
                }
            }
            .padding(16)
        case .appStore:
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    mockIcon.frame(width: 62, height: 62)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(macText("env.e03.mock.title")).font(GoFlyStyle.font(14, bold: true))
                        Text(macText("env.e03.mock.subtitle")).font(GoFlyStyle.font(10)).foregroundStyle(GoFlyStyle.muted)
                        Text(macText("env.e03.mock.free")).font(GoFlyStyle.font(9)).foregroundStyle(GoFlyStyle.muted)
                    }
                    Spacer(minLength: 0)
                }
                MockSystemButton(title: "env.e03.mock.get", blue: true, highlighted: true)
                Spacer(minLength: 0)
                Text(macText("env.e03.mock.store")).font(GoFlyStyle.font(9)).foregroundStyle(GoFlyStyle.muted)
            }
            .padding(16)
        case .license:
            VStack(spacing: 10) {
                mockIcon.frame(width: 42, height: 42)
                Text(macText("env.e05.mock.title")).font(GoFlyStyle.font(10, bold: true)).multilineTextAlignment(.center)
                Text(macText("env.e05.mock.body")).font(GoFlyStyle.font(9)).foregroundStyle(GoFlyStyle.muted).multilineTextAlignment(.center)
                Spacer(minLength: 0)
                MockSystemButton(title: "env.e05.mock.cancel")
                MockSystemButton(title: "env.e05.mock.accept", blue: true, highlighted: true)
            }
            .padding(16)
        case .platforms:
            VStack(spacing: 10) {
                mockIcon.frame(width: 42, height: 42)
                Text(macText("env.e06.mock.title")).font(GoFlyStyle.font(10, bold: true))
                Text(macText("env.e06.mock.body")).font(GoFlyStyle.font(9)).foregroundStyle(GoFlyStyle.muted)
                Text(macText("env.e06.mock.note")).font(GoFlyStyle.font(9)).foregroundStyle(GoFlyStyle.muted)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    MockSystemButton(title: "env.e06.mock.later")
                    MockSystemButton(title: "env.e06.mock.install", blue: true, highlighted: true)
                }
            }
            .padding(16)
        case .accounts:
            VStack(spacing: 8) {
                Text(macText("env.e07.mock.title")).font(GoFlyStyle.font(11, bold: true))
                HStack(spacing: 10) {
                    VStack(spacing: 12) {
                        Text(macText("env.e07.mock.empty")).font(GoFlyStyle.font(9)).foregroundStyle(GoFlyStyle.muted)
                        Spacer(minLength: 0)
                        Image(systemName: "plus").font(GoFlyStyle.font(10, bold: true))
                            .foregroundStyle(MacColorSystem.accent)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(MacColorSystem.annotation, lineWidth: 1.5))
                    }
                    .frame(width: 92, height: 116)
                    .padding(8)
                    .background(MacColorSystem.mockContent, in: RoundedRectangle(cornerRadius: 8))
                    VStack {
                        Text(macText("env.e07.mock.hint")).font(GoFlyStyle.font(9)).foregroundStyle(GoFlyStyle.muted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 12)
                }
                HStack { Text("點這裡").font(GoFlyStyle.font(9, bold: true)).foregroundStyle(MacColorSystem.accentText).padding(.horizontal, 10).padding(.vertical, 4).background(MacColorSystem.annotation, in: Capsule()); Spacer() }
            }
            .padding(12)
        }
    }

    private var mockIcon: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(MacColorSystem.mockContent)
            .frame(width: 42, height: 42)
    }
}

private struct MockSystemButton: View {
    let title: String
    var blue = false
    var highlighted = false

    var body: some View {
        Text(macText(title)).font(GoFlyStyle.font(10, bold: blue))
            .foregroundStyle(blue ? MacColorSystem.accentText : GoFlyStyle.ink)
            .frame(maxWidth: .infinity).frame(height: 30)
            .background(blue ? MacColorSystem.accent : MacColorSystem.mockContent,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                highlighted ? MacColorSystem.annotation : GoFlyStyle.border, lineWidth: highlighted ? 2 : 0.75))
    }
}

private struct EnvironmentTeamSelection: View {
    @Bindable var model: MacAppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array((model.environment?.teams ?? []).enumerated()), id: \.element.teamID) { index, team in
                    Button { model.selectTeam(team.teamID) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: model.selectedTeamID == team.teamID ? "largecircle.fill.circle" : "circle")
                                .font(GoFlyStyle.font(14)).foregroundStyle(GoFlyStyle.ink)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(team.teamName + "（" + macText(team.isFreeProvisioningTeam ? "env.e08.free.label" : "env.e08.paid.label") + "）")
                                    .font(GoFlyStyle.font(13, bold: true)).foregroundStyle(GoFlyStyle.ink)
                                Text(macText(team.isFreeProvisioningTeam ? "env.e08.free.detail" : "env.e08.paid.detail"))
                                    .font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).goFlyRowFocus()
                    if index < (model.environment?.teams.count ?? 0) - 1 { Rule().padding(.leading, 48) }
                }
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 20)
            EnvironmentInfoBanner(title: "env.e08.warning.title", detail: "env.e08.warning.body", kind: .warning)
        }
    }
}

struct MacEnvironmentSummaryScreen: View {
    @Bindable var model: MacAppModel
    private let rows: [(String, String)] = [
        ("env.e09.status.macos", "macos-version"),
        ("env.e09.status.space", "available-space"),
        ("env.e09.status.xcode", "xcode-installed"),
        ("env.e09.status.components", "xcode-first-launch"),
        ("env.e09.status.ios", "ios-platform"),
        ("env.e09.status.account", "apple-account"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            MacDeviceSidebar(model: model)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(macText("env.common.environment")).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                        Text(model.environment?.ready == true ? macText("env.e09.title") : macText("env.e09.title.pending"))
                            .font(GoFlyStyle.font(28, bold: true)).padding(.top, 8)
                        Text(macText("env.e09.subtitle")).font(GoFlyStyle.font(14)).foregroundStyle(GoFlyStyle.muted)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 5).padding(.bottom, 26)
                        checkList
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 48).padding(.top, 20).padding(.bottom, 32)
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoFlyStyle.canvas)
        }
        .background(GoFlyStyle.canvas)
    }

    private var checkList: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let check = model.environment?.checks.first(where: { $0.id == row.1 })
                EnvironmentSummaryRow(title: row.0, detail: summaryDetail(row.1, check: check),
                                      passed: check?.passed == true) {
                    if let destination = route(for: row.1) { model.navigate(destination) }
                }
                Rule().padding(.leading, 42)
            }
            EnvironmentSummaryRow(title: "env.e09.status.team",
                                  detail: teamDetail,
                                  passed: model.selectedTeam != nil) {
                model.navigate(.environment(.selectTeam))
            }
        }
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var teamDetail: String {
        guard let team = model.selectedTeam else { return model.environment?.teams.isEmpty == true ? macText("env.status.accountMissing") : macText("env.status.teamChoose") }
        let kind = macText(team.isFreeProvisioningTeam ? "env.e08.free.label" : "env.e08.paid.label")
        return "\(team.teamName)（\(kind)）"
    }

    private func summaryDetail(_ id: String, check: EnvironmentCheck?) -> String {
        if let check, check.status == .unknown { return macText("env.status.unknown") }
        if id == "available-space" { return check?.detail ?? macText("env.status.unknown") }
        switch id {
        case "macos-version": return check?.passed == true ? macText("env.status.macosReady") : macText("env.status.macosNeedsUpdate")
        case "xcode-installed": return check?.passed == true ? macText("env.status.xcodeInstalled") : macText("env.status.xcodeMissing")
        case "xcode-first-launch": return check?.passed == true ? macText("env.status.componentsReady") : macText("env.status.componentsMissing")
        case "ios-platform": return check?.passed == true ? macText("env.status.iosReady") : macText("env.status.iosMissing")
        case "apple-account": return check?.passed == true ? macText("env.status.accountReady") : macText("env.status.accountMissing")
        default: return check?.detail ?? macText("env.status.unknown")
        }
    }

    private func route(for id: String) -> MacRoute? {
        switch id {
        case "macos-version": .environment(.updateMacOS)
        case "available-space": .environment(.overview)
        case "xcode-installed": .environment(.getXcode)
        case "xcode-first-launch": .environment(.firstLaunch)
        case "ios-platform": .environment(.iosPlatform)
        case "apple-account": .environment(.appleAccount)
        default: nil
        }
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            EnvironmentActionButton(title: "env.e09.action.team", enabled: (model.environment?.teams.count ?? 0) > 1) {
                model.navigate(.environment(.selectTeam))
            }
            EnvironmentActionButton(title: "env.common.retry") { model.checkEnvironment() }
            EnvironmentActionButton(title: "env.e09.action.return", primary: true) { model.returnToDevices() }
        }
        .padding(.horizontal, 48).frame(height: 80).overlay(alignment: .top) { Rule() }
    }
}

private struct EnvironmentSummaryRow: View {
    let title: String
    let detail: String
    let passed: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(passed ? GoFlyStyle.success : GoFlyStyle.warning)
                .frame(width: 20, height: 20)
            Text(macText(title)).font(GoFlyStyle.font(13, bold: true))
            Spacer(minLength: 16)
            Text(detail).font(GoFlyStyle.font(12))
                .foregroundStyle(passed ? GoFlyStyle.muted : GoFlyStyle.warning)
                .lineLimit(1).minimumScaleFactor(0.8)
            if !passed {
                Button(action: action) {
                    Text(macText("env.e09.action.go")).font(GoFlyStyle.font(11, bold: true))
                        .foregroundStyle(MacColorSystem.accent).padding(.leading, 6)
                }
                .buttonStyle(.plain).goFlyRowFocus()
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
    }
}

struct MacDeviceSidebar: View {
    @Bindable var model: MacAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("GoFly").font(GoFlyStyle.font(22, bold: true))
                Text(macText("app.forMac")).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
            }
            .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 26)
            HStack(spacing: 8) {
                Text(macText("device.sidebar.title")).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                Spacer(minLength: 0)
                Button { model.refreshDevices() } label: {
                    Label(macText("device.sidebar.search"), systemImage: "arrow.clockwise")
                        .font(GoFlyStyle.font(11, bold: true)).padding(.horizontal, 10).frame(height: 28)
                        .background(GoFlyStyle.secondarySurface, in: Capsule())
                }
                .buttonStyle(.plain).disabled(model.busy).accessibilityIdentifier("device-rescan")
            }
            .padding(.horizontal, 24)
            if model.sidebarDevices.isEmpty {
                Text(macText("device.sidebar.empty")).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    .padding(.horizontal, 24).padding(.top, 16)
            } else {
                ForEach(model.sidebarDevices, id: \.connectionID) { device in
                    let selected = model.selectedID?.lowercased() == device.id.lowercased()
                        && model.selectedTransport == device.transport
                    Button {
                        model.openDevice(device)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.displayName).font(GoFlyStyle.font(13, bold: true)).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(device.connectionName)
                                Text("·")
                                Text(expiryText(for: device)).foregroundStyle(expiryColor(for: device))
                            }
                            .font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected ? MacColorSystem.selectionSurface : MacColorSystem.transparent,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            if selected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(GoFlyStyle.border, lineWidth: 0.75)
                            }
                        }
                    }
                    .buttonStyle(.plain).goFlyRowFocus(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 12).padding(.top, 6)
                    .accessibilityIdentifier("device-\(device.connectionID)")
                }
            }
            Spacer(minLength: 16)
            Button { model.navigate(.environmentSummary) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(model.environment?.ready == true ? GoFlyStyle.success : GoFlyStyle.warning)
                            .frame(width: 8, height: 8)
                        Text(macText(model.environment?.ready == true ? "device.sidebar.environment.ready" : "device.sidebar.environment.pending"))
                            .font(GoFlyStyle.font(12, bold: true))
                    }
                    Text(deviceTeamSummary).font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                        .lineLimit(1).padding(.leading, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).goFlyRowFocus().overlay(alignment: .top) { Rule().padding(.horizontal, 12) }
            .accessibilityIdentifier("environment-summary")
        }
        .frame(width: 240)
        .background(GoFlyStyle.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(GoFlyStyle.divider).frame(width: 0.5) }
    }

    private var deviceTeamSummary: String {
        guard let team = model.selectedTeam else { return macText("device.sidebar.team.pending") }
        let kind = macText(team.isFreeProvisioningTeam ? "env.e08.free.label" : "env.e08.paid.label")
        return "\(team.teamName)（\(kind)）"
    }

    private func expiryText(for device: ConnectedDevice) -> String {
        let selected = model.selectedID?.lowercased() == device.id.lowercased()
            && model.selectedTransport == device.transport
        if selected {
            if model.route == .install {
                if model.setup?.snapshot?.isComplete == true {
                    return model.signingExpiryText(for: device)
                }
                if model.setup?.progressStage == .handoff {
                    return macText("setup.sidebar.waiting")
                }
                if model.setup?.progressStage != nil {
                    return macText("setup.sidebar.installing")
                }
            }
            switch model.devicePageState {
            case .restartRequired:
                return macText(model.setup?.mode == .renew ? "device.d14.sidebar.renew" : "device.d14.sidebar.install")
            case .trustRequired, .developerModeRequired, .readyToInstall, .wifiNeedsUSB:
                return macText("device.status.notInstalledGoFly")
            case .wifiUnavailable:
                if let days = model.signingDaysRemaining {
                    return String(format: macText("device.sidebar.wifiMissing"), days)
                }
                return macText("device.sidebar.wifiMissingUnknown")
            default:
                break
            }
        }
        guard let days = model.signingDaysRemaining(for: device) else { return macText("device.expiry.unknown") }
        return days < 0 ? macText("device.expiry.expired") : String(format: macText("device.expiry.days"), days)
    }

    private func expiryColor(for device: ConnectedDevice) -> Color {
        if model.selectedID?.lowercased() == device.id.lowercased(),
           model.selectedTransport == device.transport, model.devicePageState == .restartRequired {
            return MacColorSystem.annotation
        }
        guard let days = model.signingDaysRemaining(for: device) else { return GoFlyStyle.muted }
        if days < 0 { return MacColorSystem.error }
        if days < 4 { return MacColorSystem.annotation }
        return GoFlyStyle.muted
    }
}

private struct EnvironmentActionButton: View {
    let title: String
    var primary = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(macText(title)).font(GoFlyStyle.font(12, bold: true))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 16).frame(height: 36)
                .foregroundStyle(enabled ? (primary ? MacColorSystem.primaryActionText : GoFlyStyle.ink) : GoFlyStyle.disabled)
                .background(buttonSurface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).disabled(!enabled).goFlyRowFocus(Capsule())
    }

    private var buttonSurface: Color {
        if !enabled { return GoFlyStyle.disabledSurface }
        return primary ? MacColorSystem.primaryActionSurface : GoFlyStyle.secondarySurface
    }
}
