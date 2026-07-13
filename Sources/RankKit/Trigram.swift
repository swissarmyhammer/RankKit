// Ported from CodeContextKit's `Sources/CodeContextKit/Search/Trigram.swift`.
// Lineage: Rust `swissarmyhammer-search` crate's `score.rs` ->
// CodeContextKit -> RankKit (plan.md §3). No behavior changes.

/// Character-trigram Sørensen-Dice similarity — the typo/partial-identifier
/// fuzzy-match signal (see plan.md "Search"). Ported from the Rust crate's
/// `score.rs`.
public enum Trigram {
    /// Sørensen-Dice coefficient over the *sets* of character trigrams of
    /// two strings.
    ///
    /// Computes `2·|A∩B| / (|A|+|B|)` where `A` and `B` are the
    /// deduplicated canonical trigram sets (`canonicalTrigramSet(text:)`) of
    /// each input.
    ///
    /// Each input is canonicalized through `Tokenizer.tokenize(text:)` and
    /// re-joined with single spaces before trigramming. This normalizes
    /// identifier delimiters so that `camelCase`, `snake_case`, and
    /// `kebab-case` spellings of the same words share trigrams — which is
    /// what makes the signal a *typo / style* rescue rather than a literal
    /// substring match. Without it, `"getUsr"` and `"get_user"` would share
    /// only the `get` trigram (Dice 0.2); after canonicalization they
    /// become `"get usr"` vs `"get user"` and overlap strongly (Dice >
    /// 0.7).
    ///
    /// - Parameters:
    ///   - query: the first string to compare.
    ///   - target: the second string to compare. Order is irrelevant.
    /// - Returns: a similarity in `[0.0, 1.0]`; `1.0` for equal canonical
    ///   trigram sets, `0.0` when either side yields no trigrams (too short
    ///   after canonicalization) or the sets are disjoint.
    public static func dice(query: String, target: String) -> Double {
        dice(querySet: canonicalTrigramSet(text: query), targetSet: canonicalTrigramSet(text: target))
    }

    /// Sørensen-Dice coefficient over two already-canonicalized trigram sets.
    ///
    /// The same `2·|A∩B| / (|A|+|B|)` formula as `dice(query:target:)`, for
    /// callers that already hold both sides' `canonicalTrigramSet(text:)`
    /// output — e.g. a per-document trigram set cached once and reused
    /// across many queries, where recomputing the document's canonical form
    /// on every query would repeat work that doesn't depend on the query at
    /// all. `dice(query:target:)` is implemented in terms of this overload,
    /// so the two can never drift apart.
    ///
    /// - Parameters:
    ///   - querySet: The first canonical trigram set to compare.
    ///   - targetSet: The second canonical trigram set to compare. Order is
    ///     irrelevant.
    /// - Returns: a similarity in `[0.0, 1.0]`; `1.0` for equal sets, `0.0`
    ///   when either set is empty or the sets are disjoint.
    public static func dice(querySet: Set<String>, targetSet: Set<String>) -> Double {
        guard !querySet.isEmpty, !targetSet.isEmpty else { return 0.0 }
        let intersectionCount = Double(querySet.intersection(targetSet).count)
        return 2.0 * intersectionCount / Double(querySet.count + targetSet.count)
    }

    /// Canonicalize `text` (tokenize, re-join with spaces) and return its
    /// trigram set.
    ///
    /// This is the single authority for "does this string have trigrams?":
    /// callers detecting whether the trigram signal carries data for a
    /// query, and `dice(query:target:)` itself, both go through this canonical form
    /// — so a string with an empty canonical trigram set can never
    /// contribute a non-zero trigram score.
    ///
    /// - Parameter text: the string to canonicalize and trigram.
    /// - Returns: the deduplicated set of length-3 character windows of the
    ///   canonical form.
    public static func canonicalTrigramSet(text: String) -> Set<String> {
        let canonical = Tokenizer.tokenize(text: text).joined(separator: " ")
        return Set(Tokenizer.charTrigrams(text: canonical))
    }
}
