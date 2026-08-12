import Foundation

/// The read side of the round trip (domain-primitives.md §11): extracts and decodes the hidden
/// `<!-- workout.md:canonical v1 ... -->` block `MarkdownGenerator`/`CanonicalMarkdown` append to a
/// `plan.md` or `sessions/*.md` file. Every function here is total (never crashes) and returns `nil`
/// for Markdown with no canonical block — a `README.md` (export-only, never carries one — see
/// `CanonicalMarkdown`'s doc comment), a hand-written session note, or any other plain Markdown a
/// human dropped into the synced folder outside the app.
enum MarkdownParser {

    /// The raw JSON payload inside the hidden canonical comment, or `nil` if `markdown` doesn't
    /// contain one at all (not "contains one that fails to decode" — that's `parsePlan`/
    /// `parseSession`'s job to report as `nil` too, just via a different path).
    static func canonicalJSON(in markdown: String) -> Data? {
        let openMarker = "<!-- \(CanonicalMarkdown.marker) \(CanonicalMarkdown.version)\n"
        guard let openRange = markdown.range(of: openMarker) else { return nil }
        guard let closeRange = markdown.range(of: "\n-->", range: openRange.upperBound..<markdown.endIndex) else {
            return nil
        }
        let json = markdown[openRange.upperBound..<closeRange.lowerBound]
        return Data(json.utf8)
    }

    /// Decodes `markdown`'s canonical block as a `PlanSnapshot`. `nil` if there's no canonical block,
    /// or if the block's JSON doesn't decode as a `PlanSnapshot` (e.g. it's actually a session file).
    static func parsePlan(_ markdown: String) -> PlanSnapshot? {
        guard let data = canonicalJSON(in: markdown) else { return nil }
        return try? CanonicalMarkdown.decoder.decode(PlanSnapshot.self, from: data)
    }

    /// Decodes `markdown`'s canonical block as a `SessionDTO`. `nil` if there's no canonical block,
    /// or if the block's JSON doesn't decode as a `SessionDTO` (e.g. it's actually a plan file).
    static func parseSession(_ markdown: String) -> SessionDTO? {
        guard let data = canonicalJSON(in: markdown) else { return nil }
        return try? CanonicalMarkdown.decoder.decode(SessionDTO.self, from: data)
    }
}
