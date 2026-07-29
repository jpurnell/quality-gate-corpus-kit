import Testing
import Foundation
@testable import CorpusKit

@Suite("ProseSource")
struct ProseSourceTests {

    @Test("covers the full narrative-provenance vocabulary")
    func cases() {
        #expect(Set(ProseSource.allCases) == [.template, .claude, .onDeviceLLM, .preservedLLM])
    }

    @Test("raw values are stable (persisted in the corpus and NARRATIVE frontmatter)")
    func rawValues() {
        #expect(ProseSource.template.rawValue == "template")
        #expect(ProseSource.claude.rawValue == "claude")
        #expect(ProseSource.onDeviceLLM.rawValue == "onDeviceLLM")
        #expect(ProseSource.preservedLLM.rawValue == "preservedLLM")
    }

    @Test("round-trips through JSON")
    func roundTrip() throws {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        for source in ProseSource.allCases {
            let data = try enc.encode(source)
            #expect(try dec.decode(ProseSource.self, from: data) == source)
        }
    }
}
