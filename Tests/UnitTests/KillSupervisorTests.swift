import XCTest
import Darwin
@testable import UsedPorts

final class FakeExecutor: @unchecked Sendable, KillExecuting {
    var sendResult: Int32 = 0
    var aliveSequence: [Bool] = []
    var defaultAlive: Bool = false
    private var sendCount = 0
    func sendSignal(_ pid: Int32, sig: Int32) -> Int32 {
        sendCount += 1
        return sendResult
    }
    func isAlive(_ pid: Int32) -> Bool {
        if aliveSequence.isEmpty { return defaultAlive }
        return aliveSequence.removeFirst()
    }
}

final class KillSupervisorTests: XCTestCase {
    func test_immediateTermination() async {
        let fake = FakeExecutor()
        fake.sendResult = 0
        fake.aliveSequence = [false]
        let sup = KillSupervisor(executor: fake, sleep: { _ in })
        let r = await sup.kill(pid: 1234, signal: .term, timeoutSeconds: 1, pollInterval: 0.01)
        XCTAssertEqual(r, .terminated)
    }

    func test_stillAlive_returnsStillAlive() async {
        let fake = FakeExecutor()
        fake.sendResult = 0
        fake.defaultAlive = true
        let sup = KillSupervisor(executor: fake, sleep: { _ in })
        let r = await sup.kill(pid: 1234, signal: .term, timeoutSeconds: 0.05, pollInterval: 0.01)
        XCTAssertEqual(r, .stillAlive)
    }

    func test_alreadyDead_whenESRCH() async {
        let fake = FakeExecutor()
        fake.sendResult = ESRCH
        let sup = KillSupervisor(executor: fake, sleep: { _ in })
        let r = await sup.kill(pid: 1, signal: .term)
        XCTAssertEqual(r, .alreadyDead)
    }

    func test_noPermission_whenEPERM() async {
        let fake = FakeExecutor()
        fake.sendResult = EPERM
        let sup = KillSupervisor(executor: fake, sleep: { _ in })
        let r = await sup.kill(pid: 1, signal: .term)
        XCTAssertEqual(r, .noPermission)
    }
}
