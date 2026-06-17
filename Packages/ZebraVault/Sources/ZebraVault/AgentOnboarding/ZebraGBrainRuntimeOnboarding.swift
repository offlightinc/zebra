import Foundation

public struct ZebraGBrainRuntimeOnboardingStore {
    public struct LaunchContext {
        public let launchDirectory: String
        public let startupLine: String
        public let startupPrompt: String
        public let helperPath: String
        public let documentPath: String
        public let shellEnvironmentPrefix: String
    }

    public struct SelectedRuntime: Equatable {
        public let runtime: String
        public let executablePath: String

        public init(runtime: String, executablePath: String) {
            self.runtime = runtime
            self.executablePath = executablePath
        }
    }

    public struct CompletionResult: Equatable {
        public let isComplete: Bool
        public let reasons: [String]
    }

    public struct InteractiveAuthRequest: Equatable {
        public let id: String
        public let authKey: String
        public let runtime: String
        public let provider: String
        public let runtimeProvider: String?
        public let reason: String?
        public let requestedAt: String?
        public let startupLine: String
    }

    private struct State: Codable {
        var schemaVersion: Int
        var receipt: Receipt?
    }

    private struct Receipt: Codable {
        var complete: Bool?
        var runtime: String?
        var executablePath: String?
        var version: String?
        var provider: String?
        var keySource: String?
        var configPaths: [String: String]?
        var verifiedAt: String?
        var checks: [String: Bool]?
        var reasons: [String]?
    }

    private let stateURL: URL
    private let fileManager: FileManager
    private let homeDirectoryPath: String
    private let onboardingLanguage: ZebraOnboardingLanguage

    public init(
        stateURL: URL = ZebraGBrainRuntimeOnboardingStore.defaultStateURL(),
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        appPreferredLocalizations: [String] = Bundle.main.preferredLocalizations,
        preferredLanguages: [String] = Locale.preferredLanguages,
        currentLocaleIdentifier: String = Locale.current.identifier
    ) {
        self.stateURL = stateURL
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
        self.onboardingLanguage = ZebraOnboardingLanguage.current(
            appPreferredLocalizations: appPreferredLocalizations,
            preferredLanguages: preferredLanguages,
            currentLocaleIdentifier: currentLocaleIdentifier
        )
    }

    public static func defaultStateURL() -> URL {
        ZebraGBrainOnboardingStore.onboardingDirectoryURL()
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
    }

    public func isSetupCompleted() -> Bool {
        cachedCompletionResult().isComplete
    }

    public func cachedCompletionResult() -> CompletionResult {
        guard let state = loadState(),
              let receipt = state.receipt else {
            return CompletionResult(isComplete: false, reasons: ["missing_receipt"])
        }
        guard receipt.complete == true else {
            return CompletionResult(
                isComplete: false,
                reasons: nonEmpty(receipt.reasons) ?? ["receipt_incomplete"]
            )
        }
        guard Self.supportedRuntimeIDs.contains(receipt.runtime ?? "") else {
            return CompletionResult(isComplete: false, reasons: ["runtime_missing"])
        }
        guard let executablePath = nonEmpty(receipt.executablePath),
              fileManager.isExecutableFile(atPath: executablePath) else {
            return CompletionResult(isComplete: false, reasons: ["executable_missing"])
        }
        guard nonEmpty(receipt.keySource) != nil else {
            return CompletionResult(isComplete: false, reasons: ["credential_source_missing"])
        }
        guard receipt.checks?["credentials"] == true else {
            return CompletionResult(isComplete: false, reasons: ["credentials_unverified"])
        }
        guard receipt.checks?["runtimeConfigCommand"] == true else {
            return CompletionResult(isComplete: false, reasons: ["runtime_config_unverified"])
        }
        guard receipt.checks?["llmCall"] == true else {
            return CompletionResult(isComplete: false, reasons: ["llm_call_unverified"])
        }
        return CompletionResult(isComplete: true, reasons: [])
    }

    public func selectedRuntimeForGBrainSetup() -> SelectedRuntime? {
        guard cachedCompletionResult().isComplete,
              let receipt = loadState()?.receipt,
              let runtime = nonEmpty(receipt.runtime),
              Self.supportedRuntimeIDs.contains(runtime),
              let executablePath = nonEmpty(receipt.executablePath),
              fileManager.isExecutableFile(atPath: executablePath) else {
            return nil
        }
        return SelectedRuntime(runtime: runtime, executablePath: executablePath)
    }

    public func pendingInteractiveAuthRequest() -> InteractiveAuthRequest? {
        guard let data = try? Data(contentsOf: stateURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let interactiveAuth = object["interactiveAuth"] as? [String: Any],
              interactiveAuth["status"] as? String == "required" else {
            return nil
        }
        guard let runtime = nonEmpty(interactiveAuth["runtime"] as? String),
              Self.supportedRuntimeIDs.contains(runtime),
              let provider = nonEmpty(interactiveAuth["provider"] as? String),
              Self.isSafeInteractiveAuthIdentifier(provider),
              interactiveAuthArgvMatchesRequest(interactiveAuth, runtime: runtime, provider: provider),
              let startupLine = interactiveAuthStartupLine(runtime: runtime, provider: provider) else {
            return nil
        }
        let requestedAt = nonEmpty(interactiveAuth["requestedAt"] as? String)
        let authKey = "\(runtime)|\(provider)"
        let id = "\(authKey)|\(requestedAt ?? "pending")"
        return InteractiveAuthRequest(
            id: id,
            authKey: authKey,
            runtime: runtime,
            provider: provider,
            runtimeProvider: nonEmpty(interactiveAuth["runtimeProvider"] as? String),
            reason: nonEmpty(interactiveAuth["reason"] as? String),
            requestedAt: requestedAt,
            startupLine: startupLine
        )
    }

    public func prepareLaunch() -> LaunchContext? {
        guard let helperPath = installHelperScript() else { return nil }
        guard let documentPath = installInstructionDocument() else { return nil }
        let launchDirectory = onboardingWorkDirectoryPath()
        let helperDirectory = helperPath.deletingLastPathComponent().path
        let homeDirectory = homeDirectoryPath as NSString
        let pathEntries = [
            helperDirectory,
            homeDirectory.appendingPathComponent(".local/bin"),
            homeDirectory.appendingPathComponent(".bun/bin"),
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let environmentPrefix = [
            "cd \(ZebraAgentLaunchCommand.shellQuote(launchDirectory))",
            "export ZEBRA_GBRAIN_RUNTIME_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export ZEBRA_GBRAIN_RUNTIME_HOME=\(ZebraAgentLaunchCommand.shellQuote(homeDirectoryPath))",
            "export ZEBRA_ONBOARDING_LANGUAGE=\(ZebraAgentLaunchCommand.shellQuote(onboardingLanguage.code))",
            "export ZEBRA_GBRAIN_RUNTIME_DOC=\(ZebraAgentLaunchCommand.shellQuote(documentPath.path))",
            "export PATH=\(pathEntries.map(ZebraAgentLaunchCommand.shellQuote).joined(separator: ":")):\"$PATH\"",
        ].joined(separator: " && ") + " && "
        let startupLine = environmentPrefix + "\(ZebraAgentLaunchCommand.shellQuote(helperPath.path)) run\r"
        return LaunchContext(
            launchDirectory: launchDirectory,
            startupLine: startupLine,
            startupPrompt: startupPrompt(helperPath: helperPath.path, documentPath: documentPath.path),
            helperPath: helperPath.path,
            documentPath: documentPath.path,
            shellEnvironmentPrefix: environmentPrefix
        )
    }

    private func loadState() -> State? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func installHelperScript() -> URL? {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
        let url = directory.appendingPathComponent("zebra-gbrain-runtime-onboarding", isDirectory: false)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.helperScript.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }

    private func installInstructionDocument() -> URL? {
        let url = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-runtime-agent-onboarding.md", isDirectory: false)
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.instructionDocument.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }

    private func interactiveAuthArgvMatchesRequest(
        _ interactiveAuth: [String: Any],
        runtime: String,
        provider: String
    ) -> Bool {
        guard let argv = interactiveAuth["argv"] as? [String] else {
            return true
        }
        guard argv.count == 5 else { return false }
        return argv[1] == "interactive-auth"
            && argv[2] == runtime
            && argv[3] == "--provider"
            && argv[4] == provider
    }

    private func interactiveAuthStartupLine(runtime: String, provider: String) -> String? {
        guard let helperPath = installHelperScript(),
              let documentPath = installInstructionDocument() else {
            return nil
        }
        let launchDirectory = onboardingWorkDirectoryPath()
        let helperDirectory = helperPath.deletingLastPathComponent().path
        let homeDirectory = homeDirectoryPath as NSString
        let pathEntries = [
            helperDirectory,
            homeDirectory.appendingPathComponent(".local/bin"),
            homeDirectory.appendingPathComponent(".bun/bin"),
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let command = [
            ZebraAgentLaunchCommand.shellQuote(helperPath.path),
            "interactive-auth",
            ZebraAgentLaunchCommand.shellQuote(runtime),
            "--provider",
            ZebraAgentLaunchCommand.shellQuote(provider),
        ].joined(separator: " ")
        let failureMessage = "Zebra runtime auth did not complete. This terminal will stay open so you can review the error or retry."
        let commands = [
            "cd \(ZebraAgentLaunchCommand.shellQuote(launchDirectory))",
            "export ZEBRA_GBRAIN_RUNTIME_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export ZEBRA_GBRAIN_RUNTIME_HOME=\(ZebraAgentLaunchCommand.shellQuote(homeDirectoryPath))",
            "export ZEBRA_ONBOARDING_LANGUAGE=\(ZebraAgentLaunchCommand.shellQuote(onboardingLanguage.code))",
            "export ZEBRA_GBRAIN_RUNTIME_DOC=\(ZebraAgentLaunchCommand.shellQuote(documentPath.path))",
            "export PATH=\(pathEntries.map(ZebraAgentLaunchCommand.shellQuote).joined(separator: ":")):\"$PATH\"",
            "if \(command); then exit; else printf '\\n%s\\n' \(ZebraAgentLaunchCommand.shellQuote(failureMessage)); fi",
        ]
        return commands.joined(separator: " && ") + "\r"
    }

    private func startupPrompt(helperPath: String, documentPath: String) -> String {
        """
        You are Zebra's Step 2 runtime setup agent.

        \(onboardingLanguage.promptPolicy)

        Before running setup commands, read the complete Step 2 instruction document at:
        \(documentPath)

        Then run:
        \(helperPath) status --json
        \(helperPath) preflight --json

        Follow the document exactly. Use `zebra-gbrain-runtime-onboarding report` before and after each section. Do not run a legacy interactive setup flow, do not prepare the GBrain source repo in Step 2, and do not invent install commands outside the helper contract.
        """
    }

    private func onboardingWorkDirectoryPath() -> String {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-runtime-work", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return Self.standardizedPath(directory.path)
    }

    private static func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static func isSafeInteractiveAuthIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 48...57, 65...90, 95, 97...122:
                return true
            default:
                return false
            }
        }
    }

    private static let supportedRuntimeIDs: Set<String> = [
        "openclaw",
        "hermes",
    ]

