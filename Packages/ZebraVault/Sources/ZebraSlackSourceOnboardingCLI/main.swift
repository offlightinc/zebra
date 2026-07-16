import Darwin
import Foundation
import ZebraVault

let semaphore = DispatchSemaphore(value: 0)
var execution: SlackSourceOnboardingCLI.Execution?
Task {
    execution = await SlackSourceOnboardingCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
    semaphore.signal()
}
semaphore.wait()
guard let execution else { exit(1) }
FileHandle.standardOutput.write(execution.stdout)
exit(execution.exitCode)
