import Foundation
import Testing
@testable import TidyBugCore

@Suite(.timeLimit(.minutes(1))) struct CommandRunnerTests {
    @Test func capturesOutputAndStatus() {
        let r = CommandRunner.runSync("/bin/sh", ["-c", "echo hello; exit 3"], timeout: 10)
        #expect(r.status == 3)
        #expect(r.output.contains("hello"))
    }

    /// A background grandchild inherits the output pipe and keeps it open long
    /// after the command itself is killed. The runner must still return promptly.
    @Test func timeoutReturnsEvenWhenAGrandchildHoldsThePipe() {
        let start = Date()
        let r = CommandRunner.runSync("/bin/sh", ["-c", "sleep 30 & echo started; sleep 30"], timeout: 1)
        let elapsed = Date().timeIntervalSince(start)
        #expect(r.status == 124, "timed-out commands report status 124")
        #expect(r.output.contains("started"))
        #expect(r.output.contains("timed out"))
        #expect(elapsed < 10, "runSync blocked for \(elapsed)s after the timeout")
    }

    @Test func missingToolFailsFast() {
        let r = CommandRunner.runSync("definitely-not-a-real-tool-\(UUID().uuidString)", [], timeout: 5)
        #expect(r.status == 127)
    }
}
