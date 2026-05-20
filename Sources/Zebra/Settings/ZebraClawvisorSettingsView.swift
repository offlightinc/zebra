import SwiftUI
import ZebraVault

/// Clawvisor settings detail surface. Rendered inside cmux's Settings window
/// via the `\.settingsExtensionViewFactory` env, registered by
/// `ZebraServices`. Lives under `Sources/Zebra/Settings/` (not in the
/// `ZebraVault` SPM) so it can reuse cmux's internal `SettingsCard` /
/// `SettingsSectionHeader` / `SettingsCardDivider` components — same module
/// gives us internal-visibility access without exporting them publicly.
struct ZebraClawvisorSettingsView: View {
    private static let signupURL = URL(string: "https://app.clawvisor.com/login")!

    @State private var brainURL: String = ""
    @State private var agentToken: String = ""
    @State private var gmailTaskID: String = ""
    @State private var accountEmail: String = ""
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    private var canSave: Bool {
        !brainURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !agentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !gmailTaskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && saveState != .saving
    }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(
                    localized: "settings.clawvisor.intro",
                    defaultValue: "Zebra reads Gmail through a local SQLite cache that syncs with your Clawvisor brain. Paste the credentials from your Clawvisor dashboard below."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(String(
                        localized: "settings.clawvisor.signup.prefix",
                        defaultValue: "Don't have an account?"
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    Link(
                        String(
                            localized: "settings.clawvisor.signup.link",
                            defaultValue: "Sign up at app.clawvisor.com ↗"
                        ),
                        destination: Self.signupURL
                    )
                    .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsCardDivider()

            field(
                label: String(
                    localized: "settings.clawvisor.brainURL",
                    defaultValue: "Brain RPC URL"
                ),
                placeholder: "https://brain.example.com/rpc",
                text: $brainURL
            )

            SettingsCardDivider()

            field(
                label: String(
                    localized: "settings.clawvisor.agentToken",
                    defaultValue: "Agent token"
                ),
                placeholder: "clw_...",
                text: $agentToken,
                isSecure: true
            )

            SettingsCardDivider()

            field(
                label: String(
                    localized: "settings.clawvisor.gmailTaskID",
                    defaultValue: "Gmail task ID"
                ),
                placeholder: "task_...",
                text: $gmailTaskID
            )

            SettingsCardDivider()

            field(
                label: String(
                    localized: "settings.clawvisor.accountEmail",
                    defaultValue: "Gmail account (optional)"
                ),
                placeholder: "you@gmail.com",
                text: $accountEmail
            )

            SettingsCardDivider()

            HStack(spacing: 8) {
                statusLabel
                Spacer(minLength: 0)
                Button(action: { Task { await save() } }) {
                    Text(String(
                        localized: "settings.clawvisor.save",
                        defaultValue: "Save"
                    ))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear(perform: prefill)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch saveState {
        case .idle:
            EmptyView()
        case .saving:
            Text(String(
                localized: "settings.clawvisor.saving",
                defaultValue: "Saving…"
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        case .saved:
            Text(String(
                localized: "settings.clawvisor.saved",
                defaultValue: "Saved to ~/.gbrain/.env"
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func field(
        label: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
            .font(.system(size: 12).monospaced())
            .autocorrectionDisabled(true)
            .textContentType(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func prefill() {
        let env = readDotEnv()
        brainURL = env["CLAWVISOR_URL"] ?? ""
        agentToken = env["CLAWVISOR_AGENT_TOKEN"] ?? ""
        gmailTaskID = env["CLAWVISOR_GMAIL_TASK_ID"] ?? ""
        accountEmail = env["ZEBRA_CLAWVISOR_GMAIL_ACCOUNT"] ?? ""
    }

    private func readDotEnv() -> [String: String] {
        let homePath = NSHomeDirectory()
        guard !homePath.isEmpty else { return [:] }
        let url = URL(fileURLWithPath: homePath)
            .appendingPathComponent(".gbrain/.env")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text.hasPrefix("#") { continue }
            if text.hasPrefix("export ") {
                text = String(text.dropFirst("export ".count))
            }
            guard let equals = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(text[text.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    @MainActor
    private func save() async {
        saveState = .saving
        let updates: KeyValuePairs<String, String> = [
            "CLAWVISOR_URL": brainURL,
            "CLAWVISOR_AGENT_TOKEN": agentToken,
            "CLAWVISOR_GMAIL_TASK_ID": gmailTaskID,
            "ZEBRA_CLAWVISOR_GMAIL_ACCOUNT": accountEmail
        ]
        do {
            try ZebraClawvisorDotEnvWriter.update(updates)
            await ZebraClawvisorEmailClient.shared.invalidateConfig()
            saveState = .saved
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }
}
