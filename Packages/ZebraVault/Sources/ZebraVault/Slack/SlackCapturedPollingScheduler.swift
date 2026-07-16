import AppKit
import CoreFoundation
import Foundation

struct SlackScheduledWorkspace: Equatable, Sendable {
    let workspaceID: String
    let authorizedUserID: String
    let startDate: Date
    let lastSuccessfulPollAt: Date?

    init(workspaceID: String, authorizedUserID: String = "", startDate: Date = .distantPast,
         lastSuccessfulPollAt: Date?) {
        self.workspaceID = workspaceID
        self.authorizedUserID = authorizedUserID
        self.startDate = startDate
        self.lastSuccessfulPollAt = lastSuccessfulPollAt
    }
}

enum SlackScheduledPollResult: Equatable, Sendable {
    case success(completedAt: Date)
    case failure(SlackScheduledPollFailure)
}

struct SlackScheduledPollFailure: Equatable, Sendable {
    let reason: String
}

@MainActor
protocol SlackPollingTimerScheduling: AnyObject {
    func schedule(workspaceID: String, at date: Date, action: @escaping @MainActor () -> Void)
    func cancel(workspaceID: String)
    func cancelAll()
}

@MainActor
private final class SlackFoundationPollingTimers: SlackPollingTimerScheduling {
    private var timers: [String: Timer] = [:]

    func schedule(workspaceID: String, at date: Date, action: @escaping @MainActor () -> Void) {
        cancel(workspaceID: workspaceID)
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        timers[workspaceID] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel(workspaceID: String) {
        timers.removeValue(forKey: workspaceID)?.invalidate()
    }

    func cancelAll() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }
}

/// Process-wide owner of Slack launch, hourly, and wake polling.
/// Failure recovery decisions intentionally stop at `failurePolicy`.
@MainActor
public final class SlackCapturedPollingScheduler {
    public static let shared = SlackCapturedPollingScheduler()

    private let interval: TimeInterval
    private let now: () -> Date
    private let workspaceProvider: () -> [SlackScheduledWorkspace]
    private let poll: (SlackScheduledWorkspace) async -> SlackScheduledPollResult
    private let timers: any SlackPollingTimerScheduling
    private let failurePolicy: (SlackScheduledWorkspace, SlackScheduledPollFailure) -> Void
    private let observesWorkspaceRefresh: Bool
    private var running: Set<String> = []
    private var coalesced: Set<String> = []
    private var tasks: [String: Task<Void, Never>] = [:]
    private var scheduledAt: [String: Date] = [:]
    private var wakeObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var started = false

    private convenience init() {
        let service = SlackSourceOnboardingService()
        self.init(
            interval: 60 * 60,
            now: { Date() },
            workspaceProvider: { service.scheduledWorkspaces() },
            poll: { workspace in await service.pollScheduled(workspace) },
            timers: SlackFoundationPollingTimers(),
            observesWorkspaceRefresh: true,
            failurePolicy: { _, _ in }
        )
    }

    init(
        interval: TimeInterval,
        now: @escaping () -> Date,
        workspaceProvider: @escaping () -> [SlackScheduledWorkspace],
        poll: @escaping (SlackScheduledWorkspace) async -> SlackScheduledPollResult,
        timers: any SlackPollingTimerScheduling,
        observesWorkspaceRefresh: Bool = false,
        failurePolicy: @escaping (SlackScheduledWorkspace, SlackScheduledPollFailure) -> Void = { _, _ in }
    ) {
        self.interval = interval
        self.now = now
        self.workspaceProvider = workspaceProvider
        self.poll = poll
        self.timers = timers
        self.observesWorkspaceRefresh = observesWorkspaceRefresh
        self.failurePolicy = failurePolicy
    }

    public func start() {
        guard !started else { return }
        started = true
        installLifecycleObservers()
        reconcileEligibleWorkspaces()
    }

    public func stop() {
        guard started else { return }
        started = false
        removeWorkspaceRefreshObserver()
        timers.cancelAll()
        scheduledAt.removeAll()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        running.removeAll()
        coalesced.removeAll()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        wakeObserver = nil
        terminationObserver = nil
    }