    private static let instructionDocument = """
    # Zebra GBrain Runtime Agent Onboarding

    이 문서는 Zebra 온보딩 Step 2의 기준 문서다.

    Step 2는 이후 GBrain setup을 받쳐 줄 OpenClaw 또는 Hermes runtime layer를
    준비한다. 이 단계는 agent-orchestrated flow다. Step 1에서 선택된 primary
    agent가 이 문서를 읽고, Zebra helper/report command를 호출하고, 진행 상태를
    기록한다. helper는 deterministic check, install, verification, state write만
    담당한다.

    Step 2는 GBrain source repo를 준비하지 않는다. Source repo 선택, clone/reuse,
    docs snapshot, `bun install`, `bun install -g .` 또는 `bun link`, 그리고
    `gbrain --version` 검증은 Step 3 책임으로 남긴다.

    ## 단계 경계

    ### Step 1: primary agent bootstrap

    Step 1은 Codex, Claude, Antigravity 중 하나를 global CLI로 실행 가능하게 만든다.
    아직 primary agent가 없으므로 Step 1은 deterministic shell-script flow가 맞다.

    Step 1이 끝나면 Zebra는 선택된 primary agent를 새 terminal에서 시작한다.

    ### Step 2: runtime/prerequisite setup

    Step 2는 primary agent가 진행한다.

    Agent는 반드시 다음을 지킨다:

    - 이 문서를 읽는다.
    - `zebra-gbrain-runtime-onboarding` command를 호출한다.
    - workflow section 전후로 `report`를 호출한다.
    - 제품 선택 또는 blocking OS prompt가 필요한 경우에만 사용자에게 묻는다.
    - 이 contract 밖의 install command를 임의로 만들지 않는다.

    Helper는 다음을 담당한다:

    - prerequisite fact를 감지한다.
    - 승인된 recovery/install command를 실행한다.
    - 선택된 runtime을 configure한다.
    - 선택된 runtime이 LLM을 호출할 수 있는지 verify한다.
    - state와 final receipt를 쓴다.

    Helper는 runtime/provider 선택을 사용자에게 직접 묻고 setup 전체를 끝까지 진행하는
    end-to-end interactive flow를 실행하면 안 된다.

    ### Step 3: GBrain setup

    Step 3는 기존 repo-first GBrain flow를 유지한다.

    Step 3는 `activeGBrainBinding.sourceRepoPath`를 준비하고, `~/gbrain` 또는
    사용자가 선택한 source repo를 clone/reuse하고, local GBrain docs를 snapshot하고,
    repo-local `bun install`을 실행하고, active repo를 user-visible `gbrain` command로
    노출한 뒤 `gbrain --version`을 검증한다.

    ## 문서 모델

    Step 2는 이 고정 Zebra-owned 문서를 authoritative workflow document로 사용한다.

    Step 2용 run-specific prompt artifact는 만들지 않는다. Step 3는 active GBrain source
    docs와 snapshot commit이 실행마다 달라질 수 있어서 section prompt를 실행마다 생성한다.
    Step 2에는 그런 외부 문서 snapshot 문제가 없다.

    현재 실행 context는 helper에서 가져온다:

    ```bash
    zebra-gbrain-runtime-onboarding run
    zebra-gbrain-runtime-onboarding status --json
    zebra-gbrain-runtime-onboarding preflight --json
    ```

    `run`은 non-interactive wrapper다. 현재 status, next action, 이 문서 경로를 출력할
    수는 있지만, 질문을 하거나 full setup flow를 직접 수행하면 안 된다.

    ## Helper Command

    Step 2 helper는 `zebra-gbrain-runtime-onboarding`이다.

    작고 deterministic한 command를 제공해야 한다:

    ```bash
    zebra-gbrain-runtime-onboarding run
    zebra-gbrain-runtime-onboarding status --json
    zebra-gbrain-runtime-onboarding preflight --json
    zebra-gbrain-runtime-onboarding report --status <status> --section <section> [--note <note>]
    zebra-gbrain-runtime-onboarding recover-prerequisite <clt|node|bun>
    zebra-gbrain-runtime-onboarding install-runtime <openclaw|hermes>
    zebra-gbrain-runtime-onboarding configure-runtime <openclaw|hermes> ...
    zebra-gbrain-runtime-onboarding interactive-auth <openclaw|hermes> --provider <provider-id>
    zebra-gbrain-runtime-onboarding verify-runtime <openclaw|hermes>
    zebra-gbrain-runtime-onboarding write-receipt
    ```

    허용되는 report status:

    ```text
    started
    completed
    waiting_for_user
    failed
    ```

    Agent는 다음과 같은 형태로 report를 사용한다:

    ```bash
    zebra-gbrain-runtime-onboarding report --status started --section "Baseline preflight"
    zebra-gbrain-runtime-onboarding preflight --json
    zebra-gbrain-runtime-onboarding report --status completed --section "Baseline preflight"
    ```

    ## Workflow

    ### 1. Baseline preflight

    가장 먼저 preflight를 실행한다. Preflight는 넓게 감지하되 아무것도 설치하지 않는다.

    Preflight fact에는 다음을 포함한다:

    - `python3`
    - `/bin/sh`
    - `/bin/bash`
    - `curl`
    - `git`
    - `xcode-select` / Command Line Tools 상태
    - `node`
    - `npm`
    - `bun`
    - `openclaw`
    - `hermes`

    각 fact는 다음을 기록한다:

    - `detectedAt`
    - `ok`
    - `path`
    - `version`
    - `requiredFor`
    - `blockingNow`
    - `reason`

    특정 경로에서만 필요한 tool이 없다고 해서 즉시 blocker로 만들지 않는다. 예를 들어
    `npm`이 없어도 사용자가 OpenClaw를 선택하기 전에는 blocking이 아니다.

    ### 2. Choose runtime

    Agent가 preflight 결과를 보고 user-facing runtime branch를 선택하게 한다. Helper가
    이 질문을 직접 하면 안 된다.

    유효한 runtime 선택지:

    ```text
    openclaw
    hermes
    ```

    Agent는 현재 상태에 맞는 선택지만 설명한다:

    - OpenClaw만 설치됨: OpenClaw 사용, 또는 Hermes 설치 후 사용.
    - Hermes만 설치됨: Hermes 사용, 또는 OpenClaw 설치 후 사용.
    - 둘 다 설치됨: 사용할 runtime 선택.
    - 둘 다 없음: Zebra가 설치할 runtime 선택.

    Agent는 선택되지 않은 runtime의 dependency를 설치하지 않는다.

    ### 3. Recover common prerequisites

    선택된 runtime과 무관하게 Step 3에서 필요한 prerequisite만 복구한다:

    - Command Line Tools / `git`
    - `bun`

    Python은 설치하지 않는다.

    Command Line Tools가 없으면 다음을 trigger한다:

    ```bash
    xcode-select --install
    ```

    이 작업은 recoverable이지만 blocking이다. 사용자가 macOS installer UI를 완료해야
    하기 때문이다. `blockingReason: clt_install_required`를 기록한다.

    `bun`이 없으면 official Bun installer를 사용한다:

    ```bash
    curl -fsSL https://bun.sh/install | bash
    ```

    `~/.bun/bin/bun --version`을 검증한다. 새 shell에서 `bun`이 PATH로 resolve되는지도
    기록한다.

    ### 4. Recover selected-runtime prerequisites

    선택된 runtime에 필요한 prerequisite만 복구한다.

    #### OpenClaw

    OpenClaw는 Node/npm이 필요하다.

    `node` 또는 `npm`이 없으면 official Node.js macOS pkg install path를 사용한다.
    Homebrew를 설치하지 않는다. Zebra-private Node/npm runtime을 만들지 않는다.

    Node 설치 후 일반 terminal PATH에서 다음이 resolve되는지 검증한다:

    ```bash
    node --version
    npm --version
    ```

    `openclaw`가 없으면 다음으로 설치한다:

    ```bash
    npm install -g openclaw
    ```

    설치 전에 `npm config get prefix`로 현재 npm global prefix를 확인한다. 현재 prefix가
    global package install에 필요한 `bin`과 `lib/node_modules`를 쓸 수 있으면 그대로 둔다.
    root-owned `/usr/local`처럼 현재 사용자가 쓸 수 없는 prefix면 다음을 먼저 실행한다:

    ```bash
    mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/node_modules"
    npm config set prefix "$HOME/.local"
    ```

    그 뒤 같은 `npm install -g openclaw`를 실행한다. 이 설정은 Zebra-private runtime이
    아니라 사용자 계정의 npm global prefix를 고치는 것이다. 이후 `~/.local/bin`이 PATH에
    있으면 `openclaw`와 future npm global command가 일반 terminal에서도 resolve된다.

    #### Hermes

    Hermes는 이 onboarding path에서 Node/npm을 요구하지 않는다.

    `hermes`가 없으면 현재 검증된 minimal installer command를 그대로 사용한다:

    ```bash
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup --skip-browser --no-skills --non-interactive
    ```

    Hermes detect 후보:

    - `command -v hermes`
    - `$HERMES_INSTALL_DIR/venv/bin/hermes`
    - `~/.local/bin/hermes`
    - `~/.hermes/hermes-agent/venv/bin/hermes`
    - `/usr/local/bin/hermes`

    Python/venv installer failure는 exit code, stderr tail, blocking reason과 함께 기록한다.

    ### 5. Configure selected runtime

    선택된 runtime만 configure한다.

    필요하면 agent가 사용자에게 LLM connection/provider 선택을 묻는다. Helper는 구체적인
    runtime configuration command를 실행하고 non-secret state를 쓴다.

    Provider 선택을 물을 때는 bullet list를 쓰지 말고 번호 선택지로 제시한다. 사용자는
    provider id가 아니라 번호로 답할 수 있어야 한다. 예:

    ```text
    사용할 계정/키 방식을 선택해주세요.

    1. ChatGPT/Codex 계정으로 로그인
    2. Claude Code 계정으로 로그인
    3. OpenRouter API key 사용
    4. Anthropic API key 사용
    5. Google Gemini API key 사용
    6. OpenAI API key 사용
    ```

    Hermes runtime에서만 2번 선택지 label을 다음처럼 바꾼다:

    ```text
    2. Claude Code 계정으로 로그인 (Claude Max plan + extra usage credits 필수)
    ```

    사용자가 OpenClaw + Claude Code를 선택하면 agent는 다음 command를 그대로 호출한다:

    ```bash
    zebra-gbrain-runtime-onboarding configure-runtime openclaw --provider anthropic-claude-code
    ```

    그 외 선택지는 해당 provider id로 `configure-runtime <runtime> --provider
    <provider-id>`를 호출한다.

    Secret 값은 Zebra state에 쓰면 안 된다. State에는 environment variable 이름,
    OAuth source, entered-key source label 같은 key source만 기록할 수 있다.

    OpenClaw/Hermes OAuth 또는 provider CLI login이 실제 terminal TTY를 요구하면,
    agent tool 안에서 login command를 계속 실행하지 않는다. Helper는
    `interactive_auth_required`를 state에 쓰고, 실제 Zebra terminal에서 실행할
    `interactive-auth` command를 `interactiveAuth.command`에 기록한다.
    Zebra 앱은 이 pending state를 watch해서 실제 terminal을 연다. 앱은 state의 raw
    command string을 그대로 실행하지 않고, `runtime`, `provider`, `requestedAt` 같은
    구조화된 request 값을 검증한 뒤 Zebra-owned helper command를 조립해서 실행한다.
    같은 request는 자동으로 한 번만 실행하고, 같은 runtime/provider의 반복 request는 짧은
    간격 안에서 다시 열지 않는다. Auth command가 성공하면 terminal은 자동 종료되고,
    실패하거나 취소되면 사용자가 원인을 확인할 수 있도록 terminal을 남긴다.

    OpenClaw + Claude Code에서 `openclaw_claude_cli_registration_requires_tty`가 나오면,
    Claude Code 계정 로그인이 필요한 상태가 아니다. Claude CLI 로그인은 이미 확인됐고,
    OpenClaw가 그 로그인을 재사용하도록 등록하는 단계다. 이때는 다음처럼 안내한다:

    ```text
    OpenClaw가 Claude CLI 로그인을 재사용하도록 등록합니다.

    새 터미널이 열려 자동 등록을 진행하고, 성공하면 자동으로 닫힙니다.
    터미널이 닫히면 여기로 돌아와 완료됐다고 알려주세요.
    ```

    Agent는 이 상태를 실패로 처리하지 않는다. 사용자가 real terminal에서
    `interactive-auth`를 완료한 뒤에는 `configure-runtime`을 다시 호출하지 않는다.
    먼저 `status --json`을 호출하고, `runtimeConfig.result.ok == true`이면 바로
    `verify-runtime <runtime>`으로 넘어간다. `runtimeVerification.result.ok == true`이면
    `write-receipt`를 호출한다.

    ### 6. Verify selected runtime

    선택된 runtime이 minimal LLM call을 할 수 있는지 verify한다.

    OpenClaw는 model/auth status probe path를 사용한다.

    Hermes는 helper에서 이미 사용하는 minimal chat/status path를 사용한다.

    Verification 결과는 `llmCall` check로 기록한다.

    ### 7. Write runtime receipt

    선택된 runtime이 설치, configure, verify까지 끝나면 final receipt를 다음 파일에 쓴다:

    ```text
    ~/Library/Application Support/zebra/onboarding/gbrain-runtime-state.json
    ```

    Checklist는 receipt가 complete이고 required check가 모두 true일 때만 Step 2를 완료로
    봐야 한다.

    ## Prerequisite Policy

    ### python3

    Python은 설치하지 않는다.

    가능하면 system/CLT 제공 `python3`를 사용한다. 없으면 `python3_missing` 같은 blocking
    state를 기록한다. Python installer를 실행하지 않는다.

    ### /bin/sh and /bin/bash

    이 둘은 system tool이다. 둘 중 하나가 없으면 machine이 blocked 또는 damaged 상태라고
    본다. Shell replacement를 설치하려고 하지 않는다.

    ### curl

    `curl`은 Bun과 Hermes installer에 필요하다. 없으면 blocking state를 기록한다. 이
    flow에서 curl을 따로 설치하지 않는다.

    ### git and Command Line Tools

    Step 3는 GBrain source repo clone/reuse와 docs snapshot을 위해 `git`이 필요하다.

    Command Line Tools 또는 usable `git`이 없으면 다음을 trigger한다:

    ```bash
    xcode-select --install
    ```

    그 뒤 사용자가 macOS installer UI를 완료하고 preflight를 다시 실행할 때까지
    `waiting_for_user`를 report한다.

    ### Node and npm

    Node/npm은 OpenClaw branch에서만 필요하다.

    OpenClaw가 선택됐고 Node/npm이 없으면 official Node.js macOS pkg path로 설치한다.
    결과는 Zebra 안에서만이 아니라 일반 terminal에서도 사용할 수 있어야 한다.

    ### Bun

    Bun은 Step 3 GBrain setup에 필요하다. 없으면 official Bun installer로 설치한다.

    ### OpenClaw

    OpenClaw는 사용자가 OpenClaw를 선택했고 설치되어 있지 않을 때만 설치한다. 설치 명령:

    ```bash
    npm install -g openclaw
    ```

    ### Hermes

    Hermes는 사용자가 Hermes를 선택했고 설치되어 있지 않을 때만 설치한다. Dynamic flag
    discovery 없이 검증된 minimal Hermes installer command를 사용한다.

    ## State File

    Step 2 state 위치:

    ```text
    ~/Library/Application Support/zebra/onboarding/gbrain-runtime-state.json
    ```

    State에는 다음을 포함한다:

    ```text
    schemaVersion
    progress
    preflight
    attempts
    selection
    receipt
    ```

    `progress`에는 다음을 포함한다:

    - current section
    - completed sections
    - waiting-for-user reason
    - last failure

    `preflight`에는 fact와 detection timestamp를 포함한다.

    `attempts`에는 다음을 포함한다:

    - attempted command
    - started/finished timestamp
    - exit code
    - stdout tail
    - stderr tail
    - recoverable flag
    - blocking reason

    `selection`에는 다음을 포함한다:

    - selected runtime
    - selected provider when chosen

    `receipt`에는 다음을 포함한다:

    - complete
    - runtime
    - executable path
    - version
    - provider
    - key source
    - config paths
    - checks
    - verified timestamp
    - reasons

    ## 사람 검증용 요약

    이 섹션은 설계 의도가 대략 맞는지 빠르게 확인하기 위한 요약이다.

    - Step 1은 agent-driven 작업 전에 global primary agent CLI를 먼저 bootstrap한다.
    - Step 2는 primary-agent orchestrated flow다. Agent가 이 고정 문서를 읽고
      helper/report command를 호출한다.
    - Step 2는 run-specific packet을 만들지 않는다.
    - Step 2는 GBrain source repo를 prepare/clone/install하지 않는다.
    - Step 3는 `activeGBrainBinding.sourceRepoPath`, GBrain repo clone/reuse, docs
      snapshot, `bun install`, `bun install -g .` 또는 `bun link`, `gbrain --version`을
      계속 담당한다.
    - Preflight는 넓게 감지하지만 아무것도 설치하지 않는다.
    - Recovery는 선택된 경로에 필요한 것만 설치한다.
    - `npm`이 없어도 OpenClaw가 선택되기 전에는 문제가 아니다.
    - Zebra는 Python을 설치하지 않는다. 기존 macOS/CLT `python3`를 사용한다.
    - CLT/git recovery는 `xcode-select --install`이고, 이후 user-waiting/blocking
      상태가 된다.
    - Node/npm recovery는 official Node.js macOS pkg를 사용한다. Homebrew도 아니고
      Zebra-private runtime도 아니다.
    - Bun recovery는 official Bun installer를 사용한다.
    - OpenClaw install은 `npm install -g openclaw`를 유지하되, npm global prefix가
      root-owned/write 불가면 먼저 `npm config set prefix "$HOME/.local"`을 적용한다.
    - Hermes install은 이미 검증된 minimal installer command를 유지한다.
    - Step 2 완료 기준은 binary 존재 여부가 아니라 `gbrain-runtime-state.json`의 runtime
      receipt다.

    """

