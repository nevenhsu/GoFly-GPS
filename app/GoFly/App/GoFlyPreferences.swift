import Foundation
import GoFlyCore
import Observation
import SwiftUI

enum GoFlyLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case zhHant = "zh-Hant"
    case zhHans = "zh-Hans"

    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .system: goFlyString("settings.system")
        case .en: "English"
        case .zhHant: "繁體中文"
        case .zhHans: "简体中文"
        }
    }
}

enum GoFlyAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .system: goFlyString("settings.system")
        case .light: goFlyString("settings.appearance.light")
        case .dark: goFlyString("settings.appearance.dark")
        }
    }
}

/// Selected presentation values only. Reading preferences never changes disk or movement owners.
@MainActor @Observable
final class GoFlyPreferences {
    static let shared = GoFlyPreferences()
    private(set) var language: GoFlyLanguage
    private(set) var appearance: GoFlyAppearance
    /// Shared by route, joystick and wander so a change in one shows in the others.
    private(set) var movementSpeed: RouteSpeed
    /// Background run time for fixed position, round trip and wander (seconds).
    private(set) var backgroundRunSeconds: Int
    /// Wander range (Figma E2.b): radius and circle visibility survive relaunch. The anchor does
    /// not: after a relaunch the position can be anywhere, so the first position becomes it.
    private(set) var wanderRadius: WanderRadius
    private(set) var wanderRangeVisible: Bool
    private var systemLanguages: [String]
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "gofly.preferences.v1"

    private init() {
        let store = GoFlyUITestOverrides.preferencesDefaults() ?? UserDefaults.standard
        defaults = store
        let saved = store.dictionary(forKey: Self.storageKey)
        language = (saved?["language"] as? String).flatMap(GoFlyLanguage.init(rawValue:)) ?? .system
        appearance = (saved?["appearance"] as? String).flatMap(GoFlyAppearance.init(rawValue:)) ?? .system
        movementSpeed = (saved?["movementSpeed"] as? Int).flatMap(RouteSpeed.init(kilometersPerHour:)) ?? .standard
        backgroundRunSeconds = Self.applyBackgroundRunSeconds(
            (saved?["backgroundRunSeconds"] as? Int) ?? Int(BackgroundRunDuration.defaultSeconds))
        wanderRadius = Self.decodeRadius(saved)
        wanderRangeVisible = (saved?["wanderRangeVisible"] as? Bool) ?? true
        systemLanguages = Locale.preferredLanguages
    }

    private static func decodeRadius(_ saved: [String: Any]?) -> WanderRadius {
        (saved?["wanderRadiusKm"] as? Double).map { WanderRadius(kilometers: $0) } ?? .default
    }

    var effectiveLanguage: String {
        if language != .system { return language.rawValue }
        return Bundle.preferredLocalizations(
            from: ["en", "zh-Hant", "zh-Hans"], forPreferences: systemLanguages
        ).first ?? "en"
    }

    var locale: Locale { Locale(identifier: effectiveLanguage) }
    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func setLanguage(_ value: GoFlyLanguage) {
        guard language != value else { return }
        language = value
        save()
    }

    func setAppearance(_ value: GoFlyAppearance) {
        guard appearance != value else { return }
        appearance = value
        save()
    }

    func setMovementSpeed(_ value: RouteSpeed) {
        guard movementSpeed != value else { return }
        movementSpeed = value
        save()
    }

    func setWanderRange(radius: WanderRadius, isVisible: Bool) {
        guard radius != wanderRadius || isVisible != wanderRangeVisible else { return }
        wanderRadius = radius
        wanderRangeVisible = isVisible
        save()
    }

    func setBackgroundRunSeconds(_ value: Int) {
        let clamped = Self.applyBackgroundRunSeconds(value)
        guard backgroundRunSeconds != clamped else { return }
        backgroundRunSeconds = clamped
        save()
    }

    /// Clamps a run time and mirrors it to Core, which reads it off the main actor.
    private static func applyBackgroundRunSeconds(_ value: Int) -> Int {
        let clamped = Int(BackgroundRunDuration.clamp(TimeInterval(value)))
        BackgroundRunDuration.shared.seconds = TimeInterval(clamped)
        return clamped
    }

    /// Re-reads the one persisted preferences dictionary after Core activates
    /// a restore. Unknown keys and the restore marker stay in UserDefaults;
    /// this method only refreshes the presentation projection.
    func refreshPersistedValues() {
        let saved = defaults.dictionary(forKey: Self.storageKey)
        if let value = saved?["language"] as? String,
           let decoded = GoFlyLanguage(rawValue: value) { language = decoded }
        if let value = saved?["appearance"] as? String,
           let decoded = GoFlyAppearance(rawValue: value) { appearance = decoded }
        if let value = saved?["movementSpeed"] as? Int,
           let decoded = RouteSpeed(kilometersPerHour: value) { movementSpeed = decoded }
        wanderRadius = Self.decodeRadius(saved)
        wanderRangeVisible = (saved?["wanderRangeVisible"] as? Bool) ?? true
        if let value = saved?["backgroundRunSeconds"] as? Int {
            backgroundRunSeconds = Self.applyBackgroundRunSeconds(value)
        }
    }

    func refreshSystemPreferences() {
        systemLanguages = Locale.preferredLanguages
    }

    private func save() {
        var dictionary = defaults.dictionary(forKey: Self.storageKey) ?? [:]
        dictionary["language"] = language.rawValue
        dictionary["appearance"] = appearance.rawValue
        dictionary["movementSpeed"] = movementSpeed.kilometersPerHour
        dictionary["backgroundRunSeconds"] = backgroundRunSeconds
        dictionary["wanderRadiusKm"] = wanderRadius.kilometers
        dictionary["wanderRangeVisible"] = wanderRangeVisible
        defaults.set(dictionary, forKey: Self.storageKey)
    }
}
