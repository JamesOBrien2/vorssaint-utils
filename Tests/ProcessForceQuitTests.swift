// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Run the real eligibility guard with controlled process identities; no process is signalled.
enum ProcessForceQuitTests {
    struct ProcessUsage {
        let pid: pid_t
        let name: String
        let startedAt: UInt64?
    }

    enum KillProcessService {
        static var startTimes: [pid_t: UInt64] = [:]
        static var lookups = 0
        static func startTime(for pid: pid_t) -> UInt64? {
            lookups += 1
            return startTimes[pid]
        }
    }

    static func run(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        let featureKey = AppFeature.killProcess.availabilityKey
        let previous = defaults.object(forKey: featureKey)
        defer {
            if let previous { defaults.set(previous, forKey: featureKey) }
            else { defaults.removeObject(forKey: featureKey) }
            KillProcessService.startTimes = [:]
            KillProcessService.lookups = 0
        }

        let victim = Process()
        victim.executableURL = URL(fileURLWithPath: "/bin/sleep")
        victim.arguments = ["60"]
        guard (try? victim.run()) != nil else {
            suite.expect(false, "an ordinary test process can launch")
            return
        }
        defer { victim.terminate(); victim.waitUntilExit() }
        let victimPID = victim.processIdentifier
        KillProcessService.startTimes[victimPID] = 42
        let service = Service()

        defaults.set(false, forKey: featureKey)
        suite.expect(!service.canForceQuit(ProcessUsage(pid: victimPID, name: "sleep", startedAt: 42))
                     && KillProcessService.lookups == 0,
                     "uninstalled Kill Process does not inspect or expose a process")

        defaults.set(true, forKey: featureKey)
        suite.expect(!service.canForceQuit(ProcessUsage(pid: victimPID, name: "sleep", startedAt: nil)),
                     "a row without a sampled identity cannot be killed")
        suite.expect(!service.canForceQuit(ProcessUsage(pid: victimPID, name: "sleep", startedAt: 41)),
                     "a PID reused before menu selection cannot be killed")
        suite.expect(service.canForceQuit(ProcessUsage(pid: victimPID, name: "sleep", startedAt: 42)),
                     "an ordinary process with a matching identity can be force killed")
        KillProcessService.startTimes[victimPID] = 43
        suite.expect(!service.canForceQuit(ProcessUsage(pid: victimPID, name: "sleep", startedAt: 42)),
                     "a PID reused while confirmation is open cannot be killed")
        KillProcessService.startTimes[victimPID] = 42
        suite.expect(!service.canForceQuit(ProcessUsage(pid: victimPID, name: "WindowServer", startedAt: 42)),
                     "a protected display name cannot be killed")

        KillProcessService.startTimes[getpid()] = 42
        suite.expect(!service.canForceQuit(ProcessUsage(pid: getpid(), name: "Whatever", startedAt: 42)),
                     "the app's own process stays protected")
        KillProcessService.startTimes[1] = 42
        suite.expect(!service.canForceQuit(ProcessUsage(pid: 1, name: "pid 1", startedAt: 42)),
                     "launchd stays protected")
        for name in ["WindowServer", "loginwindow", "kernel_task"] {
            guard let pid = pid(named: name) else { continue }
            KillProcessService.startTimes[pid] = 42
            suite.expect(!service.canForceQuit(ProcessUsage(pid: pid, name: "pid \(pid)", startedAt: 42)),
                         "\(name) stays protected behind an unresolved display name")
            suite.expect(!service.canForceQuit(ProcessUsage(pid: pid, name: name, startedAt: 42)),
                         "\(name) stays protected under its own name")
        }
    }

    /// `ps` rather than `proc_name`, which returns nothing for processes owned
    /// by root — exactly the ones these assertions have to reach.
    private static func pid(named target: String) -> pid_t? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aceo", "pid,comm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count == 2, columns[1] == target else { continue }
            return pid_t(columns[0])
        }
        return nil
    }
}
