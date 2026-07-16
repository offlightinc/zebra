import Foundation

public enum SlackSourceOnboardingCLI {
    public struct Execution: Sendable {
        public let exitCode: Int32
        public let stdout: Data
    }

    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> Execution {
        let stateURL = URL(fileURLWithPath: environment["ZEBRA_SOURCE_ONBOARDING_STATE"]
            ?? ZebraSourceOnboardingState.defaultStateURL().path)
        let home = environment["ZEBRA_SOURCE_ONBOARDING_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let applicationSupport = home?.appendingPathComponent("Library/Application Support/zebra", isDirectory: true)
        let service = SlackSourceOnboardingService(stateURL: stateURL, applicationSupport: applicationSupport)
        return await run(arguments: arguments, service: service)
    }

    static func run(arguments: [String], service: SlackSourceOnboardingService) async -> Execution {
        let usage = result(reason: "invalid_arguments", retryable: false)
        guard let command = arguments.first else { return encode(usage, exitCode: 2) }

        switch command {
        case "connect":
            guard let token = value(after: "--slack-token", in: arguments),
                  let rawDate = value(after: "--start-date", in: arguments),
                  arguments.count == 5,
                  let startDate = parseDate(rawDate) else {
                return encode(usage, exitCode: 2)
            }
            let result = await service.run(credential: .token(token), startDate: startDate)
            return encode(result, exitCode: result.status == .checked ? 0 : 1)
        case "retry":
            guard arguments.count == 1 else { return encode(usage, exitCode: 2) }
            let result = await service.resumeFromState()
            return encode(result, exitCode: result.status == .checked ? 0 : 1)
        default:
            return encode(usage, exitCode: 2)
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func parseDate(_ raw: String) -> Date? {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { return nil }
        return date
    }

    private static func encode(_ result: SlackSourceOnboardingResult, exitCode: Int32) -> Execution {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var data = (try? encoder.encode(result)) ?? Data(#"{"ok":false,"reason":"encoding_failed","status":"attention"}"#.utf8)
        data.append(0x0A)
        return Execution(exitCode: exitCode, stdout: data)
    }

    private static func result(reason: String, retryable: Bool) -> SlackSourceOnboardingResult {
        .init(ok: false, sourceID: "slack", status: .attention, reason: reason, retryable: retryable,
              workspaceID: nil, authorizedUserID: nil, startDate: "", nextActiveSourceID: nil)
    }
}
