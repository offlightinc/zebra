import Foundation
import Testing
@testable import ZebraVault

@Suite(.serialized)
@MainActor
struct SlackCapturedPollingSchedulerTests {
    @Test func launchPollsImmediatelyAndSchedulesOneHourFromSuccessfulCompletion() async {
        let clock = SchedulerTestClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = SchedulerTestRunner(clock: clock)
        let timers = SchedulerTestTimers()
        let scheduler = SlackCapturedPollingScheduler(
            interval: 3_600,
            now: { clock.now },
            workspaceProvider: { [.init(workspaceID: "T1", lastSuccessfulPollAt: Date(timeIntervalSince1970: 900))] },
            poll: { workspace in await runner.poll(workspace) },
            timers: timers
        )

        scheduler.start()
        await runner.waitForPollCount(1)
        clock.now = Date(timeIntervalSince1970: 1_020)
        runner.completeNextSuccessfully()
        await scheduler.waitUntilIdleForTesting()

        #expect(runner.workspaceIDs == ["T1"])
        #expect(timers.scheduledDates["T1"] == Date(timeIntervalSince1970: 4_620))
    }

    @Test func wakePollsWhenDueAndOtherwiseKeepsOnlyTheRemainingInterval() async {
        let clock = SchedulerTestClock(now: Date(timeIntervalSince1970: 4_000))
        let runner = SchedulerTestRunner(clock: clock)
        runner.automaticallyComplete = true
        let timers = SchedulerTestTimers()
        let scheduler = SlackCapturedPollingScheduler(
            interval: 3_600,
            now: { clock.now },
            workspaceProvider: { [.init(workspaceID: "T1", lastSuccessfulPollAt: Date(timeIntervalSince1970: 1_000))] },
            poll: { workspace in await runner.poll(workspace) },
            timers: timers
        )

        scheduler.start()
        await runner.waitForPollCount(1)
        await scheduler.waitUntilIdleForTesting()
        let launchCount = runner.workspaceIDs.count

        clock.now = Date(timeIntervalSince1970: 4_100)
        scheduler.handleWakeForTesting(lastSuccessfulPollAt: ["T1": Date(timeIntervalSince1970: 4_000)])
        await scheduler.waitUntilIdleForTesting()
        #expect(runner.workspaceIDs.count == launchCount)
        #expect(timers.scheduledDates["T1"] == Date(timeIntervalSince1970: 7_600))

        clock.now = Date(timeIntervalSince1970: 7_601)
        scheduler.handleWakeForTesting(lastSuccessfulPollAt: ["T1": Date(timeIntervalSince1970: 4_000)])
        await runner.waitForPollCount(launchCount + 1)
    }

    @Test func overlappingTriggersAreSingleFlightAndCoalesceToOneFollowUp() async {
        let clock = SchedulerTestClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = SchedulerTestRunner(clock: clock)
        let scheduler = SlackCapturedPollingScheduler(
            interval: 3_600,
            now: { clock.now },
            workspaceProvider: { [.init(workspaceID: "T1", lastSuccessfulPollAt: nil)] },
            poll: { workspace in await runner.poll(workspace) },
            timers: SchedulerTestTimers()
        )

        scheduler.start()
        await runner.waitForPollCount(1)
        scheduler.triggerForTesting(workspaceID: "T1")
        scheduler.triggerForTesting(workspaceID: "T1")
        #expect(runner.maximumConcurrentPolls == 1)
        runner.completeNextSuccessfully()
        await runner.waitForPollCount(2)
        #expect(runner.maximumConcurrentPolls == 1)
        runner.completeNextSuccessfully()
        await scheduler.waitUntilIdleForTesting()
        #expect(runner.workspaceIDs == ["T1", "T1"])
    }

    @Test func processWideStartIsIdempotent() async {
        let clock = SchedulerTestClock(now: Date(timeIntervalSince1970: 1_000))
        let runner = SchedulerTestRunner(clock: clock)
        runner.automaticallyComplete = true
        let timers = SchedulerTestTimers()
        let scheduler = SlackCapturedPollingScheduler(
            interval: 3_600,
            now: { clock.now },
            workspaceProvider: { [.init(workspaceID: "T1", lastSuccessfulPollAt: nil)] },
            poll: { workspace in await runner.poll(workspace) },
            timers: timers
        )

        scheduler.start()
        scheduler.start()
        await runner.waitForPollCount(1)
        await scheduler.waitUntilIdleForTesting()
        #expect(runner.workspaceIDs == ["T1"])
        #expect(timers.scheduleCounts["T1"] == 1)
    }
}

@MainActor
private final class SchedulerTestClock {
    var now: Date
    init(now: Date) { self.now = now }
}

@MainActor
private final class SchedulerTestTimers: SlackPollingTimerScheduling {
    private(set) var scheduledDates: [String: Date] = [:]
    private(set) var scheduleCounts: [String: Int] = [:]
    func schedule(workspaceID: String, at date: Date, action: @escaping @MainActor () -> Void) {
        scheduledDates[workspaceID] = date
        scheduleCounts[workspaceID, default: 0] += 1
    }
    func cancel(workspaceID: String) { scheduledDates[workspaceID] = nil }
    func cancelAll() { scheduledDates.removeAll() }
}

@MainActor
private final class SchedulerTestRunner {
    let clock: SchedulerTestClock
    var automaticallyComplete = false
    private(set) var workspaceIDs: [String] = []
    private(set) var maximumConcurrentPolls = 0
    private var concurrentPolls = 0
    private var continuations: [CheckedContinuation<SlackScheduledPollResult, Never>] = []

    init(clock: SchedulerTestClock) { self.clock = clock }

    func poll(_ workspace: SlackScheduledWorkspace) async -> SlackScheduledPollResult {
        workspaceIDs.append(workspace.workspaceID)
        concurrentPolls += 1
        maximumConcurrentPolls = max(maximumConcurrentPolls, concurrentPolls)
        if automaticallyComplete {
            concurrentPolls -= 1
            return .success(completedAt: clock.now)
        }
        let result = await withCheckedContinuation { continuations.append($0) }
        concurrentPolls -= 1
        return result
    }

    func completeNextSuccessfully() {
        continuations.removeFirst().resume(returning: .success(completedAt: clock.now))
    }

    func waitForPollCount(_ count: Int) async {
        for _ in 0..<200 where workspaceIDs.count < count { await Task.yield() }
    }
}
