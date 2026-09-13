import Foundation
import Testing
@testable import TidyBugCore

@Suite(.timeLimit(.minutes(1))) struct MaintenanceTests {
    @Test func catalogIsWellFormed() {
        let tasks = Maintenance.tasks
        #expect(Set(tasks.map(\.id)).count == tasks.count, "task ids must be unique")
        for t in tasks {
            #expect(!t.title.isEmpty && !t.detail.isEmpty)
        }
        // Heavy or disruptive tasks are never preselected.
        let heavy = tasks.filter { ["spotlight-rebuild", "restart-finder", "font-caches", "launch-services"].contains($0.id) }
        #expect(heavy.allSatisfy { !$0.preselected })
    }

    @Test func parsesAdminMarkers() {
        // `do shell script` returns carriage returns.
        let output = "__TB_BEGIN__ flush-dns\r__TB_END__ flush-dns 0\r__TB_BEGIN__ purge-memory\rsome output\rmore\r__TB_END__ purge-memory 1"
        let parsed = MaintenanceEngine.parseMarkers(output)
        #expect(parsed["flush-dns"]?.status == 0)
        #expect(parsed["purge-memory"]?.status == 1)
        #expect(parsed["purge-memory"]?.output.contains("some output") == true)
    }

    @Test func batchScriptWrapsEachTask() {
        let tasks = Maintenance.tasks.filter { $0.id == "flush-dns" }
        let script = MaintenanceEngine.batchScript(tasks)
        #expect(script.contains("__TB_BEGIN__ flush-dns"))
        #expect(script.contains("__TB_END__ flush-dns $?"))
        #expect(script.contains("dscacheutil -flushcache && killall -HUP mDNSResponder"))
    }

    @Test func appleScriptEscapesQuotes() {
        let s = MaintenanceEngine.appleScript(for: #"sqlite3 "/a b/c" 'VACUUM;'"#)
        #expect(s.hasPrefix("do shell script \""))
        #expect(s.contains(#"\"/a b/c\""#))
        #expect(s.hasSuffix("with administrator privileges"))
    }

    @Test func shellQuoteHandlesSingleQuotes() {
        #expect(Maintenance.shellQuote("it's") == #"'it'\''s'"#)
    }

    @Test func diagnosisProbesReturnSaneValues() {
        let mem = Diagnosis.memory()
        #expect(mem.total > 0)
        #expect(mem.used <= mem.total)
        #expect(Diagnosis.uptime() > 0)
        #expect([1, 2, 4].contains(Diagnosis.memoryPressureLevel()))
    }
}
