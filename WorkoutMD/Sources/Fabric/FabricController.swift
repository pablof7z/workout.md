import Foundation
import Observation

/// A coarse status for the Settings connection indicator. Not a strict state machine (the underlying
/// `NostrCoach` reconnects on its own) — just enough for the UI to say "not configured" vs. "trying"
/// vs. "the last publish/subscribe attempt succeeded" vs. "the last one failed".
enum FabricConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error(let message): return "Error: \(message)"
        }
    }
}

/// One inbound kind:9 fabric chat message, buffered both for the small "Fabric" view and for the
/// coach's own grounding context (`FabricController.contextSnippet`).
struct FabricMessage: Identifiable, Equatable {
    let id: String
    /// Hex pubkey — inbound events hand us the raw hex (`event.pubkey.to_hex()` on the Rust side),
    /// not a bech32 `npub`, so this is displayed truncated rather than re-encoded.
    let authorPubkey: String
    let body: String
    let createdAt: Date

    var authorShort: String { String(authorPubkey.prefix(8)) }
}

/// Owns the live `NostrCoach` (the Rust NIP-29 fabric engine, over UniFFI) and wires the app into the
/// user's tenex-edge fabric: joins a channel, publishes the coach's own kind:0 profile, posts terse
/// kind:9 summaries when something notable happens in a session (see `CoachController` and
/// `WorkoutMDApp.saveToHistory`), and buffers inbound kind:9 traffic from the user's other agents —
/// both for `FabricView` and for the coach's own grounding context.
///
/// Created once at the app root (`WorkoutMDApp`) and injected via `.environment(FabricController.self)`,
/// mirroring `CoachController`. `CoachController` also holds a reference (default `.shared`, exactly
/// like it already does for `AppSettings`) so a coach turn can fold in recent fabric traffic and post
/// notable plan changes without every call site threading a fabric reference through by hand.
///
/// ## Identity & Keychain
/// The coach's nsec lives only in the Keychain (`FabricSecrets`), mirroring `CoachSecrets`/`GitHubAuth`
/// — never held in a Swift-visible stored property beyond the moment it's handed to
/// `NostrCoach.importNsec`/read back from `NostrCoach.exportNsec`, never written to `UserDefaults`,
/// never logged.
///
/// ## Threading
/// `NostrCoach.configure`/`publishProfile`/`publishMessage` block the calling thread for the duration
/// of their own network round trip (per the Rust module doc, up to `CONNECT_WAIT` — 8s — just to
/// settle the relay connection). Every call site here that reaches the network runs on a background
/// `DispatchQueue`, hopping back to `DispatchQueue.main` only to update the `@Observable` state the UI
/// reads — the same marshaling shape `CoachController`'s `CoachStreamSink` uses for the engine's own
/// background-runtime callbacks.
@Observable
final class FabricController {
    static let shared = FabricController()

    private let engine: NostrCoach
    private let settings: AppSettings

    private(set) var status: FabricConnectionStatus = .disconnected
    private(set) var npub: String?
    private(set) var messages: [FabricMessage] = []
    private(set) var lastPublishError: String?
    /// Whether `messages` holds anything the coach grounding context hasn't been folded into yet —
    /// cleared by `contextSnippet()`, the one place a turn actually "consumes" the buffer. Lets a
    /// future UI badge say "new messages from your other agents" per the product vision.
    private(set) var hasUnseenMessages = false

    /// Bounded so a long-running fabric subscription doesn't grow this without limit.
    private static let messageBufferLimit = 50

    var channelLabel: String { settings.fabricChannel }

    init(settings: AppSettings = .shared, engine: NostrCoach = NostrCoach()) {
        self.settings = settings
        self.engine = engine
        npub = engine.currentNpub()
        if settings.fabricEnabled {
            enable()
        }
    }

    // MARK: - Enable / disable

    /// Ensures an identity exists (generating + persisting one to the Keychain on first use, else
    /// importing the stored one), configures the engine from `AppSettings`, publishes the coach's
    /// profile, and starts the inbound subscription. Safe to call again — every one of these Rust
    /// calls is documented idempotent/reconfigurable. Called automatically at launch if
    /// `AppSettings.fabricEnabled` was already on, and from the Settings toggle otherwise.
    func enable() {
        let channel = settings.fabricChannel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channel.isEmpty else {
            status = .error("Set a channel slug first.")
            return
        }
        status = .connecting

        let relays = settings.fabricRelaysList
        let indexerTrimmed = settings.fabricIndexerRelay.trimmingCharacters(in: .whitespaces)
        let indexer = indexerTrimmed.isEmpty ? nil : indexerTrimmed
        let displayName = settings.fabricDisplayName.isEmpty ? "coach" : settings.fabricDisplayName
        let about = settings.fabricAbout.isEmpty ? nil : settings.fabricAbout

        do {
            let resolvedNpub = try ensureIdentity()
            if !resolvedNpub.isEmpty { npub = resolvedNpub }
        } catch {
            status = .error(String(describing: error))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [engine] in
            engine.configure(relays: relays, indexerRelay: indexer, channel: channel)
            do {
                _ = try engine.publishProfile(name: displayName, about: about, picture: nil)
                DispatchQueue.main.async { [weak self] in
                    self?.status = .connected
                    self?.startSubscription()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.status = .error(String(describing: error))
                }
            }
        }
    }

