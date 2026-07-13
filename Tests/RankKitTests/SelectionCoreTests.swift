import Foundation
import RankKit
import Testing

/// Tests for `Selection`'s `@Generable` schema shape, `SelectionCatalog`
/// conformance, and `RankDiagnostic`'s value semantics (plan.md §6 phase 3)
/// — the remaining core-type coverage for this port not already exercised
/// by `SelectionConfigTests`.
struct SelectionCoreTests {
    // MARK: - `Selection`'s `@Generable` schema shape

    @Test
    func generationSchemaEncodesAnIdsArrayWithAnItemsSubschema() throws {
        let data = try JSONEncoder().encode(Selection.generationSchema)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])

        #expect(idsSchema["items"] != nil)
    }

    // MARK: - `Selection` value semantics

    @Test
    func selectionInitStoresIdsInOrder() {
        let selection = Selection(ids: ["b", "a"])

        #expect(selection.ids == ["b", "a"])
    }

    // MARK: - `SelectionCatalog` conformance

    struct FixtureCatalog: SelectionCatalog {
        let ids: [String]
        private let summaries: [String: String]
        private let blocks: [String: String]

        init(ids: [String], summaries: [String: String], blocks: [String: String]) {
            self.ids = ids
            self.summaries = summaries
            self.blocks = blocks
        }

        func summaryBlock(forId id: String) -> String? { summaries[id] }
        func block(forId id: String) -> String? { blocks[id] }
    }

    @Test
    func selectionCatalogResolvesSummaryAndBlockForKnownIds() {
        let catalog = FixtureCatalog(
            ids: ["deploy"],
            summaries: ["deploy": "short summary"],
            blocks: ["deploy": "the full rendered block"]
        )

        #expect(catalog.ids == ["deploy"])
        #expect(catalog.summaryBlock(forId: "deploy") == "short summary")
        #expect(catalog.block(forId: "deploy") == "the full rendered block")
    }

    @Test
    func selectionCatalogReturnsNilForAnUnknownId() {
        let catalog = FixtureCatalog(ids: [], summaries: [:], blocks: [:])

        #expect(catalog.summaryBlock(forId: "missing") == nil)
        #expect(catalog.block(forId: "missing") == nil)
    }

    // MARK: - `RankDiagnostic` value semantics

    @Test
    func rankDiagnosticCasesCompareEqualByValue() {
        #expect(RankDiagnostic.retrievalCut(considered: 10, kept: 3) == .retrievalCut(considered: 10, kept: 3))
        #expect(RankDiagnostic.unknownSelectedId(id: "x") == .unknownSelectedId(id: "x"))
        #expect(RankDiagnostic.retrievalCut(considered: 10, kept: 3) != .retrievalCut(considered: 10, kept: 4))
    }
}
