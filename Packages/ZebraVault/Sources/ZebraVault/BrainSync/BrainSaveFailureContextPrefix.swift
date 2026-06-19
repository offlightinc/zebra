import Foundation

public enum BrainSaveFailureContextPrefix {
    public static func build(
        vaultPath: String,
        failure: BrainSaveFailure,
        failedAt: Date?
    ) -> String {
        BrainFailureContextPrefixBuilder.build(
            BrainFailureContextPrefixRequest(
                title: "Zebra brain save failure",
                vaultPath: vaultPath,
                reason: failure.source.rawValue,
                rawReason: nil,
                detail: failure.message,
                failedAt: failedAt,
                guidance: guidance(for: failure.source),
                inspectCommands: inspectCommands(for: failure.source)
            )
        )
    }

    private static func guidance(for source: BrainSaveFailureSource) -> String {
        switch source {
        case .gbrainStatus:
            return """
            GBrain reported that save state is unhealthy. Inspect `gbrain status --json` first, then check active locks and failed/dead queue entries before changing files. Do not delete queue or lock state unless you have verified it is stale.
            """
        case .openClawCron:
            return """
            OpenClaw cron reported a GBrain save failure. Inspect the OpenClaw cron job status and recent output, then compare it with `gbrain status --json` so stale cron failures do not hide a newer successful save.
            """
        case .hermesCron:
            return """
            Hermes cron reported a GBrain save failure. Inspect the Hermes cron jobs file and recent GBrain status. Treat Hermes as the scheduler/runtime layer and avoid applying git-sync recovery steps unless GBrain status points to a repository problem.
            """
        case .missingCronJob:
            return """
            Zebra could not find a GBrain save cron job for the selected vault. Inspect the selected vault path and the configured runtime scheduler, then create or repair a job that runs `gbrain sync --repo <selected vault path> --yes` only after user approval for persistent background jobs.
            """
        case .unavailable:
            return """
            Zebra could not read GBrain save status. Verify whether GBrain is installed and configured before treating this as data loss or a failed save.
            """
        }
    }

    private static func inspectCommands(for source: BrainSaveFailureSource) -> [String] {
        var commands = [
            "gbrain status --json",
        ]
        switch source {
        case .gbrainStatus:
            commands.append("gbrain status --json | jq .")
            commands.append("find ~/.gbrain -maxdepth 3 -type f \\( -name '*lock*' -o -name '*queue*' \\) -print")
        case .openClawCron:
            commands.append("openclaw cron list --json")
            commands.append("openclaw cron list --json | jq '.jobs[]? | select((.name // .command // .description // \"\") | test(\"gbrain\"; \"i\"))'")
        case .hermesCron:
            commands.append("cat ~/.hermes/cron/jobs.json")
            commands.append("jq '.jobs[]? | select((.name // .command // .description // \"\") | test(\"gbrain\"; \"i\"))' ~/.hermes/cron/jobs.json")
        case .missingCronJob:
            commands.append("openclaw cron list --json")
            commands.append("cat ~/.hermes/cron/jobs.json")
        case .unavailable:
            commands.append("command -v gbrain")
            commands.append("gbrain --help")
        }
        return commands
    }
}
