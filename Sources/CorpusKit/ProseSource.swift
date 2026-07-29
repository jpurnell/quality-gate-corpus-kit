import Foundation

/// Where a piece of corpus prose came from — its provenance/durability tier.
///
/// Shared by every producer of narrative or descriptive text in the corpus:
/// module orientation cards (``ModuleOrientationCard``) and the weekly pulse
/// narrative (``InstitutionalPulse/narrativeSource``). The factual fields those
/// artifacts carry never depend on this — provenance annotates the prose only.
///
/// The durability order, best to last-resort, is:
/// `claude` > `onDeviceLLM` > `preservedLLM` > `template`.
///
/// Raw values are stable: they are persisted in corpus JSON and in
/// `NARRATIVE_*.md` frontmatter, so cases must never be renamed.
public enum ProseSource: String, Sendable, Codable, Equatable, CaseIterable {
    /// Deterministic, non-LLM synthesis from structured facts — the last resort.
    case template
    /// Cloud LLM (Anthropic Claude) — the primary, highest-quality engine.
    case claude
    /// Apple Foundation Models, generated entirely on-device — the offline / no-key fallback.
    case onDeviceLLM
    /// The prior artifact's LLM prose, carried forward verbatim when no engine could run.
    case preservedLLM
}
