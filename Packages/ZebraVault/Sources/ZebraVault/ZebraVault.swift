/// ZebraVault is the local Swift package that owns the Zebra layer of the
/// app. See `docs/phase3-spm-rfc.md` for the extraction plan.
///
/// During Phase 3 scaffolding (step 3.1) this file is intentionally empty
/// of public API — its only job is to give the package a non-zero target
/// so `swift build` can resolve the three dependencies (Bonsplit,
/// CMUXDebugLog, MarkdownUI) end-to-end before the protocol seam and
/// first migrated slice land in step 3.2.
public enum ZebraVault {
    public static let version = "0.0.0-scaffold"
}
