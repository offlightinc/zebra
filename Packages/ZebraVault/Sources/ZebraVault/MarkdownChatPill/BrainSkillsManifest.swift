import Foundation

/// Lazily loads gbrain's `skills/manifest.json` so the chat-pill slash menu
/// can show real registered skills (`/ingest`, `/query`, `/maintain`, …)
/// instead of mockup placeholders.
///
/// Plan §A decision: we read the manifest directly off disk (one file
/// parse, near-zero cost) and surface a single "Brain Skills" section.
/// Project/global split from the mockup was abandoned — gbrain ships a
/// single registry.
enum BrainSkillsManifest {
    struct Skill: Equatable, Identifiable {
        let name: String
        let description: String
        var id: String { name }
    }

    /// Default engine location. GBrain setup records the user-confirmed
    /// source repo; `~/gbrain` remains only the fallback recommendation.
    private static var defaultManifestURL: URL {
        let sourceRepoURL: URL
        if let sourceRepoPath = ZebraGBrainOnboardingStore().activeSourceRepoPathFromCachedState() {
            sourceRepoURL = URL(fileURLWithPath: sourceRepoPath, isDirectory: true)
        } else {
            sourceRepoURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("gbrain", isDirectory: true)
        }
        return sourceRepoURL
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("manifest.json", isDirectory: false)
    }

    private struct ManifestFile: Decodable {
        let skills: [Entry]
        struct Entry: Decodable {
            let name: String
            let description: String?
        }
    }

    // Cached parse — gbrain's manifest changes only when the user updates
    // gbrain itself; reparsing on every keystroke is wasted IO. Both
    // success and failure are cached so a gbrain-less environment doesn't
    // hit disk again every time a new pill instance probes for skills.
    // (`.success(nil)` would be ambiguous, hence the dedicated enum.)
    private enum CachedResult {
        case skills([Skill])
        case unavailable
    }
    private static var cached: CachedResult?

    /// Returns all registered gbrain skills, or nil when the manifest can't
    /// be loaded (gbrain not installed, file missing, JSON malformed). nil
    /// is the signal for the pill to keep the slash menu disabled — we'd
    /// rather show nothing than a stale or invented skill list.
    static func skills() -> [Skill]? {
        if let cached {
            switch cached {
            case .skills(let list): return list
            case .unavailable: return nil
            }
        }
        guard let data = try? Data(contentsOf: defaultManifestURL),
              let manifest = try? JSONDecoder().decode(ManifestFile.self, from: data) else {
            cached = .unavailable
            return nil
        }
        let parsed = manifest.skills.compactMap { entry -> Skill? in
            let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            return Skill(
                name: trimmedName,
                description: entry.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        cached = .skills(parsed)
        return parsed
    }
}
