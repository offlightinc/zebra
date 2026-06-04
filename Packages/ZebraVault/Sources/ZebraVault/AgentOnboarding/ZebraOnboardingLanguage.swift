import Foundation

enum ZebraOnboardingLanguage: String, Equatable {
    case en
    case ja
    case ko

    static func current(
        appPreferredLocalizations: [String] = Bundle.main.preferredLocalizations,
        preferredLanguages: [String] = Locale.preferredLanguages,
        currentLocaleIdentifier: String = Locale.current.identifier
    ) -> ZebraOnboardingLanguage {
        for language in appPreferredLocalizations {
            if let resolved = resolve(language) {
                return resolved
            }
        }
        for language in preferredLanguages {
            if let resolved = resolve(language) {
                return resolved
            }
        }
        return resolve(currentLocaleIdentifier) ?? .en
    }

    static func resolve(_ raw: String?) -> ZebraOnboardingLanguage? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        guard !normalized.isEmpty else { return nil }
        if normalized == "ko" || normalized.hasPrefix("ko-") {
            return .ko
        }
        if normalized == "ja" || normalized.hasPrefix("ja-") {
            return .ja
        }
        if normalized == "en" || normalized.hasPrefix("en-") {
            return .en
        }
        return nil
    }

    var code: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .ja: return "Japanese"
        case .ko: return "Korean"
        }
    }

    var firstVisibleGBrainSetupInstruction: String {
        switch self {
        case .en:
            return """
            Your first visible response must be exactly:
            Zebra GBrain setup is starting. I am reading the setup packet now. Please wait.
            """
        case .ja:
            return """
            Your first visible response must be a brief Japanese sentence telling the user that Zebra GBrain setup is starting, you are reading the setup packet now, and they should wait. Preserve `Zebra GBrain setup` and `setup packet` exactly.
            """
        case .ko:
            return """
            Your first visible response must be a brief Korean sentence telling the user that Zebra GBrain setup is starting, you are reading the setup packet now, and they should wait. Preserve `Zebra GBrain setup` and `setup packet` exactly.
            """
        }
    }

    var promptPolicy: String {
        """
        Language policy:
        Use Zebra's app language (\(displayName)) for user-facing prose. Preserve technical terms, domain terminology, product names, commands, identifiers, file paths, environment variables, API names, CLI flags, JSON keys, error codes, and quoted/source text in their original English spelling.
        """
    }

    var embeddingProviderDecisionOptions: String {
        switch self {
        case .en:
            return """
            When an embedding provider decision is required, show only these two numbered options:
              1. provider key provided: set one of `OPENAI_API_KEY`, `ZEROENTROPY_API_KEY`, or `VOYAGE_API_KEY` in the environment, then continue.
              2. defer embeddings: initialize with `gbrain init --pglite --no-embedding` now; embeddings can be configured later.
            """
        case .ja:
            return """
            When an embedding provider decision is required, show only these two numbered options in Japanese. Preserve `provider key provided`, `defer embeddings`, `OPENAI_API_KEY`, `ZEROENTROPY_API_KEY`, `VOYAGE_API_KEY`, `environment`, `gbrain init --pglite --no-embedding`, and `embeddings` exactly:
              1. provider key provided: `OPENAI_API_KEY`, `ZEROENTROPY_API_KEY`, `VOYAGE_API_KEY`のいずれかをenvironmentに設定してから続行します。
              2. defer embeddings: 今すぐ`gbrain init --pglite --no-embedding`で初期化します。embeddingsは後で設定できます。
            """
        case .ko:
            return """
            When an embedding provider decision is required, show only these two numbered options in Korean. Preserve `provider key provided`, `defer embeddings`, `OPENAI_API_KEY`, `ZEROENTROPY_API_KEY`, `VOYAGE_API_KEY`, `environment`, `gbrain init --pglite --no-embedding`, and `embeddings` exactly:
              1. provider key provided: `OPENAI_API_KEY`, `ZEROENTROPY_API_KEY`, `VOYAGE_API_KEY` 중 하나를 environment에 설정한 뒤 계속합니다.
              2. defer embeddings: 지금 `gbrain init --pglite --no-embedding`으로 초기화합니다. embeddings는 나중에 설정할 수 있습니다.
            """
        }
    }

    var topologyDecisionPrompt: String {
        switch self {
        case .en:
            return "Ask only for the Step 3 topology decision now: local PGLite or Supabase/Postgres."
        case .ja:
            return "Step 3 topology decisionだけを日本語で聞いてください: local PGLite または Supabase/Postgres。"
        case .ko:
            return "Step 3 topology decision만 한국어로 물어보세요: local PGLite 또는 Supabase/Postgres."
        }
    }

    var topologyDecisionNote: String {
        switch self {
        case .en:
            return "Choose local PGLite or Supabase/Postgres."
        case .ja:
            return "local PGLite または Supabase/Postgresを選択してください。"
        case .ko:
            return "local PGLite 또는 Supabase/Postgres를 선택하세요."
        }
    }

    func brainRepoTargetOptions(recommendedPath: String) -> String {
        switch self {
        case .en:
            return """
            1. Create a new brain repo at \(recommendedPath) (recommended)
            2. Use an existing markdown/brain repo path that the user provides
            3. Create a new brain repo at a custom path
            """
        case .ja:
            return """
            1. \(recommendedPath)に新しいbrain repoを作成します (recommended)
            2. ユーザーが指定する既存のmarkdown/brain repo pathを使用します
            3. custom pathに新しいbrain repoを作成します
            """
        case .ko:
            return """
            1. \(recommendedPath)에 새 brain repo를 만듭니다 (recommended)
            2. 사용자가 제공하는 기존 markdown/brain repo path를 사용합니다
            3. custom path에 새 brain repo를 만듭니다
            """
        }
    }

    func brainRepoTargetFollowUp(recommendedPath: String) -> String {
        switch self {
        case .en:
            return "If the user chooses 1, ask for yes/no confirmation before creating \(recommendedPath). If the user chooses 2, ask for the full existing repo path. If the user chooses 3, ask for the full path to create."
        case .ja:
            return "ユーザーが1を選んだら、\(recommendedPath)を作成する前にyes/no confirmationを求めます。2を選んだら既存repoのfull pathを聞きます。3を選んだら作成するfull pathを聞きます。"
        case .ko:
            return "사용자가 1을 선택하면 \(recommendedPath)를 만들기 전에 yes/no confirmation을 요청합니다. 2를 선택하면 기존 repo의 full path를 묻습니다. 3을 선택하면 만들 full path를 묻습니다."
        }
    }

    var clawvisorFlowPresentationInstruction: String {
        switch self {
        case .en:
            return "When showing the 7-step flow to the user, keep the step titles and explanatory prose in English."
        case .ja:
            return "When showing the 7-step flow to the user, present user-facing step titles and explanatory prose in Japanese. Preserve product names, dashboard labels, commands, URLs, file paths, `user_id`, `/clawvisor-setup`, and quoted UI text exactly."
        case .ko:
            return "When showing the 7-step flow to the user, present user-facing step titles and explanatory prose in Korean. Preserve product names, dashboard labels, commands, URLs, file paths, `user_id`, `/clawvisor-setup`, and quoted UI text exactly."
        }
    }
}
