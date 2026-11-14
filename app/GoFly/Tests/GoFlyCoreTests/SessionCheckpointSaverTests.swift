import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct SessionCheckpointSaverTests {
    @Test func captureSkipsASnapshotEqualToTheLastOne() async {
        let persistence = GatedCheckpointPersistence(), tasks = RecordingBackgroundTasks()
        let store = SessionRecoveryStore(persistence: persistence)
        let saver = SessionCheckpointSaver(store: store, backgroundTasks: tasks)

        saver.capture(store.initialSnapshot)
        #expect(!store.hasUnsavedChanges, "The restored snapshot is not written again")
        saver.capture(SessionRecoverySnapshot(mode: .joystick))
        saver.capture(SessionRecoverySnapshot(mode: .joystick))
        _ = await store.flush()
        #expect(persistence.writes == 1)
    }

    @Test func runtimeOnlyChangesDoNotWriteTheCheckpointAgain() async {
        let persistence = GatedCheckpointPersistence()
        let store = SessionRecoveryStore(persistence: persistence)
        let saver = SessionCheckpointSaver(store: store, backgroundTasks: RecordingBackgroundTasks())

        saver.capture(SessionRecoverySnapshot(mode: .joystick, activeMovement: .manual))
        #expect(await store.flush())
        saver.capture(SessionRecoverySnapshot(mode: .joystick,
            uncertainty: SessionMovementUncertainty(source: .joystick)))
        #expect(await store.flush())
        #expect(persistence.writes == 1)
    }

    @Test func leavingWithNothingUnsavedOpensNoWindow() {
        let tasks = RecordingBackgroundTasks()
        let store = SessionRecoveryStore(persistence: GatedCheckpointPersistence())
        let saver = SessionCheckpointSaver(store: store, backgroundTasks: tasks)

        saver.sceneLeftForeground(store.initialSnapshot)
        #expect(tasks.begun.isEmpty)
    }

    @Test func leavingOpensOneWindowThatEndsWhenTheSaveIsDurable() async {
        let persistence = GatedCheckpointPersistence(holding: true), tasks = RecordingBackgroundTasks()
        let store = SessionRecoveryStore(persistence: persistence)
        let saver = SessionCheckpointSaver(store: store, backgroundTasks: tasks)

        saver.sceneLeftForeground(SessionRecoverySnapshot(mode: .joystick))
        saver.sceneLeftForeground(SessionRecoverySnapshot(mode: .route))
        #expect(tasks.begun == ["Save GoFly session"])
        await settle()
        #expect(tasks.ended.isEmpty)

        persistence.release()
        await wait { tasks.ended == [0] }
        #expect(!store.hasUnsavedChanges)
    }

    @Test func returningToTheForegroundEndsTheWindowAndAllowsANewOne() async {
        let persistence = GatedCheckpointPersistence(holding: true), tasks = RecordingBackgroundTasks()
        let store = SessionRecoveryStore(persistence: persistence)
        let saver = SessionCheckpointSaver(store: store, backgroundTasks: tasks)

        saver.sceneLeftForeground(SessionRecoverySnapshot(mode: .joystick))
        saver.sceneBecameActive()
        #expect(tasks.ended == [0])

        saver.sceneLeftForeground(SessionRecoverySnapshot(mode: .route))
        #expect(tasks.begun.count == 2)
        persistence.release()
        await wait { tasks.ended == [0, 1] }
    }

    @Test func expirationEndsTheWindowOnce() async {
        let persistence = GatedCheckpointPersistence(holding: true), tasks = RecordingBackgroundTasks()
        let store = SessionRecoveryStore(persistence: persistence)
        let saver = SessionCheckpointSaver(store: store, backgroundTasks: tasks)

        saver.sceneLeftForeground(SessionRecoverySnapshot(mode: .joystick))
        tasks.expire(0)
        #expect(tasks.ended == [0])
        persistence.release()
        _ = await store.flush()
        await settle()
        #expect(tasks.ended == [0])
    }

    @Test func noGrantedBackgroundTimeStillFlushesWithoutEndingATask() async {
        let persistence = GatedCheckpointPersistence(), tasks = RecordingBackgroundTasks(grants: false)
        let store = SessionRecoveryStore(persistence: persistence)
        let saver = SessionCheckpointSaver(store: store, backgroundTasks: tasks)

        saver.sceneLeftForeground(SessionRecoverySnapshot(mode: .joystick))
        await wait { !store.hasUnsavedChanges }
        #expect(tasks.begun.count == 1 && tasks.ended.isEmpty)
    }

    private func settle() async { for _ in 0..<20 { await Task.yield() } }
    private func wait(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        #expect(condition())
    }
}

/// In-memory persistence whose writes can be held until released.
private final class GatedCheckpointPersistence: SessionRecoveryPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var holding: Bool
    private var stored: Data?
    private var writeCount = 0
    init(holding: Bool = false) { self.holding = holding }
    var writes: Int { lock.withLock { writeCount } }

    func read() throws -> Data? { lock.withLock { stored } }
    func replaceAtomically(with data: Data) throws {
        if lock.withLock({ holding }) { gate.wait() }
        lock.withLock { stored = data; writeCount += 1 }
    }
    func release() {
        let wasHolding = lock.withLock { () -> Bool in defer { holding = false }; return holding }
        if wasHolding { gate.signal() }
    }
}

@MainActor
private final class RecordingBackgroundTasks: BackgroundSaveTasks {
    private let grants: Bool
    private(set) var begun: [String] = []
    private(set) var ended: [Int] = []
    private var expirations: [Int: @MainActor () -> Void] = [:]
    init(grants: Bool = true) { self.grants = grants }

    func begin(name: String, expiration: @escaping @MainActor () -> Void) -> Int? {
        begun.append(name)
        guard grants else { return nil }
        let task = begun.count - 1
        expirations[task] = expiration
        return task
    }
    func end(_ task: Int) { ended.append(task) }
    func expire(_ task: Int) { expirations[task]?() }
}
