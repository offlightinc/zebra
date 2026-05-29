import XCTest
@testable import ZebraVault

final class ZebraAgentOnboardingCoordinatorTests: XCTestCase {
    func testSavedPrimaryInstalledLaunchesWithoutPromptOrPersist() {
        let decision = ZebraAgentOnboardingCoordinator().initialDecision(
            savedPrimary: .codex,
            candidates: [
                candidate(.codex, installState: .installed),
                candidate(.claude, installState: .missing),
            ]
        )

        XCTAssertEqual(
            decision,
            .launch(agent: .codex, selectionMode: .savedPrimary, shouldPersistPrimary: false)
        )
    }

    func testSavedPrimaryMissingAsksBeforeSwitching() {
        let candidates = [
            candidate(.codex, installState: .missing),
            candidate(.claude, installState: .installed),
        ]

        let decision = ZebraAgentOnboardingCoordinator().initialDecision(
            savedPrimary: .codex,
            candidates: candidates
        )

        XCTAssertEqual(
            decision,
            .primaryMissing(saved: .codex, installed: [candidate(.claude, installState: .installed)], candidates: candidates)
        )
    }

    func testOneInstalledAgentAutoSelectsAndPersists() {
        let decision = ZebraAgentOnboardingCoordinator().initialDecision(
            savedPrimary: nil,
            candidates: [
                candidate(.codex, installState: .installed),
                candidate(.claude, installState: .missing),
            ]
        )

        XCTAssertEqual(
            decision,
            .launch(agent: .codex, selectionMode: .autoOneInstalled, shouldPersistPrimary: true)
        )
    }

    func testMultipleInstalledAgentsAskForPrimary() {
        let installed = [
            candidate(.codex, installState: .installed),
            candidate(.claude, installState: .installed),
        ]

        let decision = ZebraAgentOnboardingCoordinator().initialDecision(
            savedPrimary: nil,
            candidates: installed
        )

        XCTAssertEqual(decision, .choosePrimary(installed: installed))
    }

    func testNoInstalledAgentsAskForInstallTarget() {
        let candidates = [
            candidate(.codex, installState: .missing),
            candidate(.claude, installState: .missing),
            candidate(.antigravity, installState: .missing),
        ]

        let decision = ZebraAgentOnboardingCoordinator().initialDecision(
            savedPrimary: nil,
            candidates: candidates
        )

        XCTAssertEqual(decision, .chooseInstallTarget(candidates: candidates))
    }

    func testInstallCompletionLaunchesSelectedAgentAndPersists() {
        let decision = ZebraAgentOnboardingCoordinator().decisionAfterInstallCompleted(
            selectedAgent: .antigravity,
            candidates: [
                candidate(.antigravity, installState: .installed),
            ]
        )

        XCTAssertEqual(
            decision,
            .launch(agent: .antigravity, selectionMode: .installCompleted, shouldPersistPrimary: true)
        )
    }

    func testInstallFailureReturnsRecoverableFailureDecision() {
        let decision = ZebraAgentOnboardingCoordinator().decisionAfterInstallFailed(
            selectedAgent: .codex,
            message: "Installer exited 1"
        )

        XCTAssertEqual(decision, .installFailed(agent: .codex, message: "Installer exited 1"))
    }

    private func candidate(
        _ kind: ZebraAgentKind,
        installState: ZebraAgentInstallState
    ) -> ZebraAgentInstallCandidate {
        ZebraAgentInstallCandidate(
            id: kind,
            displayName: kind.displayName,
            binaryName: kind.binaryName,
            executablePath: installState == .installed ? "/bin/\(kind.binaryName)" : nil,
            appBundlePath: nil,
            version: nil,
            installState: installState,
            authState: .unknown,
            terminalLaunchable: installState == .installed,
            recommendedAction: installState == .installed ? .launch : .install
        )
    }
}
