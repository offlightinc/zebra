import Foundation
import SwiftUI

@MainActor
final class SlackSourceOnboardingCoordinator: ObservableObject {
    enum PresentationState: Equatable { case idle, polling, attention(String), checked }

    @Published private(set) var presentationState: PresentationState = .idle
    private let service: SlackSourceOnboardingService
    private var pollTask: Task<Void, Never>?

    init(
        stateURL: URL = ZebraSourceOnboardingState.defaultStateURL(),
        applicationSupport: URL? = nil,
        credentialStore: any SlackCredentialStoring = SlackKeychainCredentialStore(),
        transport: any SlackHTTPTransport = SlackURLSessionTransport(),
        fileManager: FileManager = .default
    ) {
        service = SlackSourceOnboardingService(stateURL: stateURL, applicationSupport: applicationSupport,
                                               credentialStore: credentialStore, transport: transport,
                                               fileManager: fileManager)
    }

    deinit { pollTask?.cancel() }

    func begin(token: String, startDate: Date) {
        run(credential: .token(token), startDate: startDate)
    }

    func resume(startDate: Date) {
        guard pollTask == nil else { presentationState = .attention("poll_already_running"); return }
        presentationState = .polling
        pollTask = Task { [weak self, service] in
            let result = await service.resumeFromState()
            guard let self else { return }
            presentationState = result.status == .checked ? .checked : .attention(result.reason ?? "slack_poll_failed")
            pollTask = nil
        }
    }

    func isSlackConfirmedAndActive() -> Bool { service.isConfirmedAndActive() }

    private func run(credential: SlackSourceOnboardingService.Credential, startDate: Date) {
        guard pollTask == nil else { presentationState = .attention("poll_already_running"); return }
        presentationState = .polling
        pollTask = Task { [weak self, service] in
            let result = await service.run(credential: credential, startDate: startDate)
            guard let self else { return }
            presentationState = result.status == .checked ? .checked : .attention(result.reason ?? "slack_poll_failed")
            pollTask = nil
        }
    }
}