    private func nonEmpty(_ values: [String]?) -> [String]? {
        guard let values, !values.isEmpty else { return nil }
        return values
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static let helperScript = """
    #!/bin/sh
    set -eu

    STATE="${ZEBRA_GBRAIN_RUNTIME_STATE:-$HOME/Library/Application Support/zebra/onboarding/gbrain-runtime-state.json}"
    COMMAND="${1:-run}"
    if [ $# -gt 0 ]; then
      shift
    fi

    write_shell_python_blocked_state() {
      reason="${1:-python3_missing}"
      status="${2:-failed}"
      attempt_command="${3:-}"
      attempt_exit_code="${4:-}"
      waiting_note="${5:-}"
      python_present=false
      python_path=""
      if [ -n "${PYTHON_BIN:-}" ]; then
        python_present=true
        python_path="$PYTHON_BIN"
      fi
      DETECTED_AT="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown')"
      STATE_DIR="${STATE%/*}"
      if [ "$STATE_DIR" != "$STATE" ]; then
        /bin/mkdir -p "$STATE_DIR" 2>/dev/null || true
      fi
      {
        printf '{\n'
        printf '  "schemaVersion": 1,\n'
        printf '  "progress": {\n'
        printf '    "status": "%s",\n' "$status"
        printf '    "currentSection": "Baseline preflight",\n'
        if [ -n "$waiting_note" ]; then
          printf '    "waitingForUser": {\n'
          printf '      "section": "Recover common prerequisites",\n'
          printf '      "note": "Install macOS Command Line Tools, then rerun Step 2.",\n'
          printf '      "createdAt": "%s"\n' "$DETECTED_AT"
          printf '    },\n'
        fi
        printf '    "lastFailure": {\n'
        printf '      "reason": "%s",\n' "$reason"
        printf '      "recoverable": true,\n'
        printf '      "updatedAt": "%s"\n' "$DETECTED_AT"
        printf '    }\n'
        printf '  },\n'
        if [ -n "$attempt_command" ]; then
          printf '  "attempts": [\n'
          printf '    {\n'
          printf '      "attemptedCommand": "%s",\n' "$attempt_command"
          printf '      "startedAt": "%s",\n' "$DETECTED_AT"
          printf '      "finishedAt": "%s",\n' "$DETECTED_AT"
          printf '      "exitCode": %s,\n' "${attempt_exit_code:-1}"
          printf '      "stdoutTail": "",\n'
          printf '      "stderrTail": "",\n'
          printf '      "recoverable": true,\n'
          printf '      "blockingReason": "%s"\n' "$reason"
          printf '    }\n'
          printf '  ],\n'
        fi
        printf '  "preflight": {\n'
        printf '    "detectedAt": "%s",\n' "$DETECTED_AT"
        printf '    "facts": {\n'
        printf '      "python3": {\n'
        printf '        "name": "python3",\n'
        printf '        "ok": false,\n'
        printf '        "present": %s,\n' "$python_present"
        printf '        "path": "%s",\n' "$python_path"
        printf '        "version": "",\n'
        printf '        "requiredFor": ["step2-helper"],\n'
        printf '        "blockingNow": true,\n'
        printf '        "recoverable": true,\n'
        printf '        "reason": "%s",\n' "$reason"
        printf '        "blockingReason": "%s"\n' "$reason"
        printf '      }\n'
        printf '    }\n'
        printf '  }\n'
        printf '}\n'
      } > "$STATE" 2>/dev/null || true
    }

    print_shell_python_blocked_status() {
      reason="${1:-python3_missing}"
      printf '{\n'
      printf '  "ok": false,\n'
      printf '  "statePath": "%s",\n' "$STATE"
      printf '  "blockingReason": "%s",\n' "$reason"
      printf '  "next": [\n'
      printf '    "Install macOS Command Line Tools so /usr/bin/python3 can run.",\n'
      printf '    "Then rerun Zebra Step 2 runtime setup."\n'
      printf '  ]\n'
      printf '}\n'
    }

    request_shell_clt_install() {
      XCODE_SELECT_BIN="$(command -v xcode-select || printf '/usr/bin/xcode-select')"
      if "$XCODE_SELECT_BIN" --install >/dev/null 2>&1; then
        write_shell_python_blocked_state "clt_install_required" "waiting_for_user" "xcode-select --install" "0" "1"
        printf '{\n  "ok": false,\n  "requiresUserAction": true,\n  "blockingReason": "clt_install_required",\n  "statePath": "%s"\n}\n' "$STATE"
        return 0
      fi

      code="$?"
      write_shell_python_blocked_state "clt_manual_install_required" "failed" "xcode-select --install" "$code" ""
      printf '{\n  "ok": false,\n  "requiresUserAction": true,\n  "blockingReason": "clt_manual_install_required",\n  "statePath": "%s"\n}\n' "$STATE"
      echo "xcode-select --install could not request Command Line Tools. Install CLT manually, then rerun Step 2." >&2
      return 1
    }

    PYTHON_BIN="$(command -v python3 || true)"
    PYTHON_READY=0
    PYTHON_BLOCK_REASON="python3_missing"
    if [ -n "$PYTHON_BIN" ]; then
      if "$PYTHON_BIN" -c 'import sys' >/dev/null 2>&1; then
        PYTHON_READY=1
      else
        PYTHON_BLOCK_REASON="python3_unusable"
      fi
    fi

    if [ "$PYTHON_READY" != "1" ]; then
      case "$COMMAND" in
        recover-prerequisite)
          target="${1:-}"
          if [ "$target" = "clt" ]; then
            request_shell_clt_install
            exit "$?"
          fi
          write_shell_python_blocked_state "$PYTHON_BLOCK_REASON" "failed" "" "" ""
          print_shell_python_blocked_status "$PYTHON_BLOCK_REASON"
          echo "python3 is required before recover-prerequisite $target can run" >&2
          exit 1
          ;;
        report)
          write_shell_python_blocked_state "$PYTHON_BLOCK_REASON" "failed" "" "" ""
          printf '{\n  "ok": true,\n  "statePath": "%s",\n  "blockingReason": "%s"\n}\n' "$STATE" "$PYTHON_BLOCK_REASON"
          exit 0
          ;;
        run|status|preflight|"")
          request_shell_clt_install
          exit "$?"
          ;;
        *)
          write_shell_python_blocked_state "$PYTHON_BLOCK_REASON" "failed" "" "" ""
          print_shell_python_blocked_status "$PYTHON_BLOCK_REASON"
          echo "python3 is required for zebra-gbrain-runtime-onboarding $COMMAND" >&2
          exit 1
          ;;
      esac
    fi

    if [ -z "$PYTHON_BIN" ]; then
      write_shell_python_blocked_state "python3_missing" "failed" "" "" ""
      print_shell_python_blocked_status "python3_missing"
      echo "python3 is required for zebra-gbrain-runtime-onboarding" >&2
      exit 1
    fi

    resolve_helper_path() {
      case "$0" in
        */*)
          helper_dir_name="$(dirname "$0")"
          helper_base_name="$(basename "$0")"
          helper_dir_abs="$(cd "$helper_dir_name" 2>/dev/null && pwd -P || true)"
          if [ -n "$helper_dir_abs" ]; then
            printf '%s/%s\n' "$helper_dir_abs" "$helper_base_name"
          else
            printf '%s\n' "$0"
          fi
          ;;
        *)
          command -v "$0" 2>/dev/null || printf '%s\n' "$0"
          ;;
      esac
    }

    export ZEBRA_GBRAIN_RUNTIME_HELPER_PATH="$(resolve_helper_path)"
    "$PYTHON_BIN" - "$STATE" "$COMMAND" "$@" <<'PY'
    import contextlib
    import getpass
    import json
    import os
    import shlex
    import shutil
    import subprocess
    import sys
    import time
    import urllib.request
    from datetime import datetime, timezone
    from pathlib import Path
    try:
        import fcntl
    except Exception:
        fcntl = None

    state_path = Path(sys.argv[1]).expanduser()
    command = sys.argv[2] or "run"
    home = Path(os.environ.get("ZEBRA_GBRAIN_RUNTIME_HOME") or str(Path.home())).expanduser()
    language = (os.environ.get("ZEBRA_ONBOARDING_LANGUAGE") or "en").split("-")[0].lower()
    if language not in {"en", "ja", "ko"}:
        language = "en"

    provider_choices = [
        {"id": "openai-codex", "label": "OpenAI Codex account login", "env": "", "auth_type": "oauth", "openclaw_provider": "openai", "openclaw_auth": "openai", "hermes_provider": "openai-codex", "hermes_model": "gpt-5.5", "hermes_base_url": "https://chatgpt.com/backend-api/codex", "hermes_base_env": "HERMES_CODEX_BASE_URL", "hermes_api_mode": "codex_responses"},
        {"id": "anthropic-claude-code", "label": "Anthropic Claude Code account login", "env": "", "auth_type": "oauth", "openclaw_provider": "claude-cli", "openclaw_auth": "anthropic-cli", "hermes_provider": "anthropic", "hermes_model": "claude-opus-4-8", "hermes_base_url": "https://api.anthropic.com", "hermes_base_env": "ANTHROPIC_BASE_URL", "hermes_api_mode": "anthropic_messages"},
        {"id": "openrouter", "label": "OpenRouter", "env": "OPENROUTER_API_KEY", "auth_type": "api_key", "openclaw_provider": "openrouter", "openclaw_auth": "openrouter-api-key", "hermes_provider": "openrouter", "hermes_model": "google/gemini-3.5-flash", "hermes_base_url": "https://openrouter.ai/api/v1", "hermes_base_env": "OPENROUTER_BASE_URL", "hermes_api_mode": "chat_completions"},
        {"id": "anthropic-api", "label": "Anthropic API key", "env": "ANTHROPIC_API_KEY", "auth_type": "api_key", "openclaw_provider": "anthropic", "openclaw_auth": "apiKey", "hermes_provider": "anthropic", "hermes_model": "claude-haiku-4-5-20251001", "hermes_base_url": "https://api.anthropic.com", "hermes_base_env": "ANTHROPIC_BASE_URL", "hermes_api_mode": "anthropic_messages"},
        {"id": "google", "label": "Google Gemini", "env": "GOOGLE_API_KEY", "auth_type": "api_key", "openclaw_provider": "google", "openclaw_auth": "google-api-key", "hermes_provider": "gemini", "hermes_model": "gemini-3.5-flash", "hermes_base_url": "https://generativelanguage.googleapis.com/v1beta", "hermes_base_env": "GEMINI_BASE_URL", "hermes_api_mode": "chat_completions"},
        {"id": "openai-api", "label": "OpenAI API key", "env": "OPENAI_API_KEY", "auth_type": "api_key", "openclaw_provider": "openai", "openclaw_auth": "openai-api-key", "hermes_provider": "openai-api", "hermes_model": "gpt-5-mini", "hermes_base_url": "https://api.openai.com/v1", "hermes_base_env": "OPENAI_BASE_URL", "hermes_api_mode": "codex_responses"},
    ]

    def now():
        return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    def message(en, ko=None, ja=None):
        if language == "ko" and ko:
            return ko
        if language == "ja" and ja:
            return ja
        return en

    def load_state():
        try:
            with state_path.open("r", encoding="utf-8") as handle:
                return json.load(handle)
        except Exception:
            return {"schemaVersion": 1}

    def save_state(state):
        state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = state_path.with_suffix(state_path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\\n")
        os.replace(tmp, state_path)

    def parse_flags(argv):
        flags = {}
        positional = []
        i = 0
        while i < len(argv):
            item = argv[i]
            if item.startswith("--"):
                key = item[2:].replace("-", "_")
                if "=" in key:
                    key, value = key.split("=", 1)
                    flags[key] = value
                    i += 1
                elif i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                    flags[key] = argv[i + 1]
                    i += 2
                else:
                    flags[key] = "true"
                    i += 1
            else:
                positional.append(item)
                i += 1
        flags["_positional"] = positional
        return flags

    def output_tail(text, limit=2000):
        if not text:
            return ""
        return text[-limit:]

    def redacted_result(result, credential=None):
        credential = credential or {}
        output = {
            "ok": bool(result.get("ok")),
            "exitCode": result.get("code"),
            "stdoutTail": output_tail(redact_output(result.get("stdout", ""), credential)),
            "stderrTail": output_tail(redact_output(result.get("stderr", ""), credential)),
        }
        if result.get("requiresInteractiveAuth"):
            output["requiresInteractiveAuth"] = True
            output["blockingReason"] = result.get("blockingReason") or "interactive_auth_required"
            output["interactiveAuthCommand"] = result.get("interactiveAuthCommand") or ""
        return output

    def record_attempt(kind, attempted_command, result, *, recoverable=True, blocking_reason=""):
        state = load_state()
        state["schemaVersion"] = 1
        attempts = state.setdefault("attempts", [])
        attempts.append({
            "kind": kind,
            "attemptedCommand": attempted_command,
            "finishedAt": now(),
            "exitCode": result.get("code"),
            "stdoutTail": output_tail(result.get("stdout", "")),
            "stderrTail": output_tail(result.get("stderr", "")),
            "recoverable": bool(recoverable),
            "blockingReason": blocking_reason,
        })
        save_state(state)

    def normalize_provider_id(provider_id):
        aliases = {
            "claude-code": "anthropic-claude-code",
        }
        return aliases.get(provider_id, provider_id)

    def provider_by_id(provider_id):
        provider_id = normalize_provider_id(provider_id)
        for provider in provider_choices:
            if provider["id"] == provider_id:
                return provider
        raise RuntimeError(f"unsupported_provider:{provider_id}")

    def non_secret_credential(credential):
        return {
            "source": credential.get("source", ""),
            "envName": credential.get("envName", ""),
            "persistEnvName": credential.get("persistEnvName", ""),
        }

    def executable_for_runtime(runtime):
        if runtime not in {"openclaw", "hermes"}:
            raise RuntimeError(f"unsupported_runtime:{runtime}")
        detected = detect_runtime(runtime)
        if not detected.get("installed"):
            raise RuntimeError(f"{runtime}_executable_missing")
        return detected

    def command_available(name):
        path = shutil.which(name) or ""
        return path

    def tool_candidate_paths(name):
        candidates = []
        path_match = shutil.which(name)
        if path_match:
            candidates.append(path_match)
        if name == "bun":
            candidates.extend([
                str(home / ".bun" / "bin" / "bun"),
                "/opt/homebrew/bin/bun",
                "/usr/local/bin/bun",
            ])
        seen = set()
        output = []
        for candidate in candidates:
            expanded = str(Path(candidate).expanduser())
            if expanded not in seen:
                seen.add(expanded)
                output.append(expanded)
        return output

    def first_executable_path(candidates):
        for candidate in candidates:
            if os.path.exists(candidate) and os.access(candidate, os.X_OK):
                return candidate
        return ""

    def version_for_command(path, *args):
        if not path:
            return ""
        result = run_process([path, *args], timeout=10)
        if result["ok"] and (result["stdout"] or result["stderr"]):
            return (result["stdout"] or result["stderr"]).splitlines()[0][:160]
        return ""

    def tool_fact(name, *, required_for=None, blocking_now=False, version_args=("--version",), path_override=None):
        candidates = [path_override] if path_override is not None and path_override else tool_candidate_paths(name)
        path = path_override if path_override is not None else first_executable_path(candidates)
        ok = bool(path and os.path.exists(path) and os.access(path, os.X_OK))
        version = version_for_command(path, *version_args) if ok and version_args else ""
        fact = {
            "detectedAt": now(),
            "ok": ok,
            "path": path or "",
            "version": version,
            "requiredFor": required_for or [],
            "blockingNow": bool(blocking_now and not ok),
            "reason": "" if ok else f"{name}_missing",
        }
        if candidates:
            fact["candidates"] = candidates
        return fact

    def file_fact(label, path, *, required_for=None, blocking_now=False):
        ok = os.path.exists(path) and os.access(path, os.X_OK)
        return {
            "detectedAt": now(),
            "ok": ok,
            "path": path,
            "version": "",
            "requiredFor": required_for or [],
            "blockingNow": bool(blocking_now and not ok),
            "reason": "" if ok else f"{label}_missing",
        }

    def xcode_select_fact():
        path = command_available("xcode-select") or "/usr/bin/xcode-select"
        result = run_process([path, "-p"], timeout=10) if os.path.exists(path) else {"ok": False, "stdout": "", "stderr": "xcode-select missing"}
        return {
            "detectedAt": now(),
            "ok": bool(result.get("ok") and result.get("stdout")),
            "path": (result.get("stdout") or "").strip(),
            "version": "",
            "requiredFor": ["gbrain-step3"],
            "blockingNow": not bool(result.get("ok") and result.get("stdout")),
            "reason": "" if result.get("ok") and result.get("stdout") else "clt_missing",
            "stderrTail": output_tail(result.get("stderr", "")),
        }

    def runtime_fact(name, *, required_for):
        detected = detect_runtime(name)
        return {
            "detectedAt": now(),
            "ok": bool(detected.get("installed")),
            "path": detected.get("path", ""),
            "version": detected.get("version", ""),
            "requiredFor": required_for,
            "blockingNow": False,
            "reason": "" if detected.get("installed") else f"{name}_missing",
            "candidates": detected.get("candidates", []),
        }

    def collect_preflight():
        python_path = command_available("python3") or sys.executable or ""
        facts = {
            "python3": tool_fact("python3", required_for=["helper-runtime"], blocking_now=True, path_override=python_path),
            "sh": file_fact("sh", "/bin/sh", required_for=["helper-runtime"], blocking_now=True),
            "bash": file_fact("bash", "/bin/bash", required_for=["hermes", "bun"], blocking_now=True),
            "curl": tool_fact("curl", required_for=["hermes", "bun", "node"], blocking_now=True),
            "git": tool_fact("git", required_for=["gbrain-step3"], blocking_now=True),
            "xcodeSelect": xcode_select_fact(),
            "node": tool_fact("node", required_for=["openclaw"], blocking_now=False),
            "npm": tool_fact("npm", required_for=["openclaw"], blocking_now=False),
            "bun": tool_fact("bun", required_for=["gbrain-step3"], blocking_now=True),
            "openclaw": runtime_fact("openclaw", required_for=["openclaw"]),
            "hermes": runtime_fact("hermes", required_for=["hermes"]),
        }
        return {"detectedAt": now(), "facts": facts}

    def write_preflight():
        preflight = collect_preflight()
        state = load_state()
        state["schemaVersion"] = 1
        state["preflight"] = preflight
        save_state(state)
        return preflight

    def report_progress(flags):
        status = flags.get("status", "")
        section = flags.get("section", "")
        note = flags.get("note", "")
        if status not in {"started", "completed", "waiting_for_user", "failed"}:
            raise RuntimeError("invalid_report_status")
        if not section:
            raise RuntimeError("report_section_missing")
        state = load_state()
        state["schemaVersion"] = 1
        progress = state.setdefault("progress", {})
        progress["currentSection"] = section
        progress["lastStatus"] = status
        progress["updatedAt"] = now()
        if status == "completed":
            completed = progress.setdefault("completedSections", [])
            if section not in completed:
                completed.append(section)
            if progress.get("waitingForUser", {}).get("section") == section:
                progress.pop("waitingForUser", None)
            progress.pop("lastFailure", None)
        elif status == "waiting_for_user":
            progress["waitingForUser"] = {
                "section": section,
                "note": note,
                "createdAt": now(),
            }
        elif status == "failed":
            progress["lastFailure"] = {
                "section": section,
                "note": note,
                "createdAt": now(),
            }
        save_state(state)
        print(json.dumps({"ok": True, "progress": progress}, indent=2, sort_keys=True))

    def run_process(argv, *, env=None, timeout=45, input_text=None):
        try:
            completed = subprocess.run(
                argv,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                timeout=timeout,
                input=input_text,
            )
            return {
                "ok": completed.returncode == 0,
                "code": completed.returncode,
                "stdout": completed.stdout.strip(),
                "stderr": completed.stderr.strip(),
            }
        except Exception as exc:
            return {"ok": False, "code": -1, "stdout": "", "stderr": str(exc)}

    def has_interactive_tty():
        if os.environ.get("ZEBRA_GBRAIN_RUNTIME_ASSUME_TTY", "").strip() == "1":
            return True
        try:
            with open("/dev/tty", "rb", buffering=0):
                return True
        except Exception:
            return False

    def helper_command_argv(runtime, provider_id):
        helper_path = os.environ.get("ZEBRA_GBRAIN_RUNTIME_HELPER_PATH", "").strip() or "zebra-gbrain-runtime-onboarding"
        return [helper_path, "interactive-auth", runtime, "--provider", provider_id]

    def helper_command_line(runtime, provider_id):
        env_parts = {
            "ZEBRA_GBRAIN_RUNTIME_STATE": str(state_path),
            "ZEBRA_GBRAIN_RUNTIME_HOME": str(home),
        }
        doc_path = os.environ.get("ZEBRA_GBRAIN_RUNTIME_DOC", "").strip()
        if doc_path:
            env_parts["ZEBRA_GBRAIN_RUNTIME_DOC"] = doc_path
        language = os.environ.get("ZEBRA_ONBOARDING_LANGUAGE", "").strip()
        if language:
            env_parts["ZEBRA_ONBOARDING_LANGUAGE"] = language
        argv = helper_command_argv(runtime, provider_id)
        return " ".join(
            [f"{key}={shlex.quote(value)}" for key, value in env_parts.items()]
            + [shlex.quote(part) for part in argv]
        )

    def interactive_auth_required_result(runtime, provider, reason):
        provider_id = provider.get("id", "")
        command = helper_command_line(runtime, provider_id)
        return {
            "ok": False,
            "code": 0,
            "stdout": "",
            "stderr": reason,
            "requiresInteractiveAuth": True,
            "blockingReason": "interactive_auth_required",
            "interactiveAuthCommand": command,
            "interactiveAuthArgv": helper_command_argv(runtime, provider_id),
        }

    def interactive_auth_waiting_note(runtime, provider, result):
        provider_id = provider.get("id", "")
        reason = result.get("stderr") or result.get("blockingReason") or "interactive_auth_required"
        if (
            runtime == "openclaw"
            and provider_id == "anthropic-claude-code"
            and reason == "openclaw_claude_cli_registration_requires_tty"
        ):
            return message(
                "OpenClaw will register Claude CLI login reuse.\\n\\nA new terminal will open, run the registration automatically, and close when it succeeds. When the terminal closes, return here and say it is complete.",
                "OpenClaw가 Claude CLI 로그인을 재사용하도록 등록합니다.\\n\\n새 터미널이 열려 자동 등록을 진행하고, 성공하면 자동으로 닫힙니다.\\n터미널이 닫히면 여기로 돌아와 완료됐다고 알려주세요.",
                "OpenClawがClaude CLIログインを再利用するよう登録します。\\n\\n新しいターミナルが開いて自動登録を実行し、成功すると自動で閉じます。ターミナルが閉じたら、ここに戻って完了したことを知らせてください。",
            )
        return message(
            "Run the interactive auth command in a real Zebra terminal, then rerun configure-runtime.",
            "실제 Zebra 터미널에서 interactive auth command를 실행한 뒤 configure-runtime을 다시 실행하세요.",
            "実際のZebraターミナルでinteractive auth commandを実行してから、configure-runtimeを再実行してください。",
        )

    def write_interactive_auth_request(runtime, provider, credential, result):
        provider_id = provider.get("id", "")
        state = load_state()
        state["schemaVersion"] = 1
        state["selection"] = {
            "selectedRuntime": runtime,
            "selectedProvider": provider_id,
            "runtimeProvider": provider_id_for_runtime(provider, runtime),
            "runtimeModel": provider.get("hermes_model") if runtime == "hermes" else "",
            "credential": non_secret_credential(credential),
            "updatedAt": now(),
        }
        state["runtimeConfig"] = {
            "configuredAt": now(),
            "result": redacted_result(result, credential),
        }
        state["interactiveAuth"] = {
            "status": "required",
            "runtime": runtime,
            "provider": provider_id,
            "runtimeProvider": provider_id_for_runtime(provider, runtime),
            "reason": result.get("stderr") or result.get("blockingReason") or "interactive_auth_required",
            "command": result.get("interactiveAuthCommand") or helper_command_line(runtime, provider_id),
            "argv": result.get("interactiveAuthArgv") or helper_command_argv(runtime, provider_id),
            "requestedAt": now(),
        }
        progress = state.setdefault("progress", {})
        progress["status"] = "waiting_for_user"
        progress["currentSection"] = "Configure selected runtime"
        progress["waitingForUser"] = {
            "section": "Configure selected runtime",
            "note": interactive_auth_waiting_note(runtime, provider, result),
            "createdAt": now(),
        }
        progress.pop("lastFailure", None)
        state["receipt"] = {
            "complete": False,
            "verifiedAt": now(),
            "reasons": ["interactive_auth_required"],
        }
        save_state(state)
        return state

    def completed_runtime_config_state(runtime, provider):
        provider_id = provider.get("id", "")
        state = load_state()
        selection = state.get("selection") or {}
        interactive_auth = state.get("interactiveAuth") or {}
        runtime_config = state.get("runtimeConfig") or {}
        config_result = runtime_config.get("result") or {}
        if selection.get("selectedRuntime") != runtime:
            return None
        if selection.get("selectedProvider") != provider_id:
            return None
        if interactive_auth.get("status") != "completed":
            return None
        if interactive_auth.get("runtime") != runtime or interactive_auth.get("provider") != provider_id:
            return None
        if not config_result.get("ok"):
            return None
        return state

    def next_recommended_command(state):
        receipt = state.get("receipt") or {}
        if receipt.get("complete"):
            return ""
        selection = state.get("selection") or {}
        runtime = selection.get("selectedRuntime", "")
        if not runtime:
            return "preflight"
        runtime_config_result = ((state.get("runtimeConfig") or {}).get("result") or {})
        runtime_verification_result = ((state.get("runtimeVerification") or {}).get("result") or {})
        interactive_auth = state.get("interactiveAuth") or {}
        if interactive_auth.get("status") == "required":
            return "status --json"
        if runtime_config_result.get("ok") and runtime_verification_result.get("ok"):
            return "write-receipt"
        if runtime_config_result.get("ok"):
            return f"verify-runtime {runtime}"
        provider_id = selection.get("selectedProvider", "")
        if provider_id:
            return f"configure-runtime {runtime} --provider {provider_id}"
        return f"configure-runtime {runtime}"

    def run_interactive_process(argv, *, env=None, timeout=600):
        try:
            with open("/dev/tty", "rb", buffering=0) as tty_in, open("/dev/tty", "wb", buffering=0) as tty_out:
                completed = subprocess.run(
                    argv,
                    stdin=tty_in,
                    stdout=tty_out,
                    stderr=tty_out,
                    env=env,
                    timeout=timeout,
                )
            return {"ok": completed.returncode == 0, "code": completed.returncode, "stdout": "", "stderr": ""}
        except Exception as exc:
            return {"ok": False, "code": -1, "stdout": "", "stderr": str(exc)}

    def interactive_process_done_grace_seconds():
        raw = os.environ.get("ZEBRA_GBRAIN_RUNTIME_INTERACTIVE_GRACE_SECONDS", "15")
        try:
            value = float(raw)
        except Exception:
            return 15.0
        if value < 0:
            return 0.0
        return min(value, 60.0)

    def run_interactive_process_until(argv, is_done, *, env=None, timeout=600):
        try:
            with open("/dev/tty", "rb", buffering=0) as tty_in, open("/dev/tty", "wb", buffering=0) as tty_out:
                process = subprocess.Popen(
                    argv,
                    stdin=tty_in,
                    stdout=tty_out,
                    stderr=tty_out,
                    env=env,
                )
                deadline = time.monotonic() + timeout
                while True:
                    code = process.poll()
                    if is_done():
                        if code is None:
                            grace_deadline = time.monotonic() + interactive_process_done_grace_seconds()
                            while time.monotonic() < grace_deadline:
                                time.sleep(0.25)
                                code = process.poll()
                                if code is not None:
                                    break
                        if code is None:
                            process.terminate()
                            try:
                                process.wait(timeout=5)
                            except subprocess.TimeoutExpired:
                                process.kill()
                                process.wait(timeout=5)
                        return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
                    if code is not None:
                        return {"ok": code == 0, "code": code, "stdout": "", "stderr": ""}
                    if time.monotonic() >= deadline:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=5)
                        return {"ok": False, "code": -1, "stdout": "", "stderr": "interactive_process_timeout"}
                    time.sleep(0.5)
        except Exception as exc:
            return {"ok": False, "code": -1, "stdout": "", "stderr": str(exc)}

    def credential_env(provider, credential):
        env = os.environ.copy()
        env_name = credential.get("envName") or provider.get("env", "")
        if credential.get("value") and env_name:
            env[env_name] = credential["value"]
        if provider.get("hermes_base_env") and provider.get("hermes_base_url"):
            env[provider["hermes_base_env"]] = provider["hermes_base_url"]
        return env

    def redact_output(text, credential):
        value = credential.get("value") if isinstance(credential, dict) else ""
        if value:
            text = text.replace(value, "<redacted>")
        return text

    def print_command_failure(result, credential):
        stdout = redact_output(result.get("stdout", ""), credential)
        stderr = redact_output(result.get("stderr", ""), credential)
        if stdout:
            print(stdout)
        if stderr:
            print(stderr, file=sys.stderr)

    def executable_version(path):
        for argv in ([path, "--version"], [path, "version"]):
            result = run_process(argv, timeout=10)
            if result["ok"] and (result["stdout"] or result["stderr"]):
                return (result["stdout"] or result["stderr"]).splitlines()[0][:160]
        return ""

    def prepend_path_once(directory):
        if not directory:
            return
        current = os.environ.get("PATH", "")
        parts = [part for part in current.split(os.pathsep) if part]
        if directory not in parts:
            os.environ["PATH"] = directory + (os.pathsep + current if current else "")

    def runtime_candidate_paths(name):
        candidates = []
        path_match = shutil.which(name)
        if path_match:
            candidates.append(path_match)
        if name == "hermes":
            install_dir = os.environ.get("HERMES_INSTALL_DIR", "").strip()
            if install_dir:
                candidates.append(str(Path(install_dir).expanduser() / "venv" / "bin" / "hermes"))
            candidates.extend([
                str(home / ".local" / "bin" / "hermes"),
                str(home / ".hermes" / "hermes-agent" / "venv" / "bin" / "hermes"),
                "/usr/local/bin/hermes",
            ])
        elif name == "openclaw":
            candidates.extend([
                str(home / ".local" / "bin" / "openclaw"),
                str(home / ".npm-global" / "bin" / "openclaw"),
                str(home / ".bun" / "bin" / "openclaw"),
                "/usr/local/bin/openclaw",
            ])
        seen = set()
        output = []
        for candidate in candidates:
            expanded = str(Path(candidate).expanduser())
            if expanded not in seen:
                seen.add(expanded)
                output.append(expanded)
        return output

    def detect_runtime(name):
        candidates = runtime_candidate_paths(name)
        path = ""
        for candidate in candidates:
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                path = candidate
                prepend_path_once(str(Path(candidate).parent))
                break
        return {
            "installed": bool(path),
            "path": path or "",
            "version": executable_version(path) if path else "",
            "candidates": candidates,
        }

    def detect_all():
        return {
            "openclaw": detect_runtime("openclaw"),
            "hermes": detect_runtime("hermes"),
        }

    def hermes_paths():
        return {
            "env": str(home / ".hermes" / ".env"),
            "config": str(home / ".hermes" / "config.yaml"),
        }

    def openclaw_paths():
        return {
            "config": os.environ.get("OPENCLAW_CONFIG_PATH") or str(home / ".openclaw" / "openclaw.json"),
            "home": os.environ.get("OPENCLAW_HOME") or str(home / ".openclaw"),
        }

    def read_env_file_vars(path):
        output = {}
        try:
            for line in Path(path).read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or "=" not in stripped:
                    continue
                key, value = stripped.split("=", 1)
                output[key.strip()] = value.strip().strip('"').strip("'")
        except Exception:
            pass
        return output

    def hermes_credential_env_names(provider):
        if provider.get("hermes_provider") == "anthropic":
            return ["ANTHROPIC_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY"]
        env_name = provider.get("env", "")
        return [env_name] if env_name else []

    def hermes_prompt_env_name(provider):
        if provider.get("hermes_provider") == "anthropic":
            return "ANTHROPIC_API_KEY"
        return provider.get("env", "")

    def agent_cli_state_path():
        return state_path.parent / "agent-cli-state.json"

    def agent_cli_events_path():
        return state_path.parent / "agent-cli-events.jsonl"

    def agent_readiness_source(agent, method):
        events_path = agent_cli_events_path()
        try:
            lines = events_path.read_text(encoding="utf-8").splitlines()
            for line in reversed(lines[-200:]):
                event = json.loads(line)
                if (
                    event.get("event") == "agent_readiness_probe_succeeded"
                    and event.get("agent") == agent
                    and event.get("method") == method
                ):
                    return f"agent-cli:{agent}-auth-status"
        except Exception:
            pass
        try:
            state = json.loads(agent_cli_state_path().read_text(encoding="utf-8"))
            if state.get("phase") == "complete" and state.get("selectedAgent") == agent:
                return f"agent-cli:{agent}-complete"
        except Exception:
            pass
        return ""

    def codex_agent_readiness_source():
        return agent_readiness_source("codex", "codex login status")

    def claude_agent_readiness_source():
        return agent_readiness_source("claude", "claude auth status --json")

    def codex_cli_auth_path():
        codex_home = os.environ.get("CODEX_HOME", "").strip()
        if not codex_home:
            codex_home = str(home / ".codex")
        return Path(codex_home).expanduser() / "auth.json"

    def hermes_auth_path():
        hermes_home = os.environ.get("HERMES_HOME", "").strip()
        if not hermes_home:
            hermes_home = str(home / ".hermes")
        return Path(hermes_home).expanduser() / "auth.json"

    @contextlib.contextmanager
    def hermes_auth_store_lock():
        lock_path = hermes_auth_path().with_suffix(".lock")
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a+", encoding="utf-8") as lock_file:
            if fcntl is not None:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                if fcntl is not None:
                    try:
                        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                    except OSError:
                        pass

    def claude_code_credential_source():
        if sys.platform == "darwin" and os.environ.get("ZEBRA_GBRAIN_RUNTIME_SKIP_CLAUDE_KEYCHAIN") != "1":
            result = run_process([
                "security",
                "find-generic-password",
                "-s",
                "Claude Code-credentials",
                "-w",
            ], timeout=5)
            if result["ok"] and result["stdout"]:
                try:
                    payload = json.loads(result["stdout"])
                    oauth = payload.get("claudeAiOauth") if isinstance(payload, dict) else None
                    if isinstance(oauth, dict) and oauth.get("accessToken"):
                        return "claude-code-keychain"
                except Exception:
                    pass
        credentials_path = home / ".claude" / ".credentials.json"
        try:
            payload = json.loads(credentials_path.read_text(encoding="utf-8"))
            oauth = payload.get("claudeAiOauth") if isinstance(payload, dict) else None
            if isinstance(oauth, dict) and oauth.get("accessToken"):
                return "claude-code-credentials-file"
        except Exception:
            pass
        return ""

    def read_codex_cli_tokens():
        try:
            payload = json.loads(codex_cli_auth_path().read_text(encoding="utf-8"))
            tokens = payload.get("tokens") if isinstance(payload, dict) else None
            if not isinstance(tokens, dict):
                return {}
            access_token = tokens.get("access_token")
            refresh_token = tokens.get("refresh_token")
            if not isinstance(access_token, str) or not access_token.strip():
                return {}
            if not isinstance(refresh_token, str) or not refresh_token.strip():
                return {}
            return dict(tokens)
        except Exception:
            return {}

    def import_codex_cli_tokens_to_hermes():
        tokens = read_codex_cli_tokens()
        if not tokens:
            return {"ok": False, "code": 1, "stdout": "", "stderr": "codex_cli_credentials_unreadable"}
        auth_path = hermes_auth_path()
        try:
            with hermes_auth_store_lock():
                auth_path.parent.mkdir(parents=True, exist_ok=True)
                try:
                    if auth_path.exists():
                        store = json.loads(auth_path.read_text(encoding="utf-8"))
                        if not isinstance(store, dict):
                            store = {}
                    else:
                        store = {}
                except Exception as exc:
                    return {"ok": False, "code": 1, "stdout": "", "stderr": f"hermes_auth_read_failed: {exc}"}
                timestamp = now()
                providers = store.setdefault("providers", {})
                if not isinstance(providers, dict):
                    providers = {}
                    store["providers"] = providers
                providers["openai-codex"] = {
                    "tokens": tokens,
                    "last_refresh": timestamp,
                    "auth_mode": "chatgpt",
                    "label": "Zebra Codex CLI import",
                }
                pool = store.setdefault("credential_pool", {})
                if not isinstance(pool, dict):
                    pool = {}
                    store["credential_pool"] = pool
                existing_entries = pool.get("openai-codex")
                entries = existing_entries if isinstance(existing_entries, list) else []
                next_entry = {
                    "id": "zebra-codex",
                    "label": "Zebra Codex CLI import",
                    "auth_type": "oauth",
                    "priority": 0,
                    "source": "device_code",
                    "access_token": tokens["access_token"],
                    "refresh_token": tokens.get("refresh_token"),
                    "base_url": "https://chatgpt.com/backend-api/codex",
                    "last_refresh": timestamp,
                    "last_status": None,
                    "last_status_at": None,
                    "last_error_code": None,
                    "last_error_reason": None,
                    "last_error_message": None,
                    "last_error_reset_at": None,
                }
                replaced = False
                for index, entry in enumerate(entries):
                    if isinstance(entry, dict) and entry.get("source") == "device_code":
                        entries[index] = next_entry
                        replaced = True
                        break
                if not replaced:
                    entries.insert(0, next_entry)
                pool["openai-codex"] = entries
                store["active_provider"] = "openai-codex"
                store["version"] = store.get("version") or 1
                store["updated_at"] = timestamp
                tmp = auth_path.with_name(f".{auth_path.name}.zebra-tmp")
                try:
                    fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                    with os.fdopen(fd, "w", encoding="utf-8") as handle:
                        json.dump(store, handle, indent=2, sort_keys=True)
                        handle.write("\\n")
                        handle.flush()
                        os.fsync(handle.fileno())
                    os.replace(tmp, auth_path)
                    os.chmod(auth_path, 0o600)
                    return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
                except Exception as exc:
                    try:
                        if tmp.exists():
                            tmp.unlink()
                    except Exception:
                        pass
                    return {"ok": False, "code": 1, "stdout": "", "stderr": f"hermes_auth_write_failed: {exc}"}
        except Exception as exc:
            return {"ok": False, "code": 1, "stdout": "", "stderr": f"hermes_auth_lock_failed: {exc}"}

    def write_env_file_value(path, key, value):
        if not key or not (key[0].isalpha() or key[0] == "_") or not all(ch.isalnum() or ch == "_" for ch in key):
            return {"ok": False, "code": 1, "stdout": "", "stderr": f"invalid_env_key: {key}"}
        sanitized_value = value.replace("\\n", "").replace("\\r", "")
        env_path = Path(path)
        env_path.parent.mkdir(parents=True, exist_ok=True)
        lines = []
        try:
            if env_path.exists():
                lines = env_path.read_text(encoding="utf-8-sig", errors="replace").splitlines(keepends=True)
        except Exception as exc:
            return {"ok": False, "code": 1, "stdout": "", "stderr": f"env_read_failed: {exc}"}
        found = False
        prefix = f"{key}="
        for index, line in enumerate(lines):
            if line.strip().startswith(prefix):
                lines[index] = f"{key}={sanitized_value}\\n"
                found = True
                break
        if not found:
            if lines and not lines[-1].endswith("\\n"):
                lines[-1] += "\\n"
            lines.append(f"{key}={sanitized_value}\\n")
        tmp = env_path.with_name(f".{env_path.name}.zebra-tmp")
        try:
            fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.writelines(lines)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp, env_path)
            os.chmod(env_path, 0o600)
            os.environ[key] = sanitized_value
            return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
        except Exception as exc:
            try:
                if tmp.exists():
                    tmp.unlink()
            except Exception:
                pass
            return {"ok": False, "code": 1, "stdout": "", "stderr": f"env_write_failed: {exc}"}

    def provider_id_for_runtime(provider, runtime):
        if runtime == "hermes":
            return provider["hermes_provider"]
        return provider["openclaw_provider"]

    def load_json_object(text):
        try:
            return json.loads(text)
        except Exception:
            pass
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            return json.loads(text[start:end + 1])
        raise ValueError("json_output_missing")

    def path_writable_or_creatable(path):
        candidate = Path(path).expanduser()
        current = candidate
        while not current.exists():
            parent = current.parent
            if parent == current:
                return False
            current = parent
        return os.access(str(current), os.W_OK | os.X_OK)

    def npm_environment():
        env = os.environ.copy()
        env["HOME"] = str(home)
        return env

    def npm_global_prefix():
        result = run_process(["npm", "config", "get", "prefix"], env=npm_environment(), timeout=30)
        if not result["ok"]:
            return "", result
        lines = [line.strip() for line in result.get("stdout", "").splitlines() if line.strip()]
        prefix = lines[-1] if lines else ""
        if prefix in {"undefined", "null"}:
            prefix = ""
        return prefix, result

    def npm_prefix_supports_global_install(prefix):
        if not prefix:
            return False
        expanded = Path(prefix).expanduser()
        return (
            path_writable_or_creatable(expanded / "bin") and
            path_writable_or_creatable(expanded / "lib" / "node_modules")
        )

    def configure_user_npm_global_prefix():
        local_prefix = home / ".local"
        (local_prefix / "bin").mkdir(parents=True, exist_ok=True)
        (local_prefix / "lib" / "node_modules").mkdir(parents=True, exist_ok=True)
        prepend_path_once(str(local_prefix / "bin"))
        result = run_process(
            ["npm", "config", "set", "prefix", str(local_prefix)],
            env=npm_environment(),
            timeout=60,
        )
        record_attempt(
            "install-runtime:openclaw:npm-prefix",
            f"npm config set prefix {local_prefix}",
            result,
            recoverable=True,
            blocking_reason="" if result["ok"] else "npm_prefix_config_failed",
        )
        return result

    def install_openclaw_runtime():
        prefix, prefix_result = npm_global_prefix()
        if not prefix_result["ok"]:
            return prefix_result
        if not npm_prefix_supports_global_install(prefix):
            prefix_result = configure_user_npm_global_prefix()
            if not prefix_result["ok"]:
                return prefix_result
        prepend_path_once(str(home / ".local" / "bin"))
        return run_process(["npm", "install", "-g", "openclaw"], env=npm_environment(), timeout=900)

    def install_runtime(runtime):
        if runtime == "openclaw":
            print(message(
                "Installing OpenClaw CLI with npm...",
                "npm으로 OpenClaw CLI를 설치합니다...",
                "npmでOpenClaw CLIをインストールします...",
            ))
            return install_openclaw_runtime()
        print(message(
            "Installing Hermes CLI with the installer in minimal mode...",
            "installer로 Hermes CLI를 최소 모드로 설치합니다...",
            "installerでHermes CLIを最小モードでインストールします...",
        ))
        script = "set -o pipefail; curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup --skip-browser --no-skills --non-interactive"
        env = os.environ.copy()
        env["PATH"] = os.pathsep.join([
            str(home / ".local" / "bin"),
            str(home / ".hermes" / "bin"),
            env.get("PATH", ""),
        ])
        return run_process(["/bin/bash", "-lc", script], env=env, timeout=1200)

    def runtime_display_name(runtime):
        return "OpenClaw" if runtime == "openclaw" else "Hermes"

    def credential_for(provider, runtime):
        if provider.get("auth_type") == "oauth":
            source = ""
            if provider.get("id") == "openai-codex":
                source = codex_agent_readiness_source()
            elif provider.get("id") == "anthropic-claude-code":
                source = claude_agent_readiness_source() or claude_code_credential_source()
            return {
                "value": "",
                "source": source or f"{provider['id']}:oauth",
                "envName": "",
                "persistEnvName": "",
            }
        env_name = provider.get("env", "")
        if runtime == "hermes":
            for candidate_env_name in hermes_credential_env_names(provider):
                if os.environ.get(candidate_env_name):
                    return {
                        "value": os.environ[candidate_env_name],
                        "source": f"env:{candidate_env_name}",
                        "envName": candidate_env_name,
                        "persistEnvName": candidate_env_name,
                    }
            hermes_env = read_env_file_vars(hermes_paths()["env"])
            for candidate_env_name in hermes_credential_env_names(provider):
                if hermes_env.get(candidate_env_name):
                    return {
                        "value": hermes_env[candidate_env_name],
                        "source": f"hermes-env:{candidate_env_name}",
                        "envName": candidate_env_name,
                        "persistEnvName": "",
                    }
            if provider.get("hermes_provider") == "anthropic":
                claude_source = claude_code_credential_source()
                if claude_source:
                    return {
                        "value": "",
                        "source": claude_source,
                        "envName": "",
                        "persistEnvName": "",
                    }
            env_name = hermes_prompt_env_name(provider)
        elif os.environ.get(env_name):
            return {
                "value": os.environ[env_name],
                "source": f"env:{env_name}",
                "envName": env_name,
                "persistEnvName": "",
            }
        value = getpass.getpass(message(
            f"Enter {provider['label']} API key (input hidden): ",
            f"{provider['label']} API key 입력 (입력값 숨김): ",
            f"{provider['label']} API keyを入力（非表示）: ",
        )).strip()
        if not value:
            raise RuntimeError("api_key_missing")
        return {
            "value": value,
            "source": f"entered:{env_name}",
            "envName": env_name,
            "persistEnvName": env_name if runtime == "hermes" else "",
        }

    def run_hermes_oauth_setup(exe, provider, credential):
        if provider.get("id") != "openai-codex":
            return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
        env = credential_env(provider, credential)
        def codex_status():
            result = run_process([exe, "auth", "status", "openai-codex"], env=env, timeout=30)
            text = (result.get("stdout", "") + "\\n" + result.get("stderr", "")).lower()
            lines = [line.strip() for line in text.splitlines()]
            return result, "openai-codex: logged in" in lines
        status, logged_in = codex_status()
        if status["ok"] and logged_in:
            return status
        if codex_agent_readiness_source() and codex_cli_auth_path().is_file():
            imported = import_codex_cli_tokens_to_hermes()
            if not imported["ok"]:
                return imported
            verified, logged_in = codex_status()
            if verified["ok"] and logged_in:
                return verified
            return {
                "ok": False,
                "code": verified.get("code", 1),
                "stdout": verified.get("stdout", ""),
                "stderr": verified.get("stderr", "") or "openai_codex_import_not_verified",
            }
        if not has_interactive_tty():
            return interactive_auth_required_result("hermes", provider, "hermes_openai_codex_auth_requires_tty")
        print(message(
            "OpenAI account login is required for Hermes. Continue the Hermes auth flow below.",
            "Hermes에서 OpenAI 계정 연동이 필요합니다. 아래 Hermes 인증 절차를 계속 진행하세요.",
            "HermesでOpenAIアカウント連携が必要です。以下のHermes認証手順を続けてください。",
        ))
        interactive = run_interactive_process([exe, "auth", "add", "openai-codex"], env=env, timeout=900)
        if not interactive["ok"]:
            return interactive
        verified, logged_in = codex_status()
        if verified["ok"] and logged_in:
            return verified
        return {
            "ok": False,
            "code": verified.get("code", 1),
            "stdout": verified.get("stdout", ""),
            "stderr": verified.get("stderr", "") or "openai_codex_auth_not_verified",
        }

    def run_hermes_config(exe, provider, credential):
        env = credential_env(provider, credential)
        if provider.get("auth_type") == "oauth":
            auth_result = run_hermes_oauth_setup(exe, provider, credential)
            if not auth_result["ok"]:
                return auth_result
        persist_env_name = credential.get("persistEnvName") or ""
        if persist_env_name and credential["value"]:
            result = write_env_file_value(hermes_paths()["env"], persist_env_name, credential["value"])
            if not result["ok"]:
                return result
        for key, value in [
            ("model.provider", provider_id_for_runtime(provider, "hermes")),
            ("model.default", provider["hermes_model"]),
            ("model.base_url", provider["hermes_base_url"]),
            ("model.api_mode", provider["hermes_api_mode"]),
        ]:
            result = run_process([exe, "config", "set", key, value], env=env, timeout=60)
            if not result["ok"]:
                return result
        return {"ok": True, "code": 0, "stdout": "", "stderr": ""}

    def openclaw_help_flags(exe):
        result = run_process([exe, "onboard", "--help"], timeout=20)
        text = result["stdout"] + "\\n" + result["stderr"]
        return {flag for flag in [
            "--skip-daemon",
            "--skip-ui",
            "--skip-skills",
            "--skip-health",
            "--skip-bootstrap",
            "--skip-channels",
            "--skip-search",
        ] if flag in text}

    def claude_cli_auth_status(env):
        result = run_process(["claude", "auth", "status", "--json"], env=env, timeout=30)
        if not result["ok"]:
            return result, False
        try:
            payload = load_json_object(result["stdout"] + "\\n" + result["stderr"])
            return result, bool(payload.get("loggedIn"))
        except Exception:
            return result, False

    def openclaw_auth_route_matches(route, provider_id):
        values = {
            str(route.get("provider") or ""),
            str(route.get("runtime") or ""),
            str(route.get("authProvider") or ""),
        }
        if provider_id == "claude-cli":
            return "claude-cli" in values or ("anthropic" in values and str(route.get("runtime") or "") == "claude-cli")
        return provider_id in values

    def openclaw_openai_oauth_env_fallback_keys():
        return ["CODEX_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENAI_ORG_ID", "OPENAI_ORGANIZATION"]

    def openclaw_env(provider, credential):
        env = credential_env(provider, credential)
        if provider.get("id") == "openai-codex":
            for key in openclaw_openai_oauth_env_fallback_keys():
                env.pop(key, None)
        return env

    def openclaw_oauth_profile_present(payload, provider_id):
        if provider_id != "openai":
            return True
        auth = payload.get("auth") or {}
        oauth = auth.get("oauth") or {}
        for profile in oauth.get("profiles") or []:
            if profile.get("provider") == "openai" and profile.get("status") not in {"missing", "expired"}:
                return True
        for provider in oauth.get("providers") or []:
            if provider.get("provider") == "openai" and provider.get("status") not in {"missing", "expired"}:
                return True
        for label in auth.get("providersWithOAuth") or []:
            if str(label).startswith("openai "):
                return True
        return False

    def openclaw_auth_profile_usable(exe, provider_id, credential):
        env = credential_env_by_provider_id(provider_id, credential)
        if provider_id == "openai":
            for key in openclaw_openai_oauth_env_fallback_keys():
                env.pop(key, None)
        result = run_process(
            [
                exe,
                "models",
                "status",
                "--json",
                "--probe-provider",
                provider_id,
            ],
            env=env,
            timeout=60,
        )
        if not result["ok"]:
            return False
        try:
            payload = load_json_object(result["stdout"] + "\\n" + result["stderr"])
            if not openclaw_oauth_profile_present(payload, provider_id):
                return False
            routes = ((payload.get("auth") or {}).get("runtimeAuthRoutes") or [])
            for route in routes:
                if openclaw_auth_route_matches(route, provider_id) and route.get("status") == "usable":
                    return True
        except Exception:
            return False
        return False

    def credential_env_by_provider_id(provider_id, credential):
        provider = next(
            (candidate for candidate in provider_choices if candidate["openclaw_provider"] == provider_id),
            None,
        )
        return credential_env(provider, credential) if provider else os.environ.copy()

    def run_openclaw_anthropic_cli_setup(exe, provider, credential):
        env = credential_env(provider, credential)
        provider_id = provider_id_for_runtime(provider, "openclaw")
        if openclaw_auth_profile_usable(exe, provider_id, credential):
            print(message(
                "Existing Claude CLI auth profile is already registered in OpenClaw. Continuing without another registration.",
                "OpenClaw에 기존 Claude CLI auth profile이 확인되어 재등록 없이 계속합니다.",
                "OpenClawに既存のClaude CLI auth profileが確認されたため、再登録せずに続行します。",
            ))
            return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
        status, logged_in = claude_cli_auth_status(env)
        if not logged_in:
            if not has_interactive_tty():
                return interactive_auth_required_result("openclaw", provider, "claude_cli_auth_login_requires_tty")
            print(message(
                "Claude CLI login is required. Continue the Claude login flow below.",
                "Claude CLI 로그인이 필요합니다. 아래 Claude 로그인 절차를 계속 진행하세요.",
                "Claude CLIログインが必要です。以下のClaudeログイン手順を続けてください。",
            ))
            login = run_interactive_process(["claude", "auth", "login"], env=env, timeout=900)
            if not login["ok"]:
                return login
            status, logged_in = claude_cli_auth_status(env)
            if not logged_in:
                return {
                    "ok": False,
                    "code": status.get("code", 1),
                    "stdout": status.get("stdout", ""),
                    "stderr": status.get("stderr", "") or "claude_cli_auth_not_verified",
                }
        print(message(
            "Registering Claude CLI auth profile in OpenClaw...",
            "OpenClaw에 Claude CLI auth profile을 등록합니다...",
            "OpenClawにClaude CLI auth profileを登録します...",
        ))
        if not has_interactive_tty():
            return interactive_auth_required_result("openclaw", provider, "openclaw_claude_cli_registration_requires_tty")
        return run_interactive_process_until(
            [exe, "models", "auth", "login", "--provider", "anthropic", "--method", "cli", "--set-default"],
            lambda: openclaw_auth_profile_usable(exe, provider_id, credential),
            env=env,
            timeout=900,
        )

    def run_openclaw_openai_codex_setup(exe, provider, credential):
        env = openclaw_env(provider, credential)
        provider_id = provider_id_for_runtime(provider, "openclaw")
        if openclaw_auth_profile_usable(exe, provider_id, credential):
            print(message(
                "Existing ChatGPT/Codex account login is already registered in OpenClaw. Continuing without another login.",
                "OpenClaw에 기존 ChatGPT/Codex 계정 연동이 확인되어 재로그인 없이 계속합니다.",
                "OpenClawに既存のChatGPT/Codexアカウント連携が確認されたため、再ログインせずに続行します。",
            ))
            return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
        print(message(
            "Registering ChatGPT/Codex account login in OpenClaw...",
            "OpenClaw에 ChatGPT/Codex 계정 연동을 등록합니다...",
            "OpenClawにChatGPT/Codexアカウント連携を登録します...",
        ))
        if not has_interactive_tty():
            return interactive_auth_required_result("openclaw", provider, "openclaw_openai_oauth_requires_tty")
        return run_interactive_process_until(
            [exe, "models", "auth", "login", "--provider", "openai", "--method", "oauth", "--set-default"],
            lambda: openclaw_auth_profile_usable(exe, provider_id, credential),
            env=env,
            timeout=900,
        )

    def run_openclaw_onboard(exe, provider, credential):
        env = credential_env(provider, credential)
        argv = [
            exe,
            "onboard",
            "--non-interactive",
            "--accept-risk",
            "--mode",
            "local",
            "--auth-choice",
            provider["openclaw_auth"],
            "--secret-input-mode",
            "ref",
        ]
        help_flags = openclaw_help_flags(exe)
        for flag in [
            "--skip-daemon",
            "--skip-ui",
            "--skip-skills",
            "--skip-health",
            "--skip-bootstrap",
            "--skip-channels",
            "--skip-search",
        ]:
            if flag in help_flags:
                argv.append(flag)
        result = run_process(argv, env=env, timeout=300)
        if result["ok"]:
            return result
        return result

    def run_openclaw_config(exe, provider, credential):
        if provider.get("id") == "anthropic-claude-code":
            return run_openclaw_anthropic_cli_setup(exe, provider, credential)
        if provider.get("id") == "openai-codex":
            return run_openclaw_openai_codex_setup(exe, provider, credential)
        return run_openclaw_onboard(exe, provider, credential)

    def verify_hermes_llm_call(exe, provider, credential):
        provider_id = provider_id_for_runtime(provider, "hermes")
        result = run_process(
            [
                exe,
                "chat",
                "-q",
                "Reply with OK. Do not use tools.",
                "--provider",
                provider_id,
                "--model",
                provider["hermes_model"],
                "--max-turns",
                "1",
                "--quiet",
                "--ignore-rules",
            ],
            env=credential_env(provider, credential),
            timeout=120,
        )
        if not result["ok"]:
            return result
        if not result["stdout"]:
            return {"ok": False, "code": 1, "stdout": result["stdout"], "stderr": "empty_llm_response"}
        if "ok" not in result["stdout"].lower():
            return {"ok": False, "code": 1, "stdout": result["stdout"], "stderr": "unexpected_llm_response"}
        return result

    def verify_openclaw_llm_call(exe, provider, credential):
        provider_id = provider_id_for_runtime(provider, "openclaw")
        result = run_process(
            [
                exe,
                "models",
                "status",
                "--json",
                "--probe",
                "--probe-provider",
                provider_id,
                "--probe-timeout",
                "15000",
                "--probe-concurrency",
                "1",
                "--probe-max-tokens",
                "4",
            ],
            env=openclaw_env(provider, credential),
            timeout=180,
        )
        if not result["ok"]:
            return result
        try:
            payload = load_json_object(result["stdout"])
            probes = (((payload.get("auth") or {}).get("probes") or {}).get("results") or [])
            for probe in probes:
                if probe.get("provider") == provider_id and probe.get("status") == "ok":
                    return result
            statuses = ", ".join(
                f"{probe.get('provider', '?')}:{probe.get('status', '?')}"
                for probe in probes
            )
            return {
                "ok": False,
                "code": 1,
                "stdout": result["stdout"],
                "stderr": f"no_ok_llm_probe_for_{provider_id}" + (f" ({statuses})" if statuses else ""),
            }
        except Exception as exc:
            return {"ok": False, "code": 1, "stdout": result["stdout"], "stderr": f"probe_json_parse_failed: {exc}"}

    def verify_llm_call(runtime, executable, provider, credential):
        print()
        print(message(
            "Checking that the selected tool can call the LLM...",
            "선택한 실행 도구가 LLM을 호출할 수 있는지 확인합니다...",
            "選択した実行ツールがLLMを呼び出せるか確認します...",
        ))
        if runtime == "hermes":
            result = verify_hermes_llm_call(executable["path"], provider, credential)
        else:
            result = verify_openclaw_llm_call(executable["path"], provider, credential)
        if not result["ok"]:
            print_command_failure(result, credential)
            raise RuntimeError("llm_call_verification_failed")
        print(message(
            "LLM call verified.",
            "LLM 호출 가능 상태를 확인했습니다.",
            "LLM呼び出し可能な状態を確認しました。",
        ))
        return result

    def write_receipt(runtime, executable, provider, credential, command_result, verification_result):
        config_paths = hermes_paths() if runtime == "hermes" else openclaw_paths()
        state = load_state()
        state["schemaVersion"] = 1
        state["receipt"] = {
            "complete": True,
            "runtime": runtime,
            "executablePath": executable["path"],
            "version": executable["version"],
            "provider": provider["id"],
            "runtimeProvider": provider_id_for_runtime(provider, runtime),
            "runtimeModel": provider.get("hermes_model") if runtime == "hermes" else "",
            "keySource": credential["source"],
            "keyEnvName": credential.get("envName") or "",
            "keyPersistedEnvName": credential.get("persistEnvName") or "",
            "configPaths": config_paths,
            "verifiedAt": now(),
            "checks": {
                "executable": True,
                "credentials": True,
                "runtimeConfigCommand": bool(command_result.get("ok")),
                "llmCall": bool(verification_result.get("ok")),
            },
            "reasons": [],
        }
        save_state(state)
        print()
        runtime_name = runtime_display_name(runtime)
        print(message(
            "OpenClaw/Hermes execution setup is complete.",
            "OpenClaw/Hermes 실행 준비가 완료되었습니다.",
            "OpenClaw/Hermesの実行準備が完了しました。",
        ))
        print(message(
            f"Selected execution tool: {runtime_name}",
            f"선택한 실행 도구: {runtime_name}",
            f"選択した実行ツール: {runtime_name}",
        ))
        print()
        print(message(
            "Return to Zebra onboarding and continue with gbrain installation.",
            "Zebra 온보딩으로 돌아가 gbrain 설치를 계속하세요.",
            "Zebraオンボーディングに戻ってgbrainのインストールを続けてください。",
        ))

    def print_provider_selection_notice(runtime, provider):
        print()
        if runtime == "hermes":
            if provider.get("id") == "anthropic-claude-code":
                print(message(
                    "Hermes condition: Max + extra credits required.",
                    "Hermes 조건: Max + extra credits 필요.",
                    "Hermes条件: Max + extra credits 必須。",
                ))
            elif provider.get("id") == "openai-codex":
                print(message(
                    "Hermes will use OpenAI Codex account login.",
                    "Hermes에 OpenAI Codex 계정 연동을 설정합니다.",
                    "HermesにOpenAI Codexアカウント連携を設定します。",
                ))
            else:
                print(message(
                    f"Hermes will use {provider['label']}.",
                    f"Hermes에 {provider['label']} 연결 정보를 설정합니다.",
                    f"Hermesに{provider['label']}の接続情報を設定します。",
                ))
            return
        if provider.get("id") == "anthropic-claude-code":
            print(message(
                "OpenClaw condition: Claude CLI login required.",
                "OpenClaw 조건: Claude CLI 로그인 필요.",
                "OpenClaw条件: Claude CLIログイン必須。",
            ))
        elif provider.get("id") == "openai-codex":
            print(message(
                "OpenClaw will register ChatGPT/Codex account login.",
                "OpenClaw에 ChatGPT/Codex 계정 연동을 등록합니다.",
                "OpenClawにChatGPT/Codexアカウント連携を登録します。",
            ))
        else:
            print(message(
                f"OpenClaw will use {provider['label']}.",
                f"OpenClaw에 {provider['label']} 연결 정보를 설정합니다.",
                f"OpenClawに{provider['label']}の接続情報を設定します。",
            ))

    def recover_prerequisite(name):
        if name == "clt":
            result = run_process(["xcode-select", "--install"], timeout=30)
            blocking = "clt_install_required"
            record_attempt("recover-prerequisite:clt", "xcode-select --install", result, recoverable=True, blocking_reason=blocking)
            state = load_state()
            progress = state.setdefault("progress", {})
            progress["waitingForUser"] = {
                "section": "Recover common prerequisites",
                "note": "Complete the macOS Command Line Tools installer, then rerun preflight.",
                "createdAt": now(),
            }
            save_state(state)
            print(json.dumps({"ok": result["ok"], "blockingReason": blocking, "result": redacted_result(result)}, indent=2, sort_keys=True))
            return
        if name == "bun":
            script = "set -o pipefail; curl -fsSL https://bun.sh/install | bash"
            result = run_process(["/bin/bash", "-lc", script], timeout=1200)
            record_attempt("recover-prerequisite:bun", script, result, recoverable=True, blocking_reason="" if result["ok"] else "bun_install_failed")
            if result["ok"]:
                prepend_path_once(str(home / ".bun" / "bin"))
            preflight = write_preflight()
            print(json.dumps({"ok": result["ok"], "result": redacted_result(result), "preflight": preflight}, indent=2, sort_keys=True))
            if not result["ok"]:
                raise RuntimeError("bun_install_failed")
            return
        if name == "node":
            result = recover_node_with_official_pkg()
            print(json.dumps(result, indent=2, sort_keys=True))
            if result.get("requiresUserAction"):
                return
            if not result.get("ok"):
                raise RuntimeError(result.get("blockingReason") or "node_install_required")
            return
        raise RuntimeError(f"unsupported_prerequisite:{name}")

    def recover_node_with_official_pkg():
        node_pkg_url = os.environ.get("ZEBRA_NODE_PKG_URL", "").strip()
        download_dir = state_path.parent / "downloads"
        download_dir.mkdir(parents=True, exist_ok=True)
        if not node_pkg_url:
            try:
                with urllib.request.urlopen("https://nodejs.org/dist/index.json", timeout=30) as response:
                    releases = json.loads(response.read().decode("utf-8"))
                release = next((item for item in releases if item.get("lts")), None)
                version = release.get("version") if isinstance(release, dict) else ""
                if not version:
                    raise RuntimeError("node_lts_release_missing")
                node_pkg_url = f"https://nodejs.org/dist/{version}/node-{version}.pkg"
            except Exception as exc:
                result = {"ok": False, "code": 1, "stdout": "", "stderr": f"node_index_fetch_failed: {exc}"}
                record_attempt("recover-prerequisite:node", "fetch https://nodejs.org/dist/index.json", result, recoverable=True, blocking_reason="node_index_fetch_failed")
                return {"ok": False, "blockingReason": "node_index_fetch_failed", "result": redacted_result(result)}
        pkg_path = download_dir / "node.pkg"
        result = run_process(["curl", "-fL", node_pkg_url, "-o", str(pkg_path)], timeout=1200)
        if not result["ok"]:
            record_attempt("recover-prerequisite:node", f"curl -fL {node_pkg_url} -o {pkg_path}", result, recoverable=True, blocking_reason="node_pkg_download_failed")
            return {"ok": False, "blockingReason": "node_pkg_download_failed", "result": redacted_result(result)}
        open_result = run_process(["open", str(pkg_path)], timeout=30)
        if not open_result["ok"]:
            record_attempt("recover-prerequisite:node", f"open {pkg_path}", open_result, recoverable=True, blocking_reason="node_pkg_open_failed")
            return {
                "ok": False,
                "requiresUserAction": False,
                "blockingReason": "node_pkg_open_failed",
                "pkgPath": str(pkg_path),
                "result": redacted_result(open_result),
            }
        record_attempt("recover-prerequisite:node", f"open {pkg_path}", open_result, recoverable=True, blocking_reason="node_pkg_install_required")
        state = load_state()
        progress = state.setdefault("progress", {})
        progress["waitingForUser"] = {
            "section": "Recover selected-runtime prerequisites",
            "note": "Complete the official Node.js pkg installer, then rerun preflight.",
            "createdAt": now(),
        }
        save_state(state)
        return {
            "ok": False,
            "requiresUserAction": True,
            "blockingReason": "node_pkg_install_required",
            "pkgPath": str(pkg_path),
            "result": redacted_result(open_result),
        }

    def install_runtime_command(runtime):
        before = detect_runtime(runtime)
        state = load_state()
        state["schemaVersion"] = 1
        selection = state.setdefault("selection", {})
        selection["selectedRuntime"] = runtime
        selection["updatedAt"] = now()
        save_state(state)
        if before.get("installed"):
            print(json.dumps({"ok": True, "runtime": runtime, "detection": before, "installedAlready": True}, indent=2, sort_keys=True))
            return
        result = install_runtime(runtime)
        record_attempt(f"install-runtime:{runtime}", "npm install -g openclaw" if runtime == "openclaw" else "hermes minimal installer", result, recoverable=True, blocking_reason="" if result["ok"] else f"{runtime}_install_failed")
        after = detect_runtime(runtime)
        output = {"ok": bool(result["ok"] and after.get("installed")), "runtime": runtime, "result": redacted_result(result), "detection": after}
        print(json.dumps(output, indent=2, sort_keys=True))
        if not output["ok"]:
            raise RuntimeError(f"{runtime}_install_failed")

    def configure_runtime_command(runtime, provider_id):
        executable = executable_for_runtime(runtime)
        provider_id = normalize_provider_id(provider_id)
        provider = provider_by_id(provider_id)
        credential = credential_for(provider, runtime)
        completed_state = completed_runtime_config_state(runtime, provider)
        if completed_state:
            print(json.dumps({
                "ok": True,
                "selection": completed_state.get("selection"),
                "runtimeConfig": completed_state.get("runtimeConfig"),
                "interactiveAuth": completed_state.get("interactiveAuth"),
                "reusedCompletedInteractiveAuth": True,
                "nextRecommendedCommand": next_recommended_command(completed_state),
            }, indent=2, sort_keys=True))
            return
        print_provider_selection_notice(runtime, provider)
        if runtime == "hermes":
            command_result = run_hermes_config(executable["path"], provider, credential)
        else:
            command_result = run_openclaw_config(executable["path"], provider, credential)
        if command_result.get("requiresInteractiveAuth"):
            state = write_interactive_auth_request(runtime, provider, credential, command_result)
            print(json.dumps({
                "ok": False,
                "requiresInteractiveAuth": True,
                "blockingReason": "interactive_auth_required",
                "interactiveAuth": state.get("interactiveAuth"),
                "selection": state.get("selection"),
                "runtimeConfig": state.get("runtimeConfig"),
                "nextRecommendedCommand": next_recommended_command(state),
            }, indent=2, sort_keys=True))
            return
        state = load_state()
        state["schemaVersion"] = 1
        state["selection"] = {
            "selectedRuntime": runtime,
            "selectedProvider": provider_id,
            "runtimeProvider": provider_id_for_runtime(provider, runtime),
            "runtimeModel": provider.get("hermes_model") if runtime == "hermes" else "",
            "credential": non_secret_credential(credential),
            "updatedAt": now(),
        }
        state["runtimeConfig"] = {
            "configuredAt": now(),
            "result": redacted_result(command_result, credential),
        }
        state.pop("interactiveAuth", None)
        if not command_result["ok"]:
            state["receipt"] = {
                "complete": False,
                "verifiedAt": now(),
                "reasons": [f"{runtime}_config_failed"],
            }
        save_state(state)
        if not command_result["ok"]:
            print_command_failure(command_result, credential)
            raise RuntimeError(f"{runtime}_config_failed")
        print(json.dumps({
            "ok": True,
            "selection": state["selection"],
            "runtimeConfig": state["runtimeConfig"],
            "nextRecommendedCommand": next_recommended_command(state),
        }, indent=2, sort_keys=True))

    def interactive_auth_command(runtime, provider_id):
        executable = executable_for_runtime(runtime)
        provider = provider_by_id(provider_id)
        credential = credential_for(provider, runtime)
        if not has_interactive_tty():
            result = interactive_auth_required_result(runtime, provider, "interactive_auth_command_requires_tty")
            state = write_interactive_auth_request(runtime, provider, credential, result)
            print(json.dumps({
                "ok": False,
                "requiresInteractiveAuth": True,
                "blockingReason": "interactive_auth_command_requires_tty",
                "interactiveAuth": state.get("interactiveAuth"),
            }, indent=2, sort_keys=True))
            raise RuntimeError("interactive_auth_command_requires_tty")

        state = load_state()
        state["schemaVersion"] = 1
        state["selection"] = {
            "selectedRuntime": runtime,
            "selectedProvider": provider_id,
            "runtimeProvider": provider_id_for_runtime(provider, runtime),
            "runtimeModel": provider.get("hermes_model") if runtime == "hermes" else "",
            "credential": non_secret_credential(credential),
            "updatedAt": now(),
        }
        state["interactiveAuth"] = {
            "status": "running",
            "runtime": runtime,
            "provider": provider_id,
            "runtimeProvider": provider_id_for_runtime(provider, runtime),
            "startedAt": now(),
        }
        save_state(state)

        print_provider_selection_notice(runtime, provider)
        if runtime == "hermes":
            command_result = run_hermes_config(executable["path"], provider, credential)
        else:
            command_result = run_openclaw_config(executable["path"], provider, credential)

        state = load_state()
        state["schemaVersion"] = 1
        state["runtimeConfig"] = {
            "configuredAt": now(),
            "result": redacted_result(command_result, credential),
        }
        if command_result["ok"]:
            state["interactiveAuth"] = {
                "status": "completed",
                "runtime": runtime,
                "provider": provider_id,
                "runtimeProvider": provider_id_for_runtime(provider, runtime),
                "completedAt": now(),
            }
            progress = state.setdefault("progress", {})
            if progress.get("waitingForUser", {}).get("section") == "Configure selected runtime":
                progress.pop("waitingForUser", None)
            progress.pop("lastFailure", None)
            state.pop("receipt", None)
            save_state(state)
            print(json.dumps({
                "ok": True,
                "interactiveAuth": state.get("interactiveAuth"),
                "selection": state.get("selection"),
                "runtimeConfig": state.get("runtimeConfig"),
                "nextRecommendedCommand": next_recommended_command(state),
            }, indent=2, sort_keys=True))
            return

        state["interactiveAuth"] = {
            "status": "failed",
            "runtime": runtime,
            "provider": provider_id,
            "runtimeProvider": provider_id_for_runtime(provider, runtime),
            "failedAt": now(),
            "result": redacted_result(command_result, credential),
        }
        state["receipt"] = {
            "complete": False,
            "verifiedAt": now(),
            "reasons": [f"{runtime}_config_failed"],
        }
        save_state(state)
        print_command_failure(command_result, credential)
        raise RuntimeError(f"{runtime}_config_failed")

    def selected_provider_for_runtime(runtime, flags):
        provider_id = normalize_provider_id(flags.get("provider", ""))
        if provider_id:
            return provider_by_id(provider_id)
        state = load_state()
        selection = state.get("selection") or {}
        if selection.get("selectedRuntime") and selection.get("selectedRuntime") != runtime:
            raise RuntimeError("selected_runtime_mismatch")
        provider_id = selection.get("selectedProvider", "")
        if not provider_id:
            raise RuntimeError("selected_provider_missing")
        return provider_by_id(provider_id)

    def verify_runtime_command(runtime, flags):
        executable = executable_for_runtime(runtime)
        provider = selected_provider_for_runtime(runtime, flags)
        credential = credential_for(provider, runtime)
        try:
            verification_result = verify_llm_call(runtime, executable, provider, credential)
        except Exception as exc:
            state = load_state()
            state["schemaVersion"] = 1
            state["runtimeVerification"] = {
                "verifiedAt": now(),
                "result": {"ok": False, "exitCode": 1, "stdoutTail": "", "stderrTail": str(exc)},
            }
            state["receipt"] = {
                "complete": False,
                "verifiedAt": now(),
                "reasons": [str(exc)],
            }
            save_state(state)
            raise
        state = load_state()
        state["schemaVersion"] = 1
        state["runtimeVerification"] = {
            "verifiedAt": now(),
            "result": redacted_result(verification_result, credential),
        }
        save_state(state)
        print(json.dumps({"ok": True, "runtimeVerification": state["runtimeVerification"]}, indent=2, sort_keys=True))

    def write_receipt_command():
        state = load_state()
        selection = state.get("selection") or {}
        runtime = selection.get("selectedRuntime", "")
        provider_id = selection.get("selectedProvider", "")
        if not runtime:
            raise RuntimeError("selected_runtime_missing")
        if not provider_id:
            raise RuntimeError("selected_provider_missing")
        provider = provider_by_id(provider_id)
        executable = executable_for_runtime(runtime)
        config_result = ((state.get("runtimeConfig") or {}).get("result") or {})
        verification_result = ((state.get("runtimeVerification") or {}).get("result") or {})
        if not config_result.get("ok"):
            raise RuntimeError("runtime_config_unverified")
        if not verification_result.get("ok"):
            raise RuntimeError("llm_call_unverified")
        credential = selection.get("credential") or {}
        write_receipt(runtime, executable, provider, credential, {"ok": True}, {"ok": True})

    def print_run_guidance():
        state = load_state()
        output = {
            "ok": True,
            "mode": "agent_orchestrated",
            "statePath": str(state_path),
            "documentPath": os.environ.get("ZEBRA_GBRAIN_RUNTIME_DOC", ""),
            "next": [
                "Read the Step 2 instruction document.",
                "Run zebra-gbrain-runtime-onboarding status --json.",
                "Run zebra-gbrain-runtime-onboarding preflight --json.",
                "Use report/preflight/recover/install/configure/verify/write-receipt commands; do not use an interactive run flow.",
            ],
            "progress": state.get("progress"),
            "selection": state.get("selection"),
            "interactiveAuth": state.get("interactiveAuth"),
            "receipt": state.get("receipt"),
            "nextRecommendedCommand": next_recommended_command(state),
        }
        print(json.dumps(output, indent=2, sort_keys=True))

    def print_status():
        state = load_state()
        output = {
            "statePath": str(state_path),
            "documentPath": os.environ.get("ZEBRA_GBRAIN_RUNTIME_DOC", ""),
            "detection": detect_all(),
            "preflight": state.get("preflight"),
            "progress": state.get("progress"),
            "selection": state.get("selection"),
            "interactiveAuth": state.get("interactiveAuth"),
            "runtimeConfig": state.get("runtimeConfig"),
            "runtimeVerification": state.get("runtimeVerification"),
            "receipt": state.get("receipt"),
            "nextRecommendedCommand": next_recommended_command(state),
        }
        print(json.dumps(output, indent=2, sort_keys=True))

    if command in {"run", ""}:
        print_run_guidance()
    elif command == "preflight":
        preflight = write_preflight()
        print(json.dumps({"statePath": str(state_path), "preflight": preflight}, indent=2, sort_keys=True))
    elif command == "report":
        try:
            report_progress(parse_flags(sys.argv[3:]))
        except Exception as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)
    elif command == "recover-prerequisite":
        try:
            target = sys.argv[3] if len(sys.argv) > 3 else ""
            recover_prerequisite(target)
        except Exception as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)
    elif command == "install-runtime":
        try:
            runtime = sys.argv[3] if len(sys.argv) > 3 else ""
            install_runtime_command(runtime)
        except Exception as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)
    elif command == "configure-runtime":
        try:
            runtime = sys.argv[3] if len(sys.argv) > 3 else ""
            flags = parse_flags(sys.argv[4:])
            provider_id = normalize_provider_id(flags.get("provider", ""))
            if not provider_id:
                raise RuntimeError("provider_missing")
            configure_runtime_command(runtime, provider_id)
        except KeyboardInterrupt:
            print("\\nCancelled.", file=sys.stderr)
            sys.exit(130)
        except Exception as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)
    elif command == "interactive-auth":
        try:
            runtime = sys.argv[3] if len(sys.argv) > 3 else ""
            flags = parse_flags(sys.argv[4:])
            provider_id = normalize_provider_id(flags.get("provider", ""))
            if not provider_id:
                raise RuntimeError("provider_missing")
            interactive_auth_command(runtime, provider_id)
        except KeyboardInterrupt:
            print("\\nCancelled.", file=sys.stderr)
            sys.exit(130)
        except Exception as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)
    elif command == "verify-runtime":
        try:
            runtime = sys.argv[3] if len(sys.argv) > 3 else ""
            flags = parse_flags(sys.argv[4:])
            verify_runtime_command(runtime, flags)
        except Exception as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)
    elif command == "write-receipt":
        try:
            write_receipt_command()
        except Exception as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)
    elif command in {"status", "detect"}:
        print_status()
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(2)
    PY
    """
}
