import Foundation

/// Appearance used to resolve a paired Figma theme token.
public enum GoFlyColorAppearance: String, CaseIterable, Sendable {
    case light
    case dark
}

/// An immutable color value read from the GoFly iOS theme variables.
public struct GoFlyColorToken: Equatable, Sendable {
    public let name: String
    public let lightHex: String
    public let darkHex: String

    public func hex(for appearance: GoFlyColorAppearance) -> String {
        switch appearance {
        case .light: lightHex
        case .dark: darkHex
        }
    }
}

/// Exact-name snapshot of all variables in the three 04 color collections.
/// Names remain the Figma variable paths to make source-to-code audits direct.
public enum GoFlyColorTokens {
    public static let all: [GoFlyColorToken] = [
        GoFlyColorToken(name: "color/action/danger/surface", lightHex: "#D92D20", darkHex: "#B3352F"),
        GoFlyColorToken(name: "color/action/danger/text", lightHex: "#FFFFFF", darkHex: "#E5E5EA"),
        GoFlyColorToken(name: "color/action/disabled/surface", lightHex: "#E7E7EC", darkHex: "#242427"),
        GoFlyColorToken(name: "color/action/primary/surface", lightHex: "#0071E3", darkHex: "#005FC7"),
        GoFlyColorToken(name: "color/action/primary/text", lightHex: "#FFFFFF", darkHex: "#E5E5EA"),
        GoFlyColorToken(name: "color/action/secondary/surface", lightHex: "#D1D1D6", darkHex: "#2C2C2F"),
        GoFlyColorToken(name: "color/canvas", lightHex: "#EEEEF3", darkHex: "#0B0B0D"),
        GoFlyColorToken(name: "color/control/grabber", lightHex: "#C7C7CC", darkHex: "#636366"),
        GoFlyColorToken(name: "color/icon/accent", lightHex: "#0071E3", darkHex: "#4DA3FF"),
        GoFlyColorToken(name: "color/icon/button/disabled", lightHex: "#AEAEB2", darkHex: "#6E6E73"),
        GoFlyColorToken(name: "color/icon/control/disabled", lightHex: "#AEAEB2", darkHex: "#6E6E73"),
        GoFlyColorToken(name: "color/icon/danger", lightHex: "#D92D20", darkHex: "#FF7A70"),
        GoFlyColorToken(name: "color/icon/disabled", lightHex: "#AEAEB2", darkHex: "#6E6E73"),
        GoFlyColorToken(name: "color/icon/input/default", lightHex: "#6A6A6F", darkHex: "#BEBEC2"),
        GoFlyColorToken(name: "color/icon/inverse", lightHex: "#FFFFFF", darkHex: "#000000"),
        GoFlyColorToken(name: "color/icon/outline", lightHex: "#FFFFFF", darkHex: "#1A1A1C"),
        GoFlyColorToken(name: "color/icon/primary", lightHex: "#1C1C1E", darkHex: "#E5E5EA"),
        GoFlyColorToken(name: "color/icon/secondary", lightHex: "#6A6A6F", darkHex: "#98989D"),
        GoFlyColorToken(name: "color/icon/status/secondary", lightHex: "#6A6A6F", darkHex: "#C7C7CC"),
        GoFlyColorToken(name: "color/icon/success", lightHex: "#2E9E4F", darkHex: "#6FC48B"),
        GoFlyColorToken(name: "color/icon/warning", lightHex: "#E39A18", darkHex: "#DDA862"),
        GoFlyColorToken(name: "color/line/border", lightHex: "#C7C7CC", darkHex: "#636366"),
        GoFlyColorToken(name: "color/line/control", lightHex: "#C7C7CC", darkHex: "#636366"),
        GoFlyColorToken(name: "color/line/input/default", lightHex: "#C7C7CC", darkHex: "#636366"),
        GoFlyColorToken(name: "color/line/input/disabled", lightHex: "#D6D6DC", darkHex: "#38383A"),
        GoFlyColorToken(name: "color/line/separator", lightHex: "#D6D6DC", darkHex: "#48484D"),
        GoFlyColorToken(name: "color/line/status/danger", lightHex: "#D92D20", darkHex: "#E0605A"),
        GoFlyColorToken(name: "color/line/status/info", lightHex: "#64748B", darkHex: "#64748B"),
        GoFlyColorToken(name: "color/line/status/success", lightHex: "#2E9E4F", darkHex: "#52A072"),
        GoFlyColorToken(name: "color/line/status/warning", lightHex: "#E39A18", darkHex: "#C48A3F"),
        GoFlyColorToken(name: "color/line/strong", lightHex: "#8E8E93", darkHex: "#8E8E93"),
        GoFlyColorToken(name: "color/map/arterial", lightHex: "#FDE7A6", darkHex: "#5C4F2A"),
        GoFlyColorToken(name: "color/map/arterial-edge", lightHex: "#EFC86A", darkHex: "#6E5C2C"),
        GoFlyColorToken(name: "color/map/building", lightHex: "#EAE6DE", darkHex: "#313133"),
        GoFlyColorToken(name: "color/map/canvas", lightHex: "#F5F3EE", darkHex: "#131315"),
        GoFlyColorToken(name: "color/map/label-area", lightHex: "#7A7466", darkHex: "#8E8E93"),
        GoFlyColorToken(name: "color/map/label-water", lightHex: "#4A8BC2", darkHex: "#6FA3D6"),
        GoFlyColorToken(name: "color/map/marker", lightHex: "#FFFFFF", darkHex: "#1E1E1E"),
        GoFlyColorToken(name: "color/map/marker-outline", lightHex: "#0071E3", darkHex: "#FFFFFF"),
        GoFlyColorToken(name: "color/map/park", lightHex: "#D3EBC4", darkHex: "#1E3322"),
        GoFlyColorToken(name: "color/map/road", lightHex: "#FFFFFF", darkHex: "#3A3A3E"),
        GoFlyColorToken(name: "color/map/road-edge", lightHex: "#E2DDD3", darkHex: "#2C2C2E"),
        GoFlyColorToken(name: "color/map/route", lightHex: "#4DA3FF", darkHex: "#66B3FF"),
        GoFlyColorToken(name: "color/map/water", lightHex: "#A4D1F5", darkHex: "#1A2B3C"),
        GoFlyColorToken(name: "color/primary/100", lightHex: "#E5F1FC", darkHex: "#E6F0FA"),
        GoFlyColorToken(name: "color/primary/300", lightHex: "#7FB8F1", darkHex: "#80B3E6"),
        GoFlyColorToken(name: "color/primary/500", lightHex: "#0071E3", darkHex: "#005FC7"),
        GoFlyColorToken(name: "color/primary/700", lightHex: "#0053A8", darkHex: "#00438F"),
        GoFlyColorToken(name: "color/primary/900", lightHex: "#00305F", darkHex: "#002952"),
        GoFlyColorToken(name: "color/speed/coral", lightHex: "#F16449", darkHex: "#F16449"),
        GoFlyColorToken(name: "color/speed/coral-shadow", lightHex: "#C64935", darkHex: "#C64935"),
        GoFlyColorToken(name: "color/speed/gold", lightHex: "#F8B948", darkHex: "#F8B948"),
        GoFlyColorToken(name: "color/speed/highlight", lightHex: "#EDF8FD", darkHex: "#EDF8FD"),
        GoFlyColorToken(name: "color/speed/navy", lightHex: "#315F8A", darkHex: "#315F8A"),
        GoFlyColorToken(name: "color/speed/skin", lightHex: "#F7CAA4", darkHex: "#F7CAA4"),
        GoFlyColorToken(name: "color/speed/sky", lightHex: "#83C6E8", darkHex: "#83C6E8"),
        GoFlyColorToken(name: "color/surface/card", lightHex: "#FBFBFD", darkHex: "#1A1A1C"),
        GoFlyColorToken(name: "color/surface/control", lightHex: "#DEDEE4", darkHex: "#2C2C2F"),
        GoFlyColorToken(name: "color/surface/control/active", lightHex: "#B9B9BF", darkHex: "#48484D"),
        GoFlyColorToken(name: "color/surface/control/disabled", lightHex: "#E7E7EC", darkHex: "#242427"),
        GoFlyColorToken(name: "color/surface/control/floating", lightHex: "#FBFBFD", darkHex: "#2C2C2F"),
        GoFlyColorToken(name: "color/surface/disabled", lightHex: "#E7E7EC", darkHex: "#242427"),
        GoFlyColorToken(name: "color/surface/input", lightHex: "#FBFBFD", darkHex: "#2C2C2F"),
        GoFlyColorToken(name: "color/surface/navigation", lightHex: "#FBFBFD", darkHex: "#1A1A1C"),
        GoFlyColorToken(name: "color/surface/overlay/background", lightHex: "#FBFBFDF2", darkHex: "#1A1A1CF2"),
        GoFlyColorToken(name: "color/surface/overlay/card", lightHex: "#FBFBFDF2", darkHex: "#1A1A1CF2"),
        GoFlyColorToken(name: "color/surface/overlay/location-card", lightHex: "#FBFBFDF2", darkHex: "#232326F2"),
        GoFlyColorToken(name: "color/surface/overlay/panel", lightHex: "#DEDEE4F2", darkHex: "#2C2C2FF2"),
        GoFlyColorToken(name: "color/surface/overlay/sheet", lightHex: "#FBFBFDF2", darkHex: "#1A1A1CF2"),
        GoFlyColorToken(name: "color/surface/overlay/tab-panel", lightHex: "#FBFBFDF2", darkHex: "#1A1A1CF2"),
        GoFlyColorToken(name: "color/surface/status/danger", lightHex: "#FFF0EE", darkHex: "#4D272A"),
        GoFlyColorToken(name: "color/surface/status/info", lightHex: "#E6EDF6", darkHex: "#1F2A37"),
        GoFlyColorToken(name: "color/surface/status/success", lightHex: "#EAF7EE", darkHex: "#1B2E22"),
        GoFlyColorToken(name: "color/surface/status/warning", lightHex: "#FFF6E6", darkHex: "#352A1B"),
        GoFlyColorToken(name: "color/system/black", lightHex: "#000000", darkHex: "#000000"),
        GoFlyColorToken(name: "color/text/accent", lightHex: "#0066CC", darkHex: "#4DA3FF"),
        GoFlyColorToken(name: "color/text/button/disabled", lightHex: "#AEAEB2", darkHex: "#6E6E73"),
        GoFlyColorToken(name: "color/text/control/disabled", lightHex: "#AEAEB2", darkHex: "#6E6E73"),
        GoFlyColorToken(name: "color/text/danger", lightHex: "#B42318", darkHex: "#FF7A70"),
        GoFlyColorToken(name: "color/text/disabled", lightHex: "#AEAEB2", darkHex: "#6E6E73"),
        GoFlyColorToken(name: "color/text/input/default", lightHex: "#6A6A6F", darkHex: "#BEBEC2"),
        GoFlyColorToken(name: "color/text/inverse", lightHex: "#FFFFFF", darkHex: "#000000"),
        GoFlyColorToken(name: "color/text/primary", lightHex: "#1C1C1E", darkHex: "#E5E5EA"),
        GoFlyColorToken(name: "color/text/secondary", lightHex: "#6A6A6F", darkHex: "#98989D"),
        GoFlyColorToken(name: "color/text/status/secondary", lightHex: "#6A6A6F", darkHex: "#C7C7CC"),
        GoFlyColorToken(name: "color/text/success", lightHex: "#1E7A34", darkHex: "#6FC48B"),
        GoFlyColorToken(name: "color/text/tertiary", lightHex: "#77777C", darkHex: "#8A8A8E"),
        GoFlyColorToken(name: "color/text/warning", lightHex: "#DC750C", darkHex: "#DDA862"),
        GoFlyColorToken(name: "common/black", lightHex: "#000000", darkHex: "#000000"),
        GoFlyColorToken(name: "common/gray/100", lightHex: "#F2F2F7", darkHex: "#F2F2F7"),
        GoFlyColorToken(name: "common/gray/200", lightHex: "#EEEEF0", darkHex: "#EEEEF0"),
        GoFlyColorToken(name: "common/gray/300", lightHex: "#D1D1D6", darkHex: "#D1D1D6"),
        GoFlyColorToken(name: "common/gray/400", lightHex: "#C7C7CC", darkHex: "#C7C7CC"),
        GoFlyColorToken(name: "common/gray/50", lightHex: "#F9F9F9", darkHex: "#F9F9F9"),
        GoFlyColorToken(name: "common/gray/500", lightHex: "#BEBEC2", darkHex: "#BEBEC2"),
        GoFlyColorToken(name: "common/gray/600", lightHex: "#98989D", darkHex: "#98989D"),
        GoFlyColorToken(name: "common/gray/700", lightHex: "#636366", darkHex: "#636366"),
        GoFlyColorToken(name: "common/gray/800", lightHex: "#48484A", darkHex: "#48484A"),
        GoFlyColorToken(name: "common/gray/900", lightHex: "#2C2C2E", darkHex: "#2C2C2E"),
        GoFlyColorToken(name: "common/gray/950", lightHex: "#1C1C1E", darkHex: "#1C1C1E"),
        GoFlyColorToken(name: "common/transparent", lightHex: "#FFFFFF00", darkHex: "#FFFFFF00"),
        GoFlyColorToken(name: "common/white", lightHex: "#FFFFFF", darkHex: "#FFFFFF")
    ]

    private static let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    public static func token(named name: String) -> GoFlyColorToken? {
        byName[name]
    }

    public static func hex(named name: String, appearance: GoFlyColorAppearance) -> String? {
        token(named: name)?.hex(for: appearance)
    }
}

