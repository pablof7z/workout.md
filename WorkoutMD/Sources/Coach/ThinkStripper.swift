import Foundation

/// Strips `<think>…</think>` / `<thinking>…</thinking>` reasoning blocks out of coach output before
/// it's ever displayed or persisted. Local reasoning models run over Ollama (deepseek-r1, qwq, glm,
/// etc.) emit these around their chain-of-thought; without stripping, the raw tags — and the
/// reasoning itself — leak straight into the transcript shown to the athlete and into
/// `CoachNoteRecord`/memory. See `CoachStreamSink` (streaming, `WorkoutMD/Sources/Coach/
/// CoachController.swift`) for the two call sites: `onTextDelta` (via `Buffer`) and `onCompleted`
/// (via `strip(_:)` directly, since the model's authoritative full text can still contain think
/// blocks even after streaming stripped them from the display).
///
/// A pure, dependency-free helper by design — no `WorkoutSession`/SwiftData/engine coupling — so it's
/// trivially unit-testable with plain strings.
///
/// ## Rules
/// - A well-formed `<think>…</think>` (or `<thinking>…</thinking>`, matched case-insensitively and
///   independent of which spelling opens vs. closes) anywhere in the text is removed entirely: open
///   tag, reasoning content, and close tag.
/// - An unterminated block that's still open when the buffer ends (mid-stream — the model is still
///   "thinking") hides everything from the open tag to the end of the buffer; nothing shows until a
///   close tag arrives in a later chunk.
/// - Some models never emit the opening tag at all: they just start reasoning immediately, then emit
///   a bare `</think>` once they switch to the real answer (the exact shape of the bug this fixes —
///   a readiness audit caught `…summarize this for the athlete.</think>Sets 1 and 2 dropped…`
///   leaking into a transcript). The first think-tag encountered decides this: if it's a close tag
///   with no preceding open anywhere before it, everything from the very start of the text up to and
///   including that close tag is treated as hidden, unmarked reasoning, and only what follows shows.
/// - Any other stray close tag — one seen after a real open/close pair already resolved, or after the
///   leading-omitted-open case above already resolved — is removed as a bare orphan marker without
///   retroactively hiding anything else around it.
/// - Text with no think tags at all passes through completely unchanged.
enum ThinkStripper {
    /// Matches `<think>`, `</think>`, `<thinking>`, `</thinking>` — case-insensitive, tolerant of
    /// stray internal whitespace (e.g. `< think >`) some models emit around the tag name.
    private static let tagPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: "</?\\s*think(?:ing)?\\s*>", options: [.caseInsensitive])
    }()

    /// The visible projection of `raw` per the rules above. A pure function of the full text seen so
    /// far — safe to call repeatedly on a growing buffer (see `Buffer`) or once on a complete string.
    static func strip(_ raw: String) -> String {
        let ns = raw as NSString
        let matches = tagPattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return raw }

        var result = ""
        var insideThink = false
        var sawOpenEver = false
        var cursor = 0

        for match in matches {
            let range = match.range
            let plain = ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            let tag = ns.substring(with: range)
            let isClose = tag.contains("/")

            if insideThink {
                // Whatever text preceded this tag was reasoning content — drop it. A close tag ends
                // the hidden run; another open tag (nested/duplicate) just leaves it open.
                if isClose {
                    insideThink = false
                }
            } else if isClose {
                if sawOpenEver {
                    // A real block already opened and closed earlier — this is a genuine stray
                    // marker. Keep the plain text, drop only the bare tag.
                    result += plain
                } else {
                    // Leading omitted-open case: everything seen so far (just `plain`, since this is
                    // necessarily the first tag in the string) was actually unmarked reasoning.
                    result = ""
                }
                sawOpenEver = true
            } else {
                result += plain
                insideThink = true
                sawOpenEver = true
            }

            cursor = range.location + range.length
        }

        let trailing = ns.substring(from: cursor)
        if !insideThink {
            result += trailing
        }
        // else: still inside an unterminated block — the trailing (in-progress reasoning) text stays
        // hidden until a close tag shows up in a later `strip` call over a longer buffer.

        return result
    }

    /// Every partial prefix (length 1 up to, but not including, the full tag) of the four tag
    /// spellings, longest first — used by `Buffer` to hold back a trailing fragment that could still
    /// turn into a tag once more deltas arrive (e.g. a delta boundary landing mid-tag: `"<thi"` then
    /// `"nk>"`). `strip(_:)` itself only recognizes *complete* tags (it needs the closing `>`), so
    /// without this a fragment like `"<thi"` would flash on screen as literal text for one delta.
    private static let tagPrefixesForHoldback: [String] = {
        ["<thinking>", "</thinking>", "<think>", "</think>"]
            .flatMap { tag in (1..<tag.count).map { String(tag.prefix($0)) } }
            .sorted { $0.count > $1.count }
    }()

    /// The number of trailing characters of `text` that match (case-insensitively) a partial prefix
    /// of a think tag — i.e. how much of the tail is still ambiguous and should be held back from
    /// display until the next delta resolves it one way or the other.
    fileprivate static func holdbackLength(forTailOf text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let lower = text.lowercased()
        for prefix in tagPrefixesForHoldback where lower.hasSuffix(prefix) {
            return prefix.count
        }
        return 0
    }

    /// Streaming accumulator: feed it raw deltas in arrival order and read `.visible` after each feed
    /// for the current think-stripped projection of everything received so far this turn. Holds back
    /// a trailing tag-prefix fragment (see `holdbackLength(forTailOf:)`) so a tag split across a
    /// delta boundary never flashes as literal text before resolving.
    struct Buffer {
        private(set) var raw = ""
        private(set) var visible = ""

        init() {}

        @discardableResult
        mutating func append(_ delta: String) -> String {
            raw += delta
            let full = ThinkStripper.strip(raw)
            let holdback = ThinkStripper.holdbackLength(forTailOf: full)
            visible = holdback > 0 ? String(full.dropLast(holdback)) : full
            return visible
        }
    }
}
