import Foundation

/// How long a test waits on the real clock for something it expects to happen. Generous on purpose:
/// an expected event returns at once, and a loaded CI runner must not run out of time and move on.
let testWaitLimit: Duration = .seconds(30)

/// Polls `condition` on the real clock until it holds or `timeout` passes. For a check that nothing
/// happens, pass a short `timeout`.
func eventually(within timeout: Duration = testWaitLimit, _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await clock.sleep(for: .milliseconds(1))
    }
    return await condition()
}