    private func installLifecycleObservers() {
        if observesWorkspaceRefresh {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                Self.workspaceRefreshCallback,
                SlackPollingWorkspaceRefreshSignal.name.rawValue,
                nil,
                .deliverImmediately
            )
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private static let workspaceRefreshCallback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let scheduler = Unmanaged<SlackCapturedPollingScheduler>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { scheduler.reconcileEligibleWorkspaces() }
        }
    }

    private func removeWorkspaceRefreshObserver() {
        guard observesWorkspaceRefresh else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            SlackPollingWorkspaceRefreshSignal.name,
            nil
        )
    }

    private func handleWake() {
        reconcileEligibleWorkspaces()
    }

    private func reconcileEligibleWorkspaces(_ workspaces: [SlackScheduledWorkspace]? = nil) {
        let workspaces = workspaces ?? workspaceProvider()
        let eligibleIDs = Set(workspaces.map(\.workspaceID))
        for workspaceID in Array(scheduledAt.keys) where !eligibleIDs.contains(workspaceID) {
            timers.cancel(workspaceID: workspaceID)
            scheduledAt[workspaceID] = nil
        }
        let current = now()
        for workspace in workspaces {
            guard let lastSuccess = workspace.lastSuccessfulPollAt else {
                trigger(workspace)
                continue
            }
            let dueAt = lastSuccess.addingTimeInterval(interval)
            if dueAt <= current { trigger(workspace) }
            else { schedule(workspace: workspace, at: dueAt) }
        }
    }

    private func trigger(_ workspace: SlackScheduledWorkspace) {
        timers.cancel(workspaceID: workspace.workspaceID)
        scheduledAt[workspace.workspaceID] = nil
        guard !running.contains(workspace.workspaceID) else {
            coalesced.insert(workspace.workspaceID)
            return
        }
        running.insert(workspace.workspaceID)
        tasks[workspace.workspaceID] = Task { [weak self] in
            guard let self else { return }
            let result = await poll(workspace)
            guard !Task.isCancelled else { return }
            finish(workspace: workspace, result: result)
        }
    }

    private func finish(workspace: SlackScheduledWorkspace, result: SlackScheduledPollResult) {
        running.remove(workspace.workspaceID)
        tasks[workspace.workspaceID] = nil
        if coalesced.remove(workspace.workspaceID) != nil {
            trigger(refreshedWorkspace(fallback: workspace))
            return
        }
        switch result {
        case .success(let completedAt):
            schedule(workspace: workspace, at: completedAt.addingTimeInterval(interval))
        case .failure(let failure):
            failurePolicy(workspace, failure)
        }
    }

    private func refreshedWorkspace(fallback: SlackScheduledWorkspace) -> SlackScheduledWorkspace {
        workspaceProvider().first { $0.workspaceID == fallback.workspaceID } ?? fallback
    }

    private func schedule(workspace: SlackScheduledWorkspace, at date: Date) {
        guard scheduledAt[workspace.workspaceID] != date else { return }
        scheduledAt[workspace.workspaceID] = date
        timers.schedule(workspaceID: workspace.workspaceID, at: date) { [weak self] in
            guard let self else { return }
            self.scheduledAt[workspace.workspaceID] = nil
            self.trigger(self.refreshedWorkspace(fallback: workspace))
        }
    }

    func triggerForTesting(workspaceID: String) {
        guard let workspace = workspaceProvider().first(where: { $0.workspaceID == workspaceID }) else { return }
        trigger(workspace)
    }

    func handleWakeForTesting(lastSuccessfulPollAt: [String: Date]) {
        let workspaces = workspaceProvider().map { workspace in
            SlackScheduledWorkspace(workspaceID: workspace.workspaceID,
                                    authorizedUserID: workspace.authorizedUserID,
                                    startDate: workspace.startDate,
                                    lastSuccessfulPollAt: lastSuccessfulPollAt[workspace.workspaceID])
        }
        reconcileEligibleWorkspaces(workspaces)
    }

    func waitUntilIdleForTesting() async {
        for _ in 0..<500 where !running.isEmpty { await Task.yield() }
    }
}