    /// Flips the toggle off. There's no explicit teardown on the Rust side — the background
    /// subscription (if started) keeps running harmlessly, matching `NostrCoach.start_subscription`'s
    /// fire-and-forget shape — but `postSummary`/`contextSnippet` both gate on
    /// `AppSettings.fabricEnabled`, so disabling here stops any further outbound posts or grounding
    /// injection immediately.
    func disable() {
        status = .disconnected
    }

    /// The Settings "Publish profile" button — re-publishes the kind:0 profile on demand, independent
    /// of `enable()`'s automatic publish (e.g. after editing the display name/about text).
    func publishProfile() {
        guard settings.fabricEnabled else { return }
        let displayName = settings.fabricDisplayName.isEmpty ? "coach" : settings.fabricDisplayName
        let about = settings.fabricAbout.isEmpty ? nil : settings.fabricAbout

        if npub == nil {
            do {
                let resolvedNpub = try ensureIdentity()
                if !resolvedNpub.isEmpty { npub = resolvedNpub }
            } catch {
                lastPublishError = String(describing: error)
                return
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [engine] in
            do {
                _ = try engine.publishProfile(name: displayName, about: about, picture: nil)
                DispatchQueue.main.async { [weak self] in self?.lastPublishError = nil }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.lastPublishError = String(describing: error) }
            }
        }
    }

