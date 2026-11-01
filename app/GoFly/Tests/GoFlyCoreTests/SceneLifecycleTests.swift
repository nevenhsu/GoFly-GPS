import Testing
@testable import GoFlyCore

@Suite @MainActor
struct SceneLifecycleTests {
    @Test func eachChangeOfActivityReachesEveryParticipantOnceInOrder() {
        let scene = SceneLifecycle()
        var events: [String] = []
        scene.register(.init(becameActive: { events.append("a+") }, leftForeground: { events.append("a-") }))
        scene.register(.init(becameActive: { events.append("b+") }, leftForeground: { events.append("b-") }))

        scene.sceneDidChange(active: false)
        #expect(events.isEmpty, "The scene starts inactive")
        scene.sceneDidChange(active: true)
        scene.sceneDidChange(active: true)
        #expect(events == ["a+", "b+"] && scene.isActive, "A repeated report (onAppear) runs nothing twice")
        scene.sceneDidChange(active: false)
        scene.sceneDidChange(active: false)
        #expect(events == ["a+", "b+", "a-", "b-"] && !scene.isActive, "Inactive then background releases once")
    }
}
