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
            Zebra GBrain setup is starting. I am reading the current section prompt now. Please wait.
            """
        case .ja:
            return """
            Your first visible response must be a brief Japanese sentence telling the user that Zebra GBrain setup is starting, you are reading the current section prompt now, and they should wait. Preserve `Zebra GBrain setup` and `section prompt` exactly.
            """
        case .ko:
            return """
            Your first visible response must be a brief Korean sentence telling the user that Zebra GBrain setup is starting, you are reading the current section prompt now, and they should wait. Preserve `Zebra GBrain setup` and `section prompt` exactly.
            """
        }
    }

    var promptPolicy: String {
        """
        Language policy:
        Use Zebra's app language (\(displayName)) for user-facing prose. Preserve technical terms, domain terminology, product names, commands, identifiers, file paths, environment variables, API names, CLI flags, JSON keys, error codes, and quoted/source text in their original English spelling.
        """
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

    var clawvisorEmailConnectionSteps: String {
        switch self {
        case .en:
            return """
            1. Open https://app.clawvisor.com/login and sign up or sign in with Google.
            2. In Clawvisor, use the left sidebar to open Agents, choose GBrain, and click Create GBrain agent.
            3. Continue through Google service authorization and task approval.
            4. When Clawvisor reaches the final Env vars step, paste the three exported env lines into this terminal.
            """
        case .ja:
            return """
            1. https://app.clawvisor.com/login を開き、Googleでsign upまたはsign inしてください。
            2. Clawvisorで左sidebarのAgentsを開き、GBrainを選択してCreate GBrain agentをクリックしてください。
            3. Google service authorizationとtask approvalを続けて完了してください。
            4. 最後のEnv vars stepに到達したら、3行のexport env linesをこのターミナルに貼り付けてください。
            """
        case .ko:
            return """
            1. https://app.clawvisor.com/login 을 열고 Google로 sign up 또는 sign in 하세요.
            2. Clawvisor에서 왼쪽 sidebar의 Agents를 열고 GBrain을 선택한 뒤 Create GBrain agent를 클릭하세요.
            3. Google service authorization과 task approval을 이어서 진행하세요.
            4. 마지막 Env vars step에 도달하면 세 줄의 export env lines를 이 터미널에 그대로 붙여넣으세요.
            """
        }
    }
}
