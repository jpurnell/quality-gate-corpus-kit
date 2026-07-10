import Foundation
import Testing
@testable import CorpusKit

@Suite("Identity migration proposals (0.4)")
struct IdentityMigrationTests {

    @Test("proposes aliases for legacy dirs that exist in the corpus and are not the identity")
    func proposesForExistingLegacyDirs() {
        let proposal = IdentityMigration.proposedAliases(
            identityID: "jpurnell__WineTaster",
            legacyCandidates: ["WineTaster", "WineTaster 4"],
            corpusDirectories: ["WineTaster", "WineTaster 4", "unrelated-project"],
            existingAliases: [:])
        #expect(proposal == [
            "WineTaster": "jpurnell__WineTaster",
            "WineTaster 4": "jpurnell__WineTaster",
        ])
    }

    @Test("skips candidates with no corpus history")
    func skipsAbsentDirs() {
        let proposal = IdentityMigration.proposedAliases(
            identityID: "jpurnell__repo",
            legacyCandidates: ["repo-old-name"],
            corpusDirectories: ["something-else"],
            existingAliases: [:])
        #expect(proposal.isEmpty)
    }

    @Test("never proposes the identity itself or an already-aliased dir")
    func skipsIdentityAndExisting() {
        let proposal = IdentityMigration.proposedAliases(
            identityID: "jpurnell__repo",
            legacyCandidates: ["jpurnell__repo", "repo", "repo-old"],
            corpusDirectories: ["jpurnell__repo", "repo", "repo-old"],
            existingAliases: ["repo-old": "jpurnell__repo"])
        #expect(proposal == ["repo": "jpurnell__repo"])
    }

    @Test("does not repropose a dir aliased to a different identity — conflicts are surfaced, not overwritten")
    func conflictingAliasLeftAlone() {
        let proposal = IdentityMigration.proposedAliases(
            identityID: "jpurnell__repo",
            legacyCandidates: ["repo"],
            corpusDirectories: ["repo"],
            existingAliases: ["repo": "someoneelse__repo"])
        #expect(proposal.isEmpty)
    }
}
