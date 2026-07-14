import Foundation
import FoundationModelsRouter
import Testing

@testable import FoundationModelsRanker

// MARK: - Shared `.jsonSchema` `Grammar` id-enum extraction
//
// `SelectionTests` and `OverBudgetTests` both need to assert on the id set a
// `SelectionTier.idEnumGrammar(ids:)`-produced `Grammar` constrains to,
// without depending on `JSONSerialization`'s unstable key ordering (which
// makes two separately-encoded but semantically-equivalent grammars compare
// unequal under `Grammar`'s raw-string `Equatable`). This lives once, here,
// rather than duplicated per test suite.

/// Extracts the `properties.ids.items.enum` id set a `.jsonSchema` `Grammar`
/// constrains to -- lets a test assert on grammar *content* without
/// depending on `JSONSerialization`'s unstable key ordering, which makes two
/// separately-encoded but equivalent grammars compare unequal under
/// `Grammar`'s raw-string `Equatable`.
enum GrammarTestSupport {
    static func enumIds(in grammar: Grammar) throws -> Set<String> {
        guard case .jsonSchema(let source) = grammar else {
            Issue.record("expected a .jsonSchema grammar")
            return []
        }
        let data = try #require(source.data(using: .utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])
        let itemsSchema = try #require(idsSchema["items"] as? [String: Any])
        let enumValues = try #require(itemsSchema["enum"] as? [String])
        return Set(enumValues)
    }
}
