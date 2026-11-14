import Foundation

/// The platform's finite background execution, e.g. UIKit background tasks.
@MainActor
public protocol BackgroundSaveTasks {
    /// Returns nil when the platform grants no background time. `expiration`
    /// runs on the main actor if the time runs out first.
    func begin(name: String, expiration: @escaping @MainActor () -> Void) -> Int?
    func end(_ task: Int)
}

/// Captures session checkpoints into the recovery store, skipping unchanged
/// snapshots, and keeps a finite save window open while the scene leaves the
/// foreground. The window is independent of movement runtime and native cleanup.
@MainActor
public final class SessionCheckpointSaver: ObservableObject {
    private let store: SessionRecoveryStore
    private let backgroundTasks: any BackgroundSaveTasks
    private var lastCaptured: SessionRecoverySnapshot?
    private var windowStarted = false
    private var windowID: UUID?
    private var backgroundTask: Int?
    private var flushTask: Task<Void, Never>?

    public init(store: SessionRecoveryStore, backgroundTasks: any BackgroundSaveTasks) {
        self.store = store; self.backgroundTasks = backgroundTasks
        lastCaptured = store.initialSnapshot
    }

    public func capture(_ snapshot: SessionRecoverySnapshot) {
        if let lastCaptured, SessionRecoveryCodec.samePersistentContent(snapshot, lastCaptured) { return }
        lastCaptured = store.capture(snapshot) ? snapshot : nil
    }

    /// Captures `snapshot` and opens one save window until the scene is active again.
    public func sceneLeftForeground(_ snapshot: SessionRecoverySnapshot) {
        capture(snapshot)
        guard !windowStarted else { return }
        windowStarted = true
        guard store.isSaving || store.hasUnsavedChanges else { return }
        let id = UUID()
        windowID = id
        backgroundTask = backgroundTasks.begin(name: "Save GoFly session") { [weak self] in
            self?.finishWindow(id: id)
        }
        flushTask = Task { @MainActor in
            _ = await store.flush()
            finishWindow(id: id)
        }
    }

    public func sceneBecameActive() {
        windowStarted = false
        finishWindow(id: windowID)
    }

    private func finishWindow(id: UUID?) {
        guard let id, windowID == id else { return }
        windowID = nil
        flushTask?.cancel()
        flushTask = nil
        if let task = backgroundTask { backgroundTasks.end(task) }
        backgroundTask = nil
    }
}