    #if DEBUG
    /// Debug-only convenience for live testing on a channel this device's coach identity doesn't
    /// already have membership on: creates (kind:9007) and immediately locks closed+public
    /// (kind:9002) the configured channel, so the current identity becomes its sole admin — see
    /// `NostrCoach.create_group`'s doc comment ("useful for tests and for a coach that wants to own a
    /// private channel of its own"). Not part of the shipped Settings flow: a real channel is owned by
    /// the user's tenex-edge fabric, joined via the admin-granted `tenex-edge channel add` path
    /// surfaced elsewhere in Settings, not created by the coach itself.
    func createTestGroupForCurrentChannel() {
        let channel = settings.fabricChannel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channel.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [engine] in
            do {
                _ = try engine.createGroup(channel: channel, name: channel)
                DispatchQueue.main.async { [weak self] in self?.lastPublishError = nil }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.lastPublishError = String(describing: error) }
            }
        }
    }
    #endif

    // MARK: - Identity

    /// Imports the Keychain-stored nsec if there is one, otherwise generates a fresh identity and
    /// persists its nsec to the Keychain — mirrors `CoachSecrets`' "generate once, import thereafter"
    /// shape described in the task's identity-storage requirement. Returns the resulting npub (empty
    /// string only if the underlying `current_npub()` genuinely has nothing, which shouldn't happen
    /// once either branch below has run).
    private func ensureIdentity() throws -> String {
        if let stored = try FabricSecrets.nsec(), !stored.isEmpty {
            try engine.importNsec(nsec: stored)
            return engine.currentNpub() ?? ""
        }
        let generatedNpub = engine.generateIdentity()
        if let nsec = engine.exportNsec() {
            try FabricSecrets.setNsec(nsec)
        }
        return generatedNpub
    }

    // MARK: - Outbound

    /// Posts a terse kind:9 summary to the configured channel — a finished session
    /// (`postSessionSummary`) or a notable coach-applied plan change (see `CoachController`'s
    /// `WorkoutSessionCoachHost`). No-op unless the fabric is enabled. Failures land in
    /// `lastPublishError` rather than surfacing as a crash — a dropped fabric post should never break
    /// the coach flow it's reporting on (e.g. a closed channel the coach hasn't been admin-added to
    /// yet — see the Settings footer's `tenex-edge channel add` hint).
    func postSummary(_ body: String) {
        guard settings.fabricEnabled else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [engine] in
            do {
                _ = try engine.publishMessage(body: trimmed, replyTo: nil, mentionPubkey: nil)
                DispatchQueue.main.async { [weak self] in self?.lastPublishError = nil }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.lastPublishError = String(describing: error) }
            }
        }
    }

    /// Builds and posts a terse "session finished" summary from a completed `WorkoutRecord` — the
    /// outbound half of the vision: the coach tells the user's other agents how training went, dryly,
    /// in one line, e.g. "Upper Body A done — 9/9 sets · avg RPE 7.8, dropped Bench Press to 125 lb".
    func postSessionSummary(_ record: WorkoutRecord) {
        postSummary(Self.summaryLine(for: record))
    }

    private static func summaryLine(for record: WorkoutRecord) -> String {
        var line = "\(record.name) done — \(record.oneLineSummary)"
        if let deviation = notableDeviation(in: record) {
            line += ", \(deviation)"
        }
        return line
    }

    /// The single most notable actual-vs-prescribed deviation across the session (a changed working
    /// weight) — terse enough to fold into one summary line. First match wins; this is a dry one-line
    /// summary, not a full deviation report (`HistoryView`/`MarkdownGenerator` already cover that).
    private static func notableDeviation(in record: WorkoutRecord) -> String? {
        let exercises = record.exercises.sorted { $0.order < $1.order }
        for exercise in exercises {
            let sets = exercise.sets.sorted { $0.order < $1.order }
            for set in sets {
                guard !set.skipped,
                      let prescribedWeight = set.prescribedWeight,
                      let actualWeight = set.actualWeight,
                      actualWeight != prescribedWeight else { continue }
                let verb = actualWeight < prescribedWeight ? "dropped" : "bumped"
                return "\(verb) \(exercise.name) to \(Int(actualWeight)) lb"
            }
        }
        return nil
    }

    // MARK: - Inbound

    private func startSubscription() {
        let sink = FabricSink(
            onEvent: { [weak self] id, authorPubkey, body, createdAt in
                self?.handle(id: id, authorPubkey: authorPubkey, body: body, createdAt: createdAt)
            },
            onError: { [weak self] message in
                self?.status = .error(message)
            }
        )
        engine.startSubscription(sink: sink)
    }

    private func handle(id: String, authorPubkey: String, body: String, createdAt: UInt64) {
        guard !messages.contains(where: { $0.id == id }) else { return } // relays may re-deliver
        let message = FabricMessage(
            id: id,
            authorPubkey: authorPubkey,
            body: body,
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdAt))
        )
        messages.append(message)
        if messages.count > Self.messageBufferLimit {
            messages.removeFirst(messages.count - Self.messageBufferLimit)
        }
        hasUnseenMessages = true
    }

    // MARK: - Coach grounding

    /// A terse context block folded into the coach's `user_message` grounding (see
    /// `CoachController.send`), e.g.:
    /// ```
    /// Fabric (tenex-edge #push-day) — 2 recent message(s) from your other agents:
    /// - a1b2c3d4: logged 3mi run, felt good
    /// - e5f6a7b8: sleep was short last night, 5.5h
    /// ```
    /// Returns an empty string if the fabric is disabled or there's nothing buffered yet. Marks the
    /// buffer "seen" as a side effect — this is the one place a coach turn actually consumes it, per
    /// the product vision that the coach "takes into account" what the other agents said.
    func contextSnippet(limit: Int = 5) -> String {
        guard settings.fabricEnabled, !messages.isEmpty else { return "" }
        defer { hasUnseenMessages = false }
        let recent = messages.suffix(limit)
        var lines = ["Fabric (tenex-edge #\(settings.fabricChannel)) — \(recent.count) recent message(s) from your other agents:"]
        lines.append(contentsOf: recent.map { "- \($0.authorShort): \($0.body)" })
        return lines.joined(separator: "\n")
    }
}

// MARK: - NostrSink

/// Marshals every `NostrSink` callback onto the main thread before touching `FabricController`'s
/// `@Observable` state — mirrors `CoachController`'s `CoachStreamSink`. `NostrSink`'s methods are
/// called from `NostrCoach`'s own background tokio runtime, never from the thread that called
/// `start_subscription`.
private final class FabricSink: NostrSink, @unchecked Sendable {
    private let onEvent: (String, String, String, UInt64) -> Void
    private let onErrorHandler: (String) -> Void

    init(onEvent: @escaping (String, String, String, UInt64) -> Void, onError: @escaping (String) -> Void) {
        self.onEvent = onEvent
        self.onErrorHandler = onError
    }

    func onMessage(id: String, authorPubkey: String, body: String, createdAt: UInt64) {
        DispatchQueue.main.async { [onEvent] in onEvent(id, authorPubkey, body, createdAt) }
    }

    func onError(message: String) {
        DispatchQueue.main.async { [onErrorHandler] in onErrorHandler(message) }
    }
}
