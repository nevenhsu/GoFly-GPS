import Combine
import Foundation

/// The one place the app's foreground state enters GoFlyCore. The map screen
/// reports every scene change here; each participant registered at assembly
/// hears a change of activity once, in registration order, so a repeated
/// report (onAppear, inactive then background) runs nothing twice.
@MainActor
public final class SceneLifecycle: ObservableObject {
    public struct Participant {
        let becameActive: @MainActor () -> Void
        let leftForeground: @MainActor () -> Void

        public init(becameActive: @escaping @MainActor () -> Void,
                    leftForeground: @escaping @MainActor () -> Void) {
            self.becameActive = becameActive; self.leftForeground = leftForeground
        }
    }

    @Published public private(set) var isActive = false
    private var participants: [Participant] = []

    public init() {}

    public func register(_ participant: Participant) { participants.append(participant) }

    public func sceneDidChange(active: Bool) {
        guard active != isActive else { return }
        isActive = active
        for participant in participants {
            if active { participant.becameActive() } else { participant.leftForeground() }
        }
    }
}
