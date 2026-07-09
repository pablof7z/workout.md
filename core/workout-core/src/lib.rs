//! `workout-core` — Workout.md's Rust core, exposed to the native iOS shell
//! through a UniFFI facade.
//!
//! Alongside the minimal `WorkoutCore` proof-of-pipeline object, this crate
//! carries the LLM coach engine (see [`coach`]) built on rig.rs: provider
//! configuration, a streaming turn loop, and the coach tool set; and the
//! Nostr/NIP-29 fabric module (see [`nostr`]) that lets the coach join the
//! user's tenex-edge fabric and exchange context with their other agents
//! over kind:9 chat messages.

pub mod coach;
pub mod nostr;

uniffi::setup_scaffolding!();

/// Returns this crate's own version string (from `Cargo.toml` at compile
/// time), so the Swift shell can prove it is actually calling into the
/// compiled Rust core rather than a stub.
#[uniffi::export]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Minimal UniFFI object proving the facade can hand a live Rust-owned
/// handle across the FFI boundary and call methods on it.
#[derive(uniffi::Object)]
pub struct WorkoutCore;

#[uniffi::export]
impl WorkoutCore {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self
    }

    /// Echoes the given message back unchanged — proves argument marshaling
    /// across the FFI boundary in both directions.
    pub fn echo(&self, message: String) -> String {
        message
    }

    /// Returns a small greeting string that embeds the crate version, for a
    /// single human-visible round trip from Swift into Rust and back.
    pub fn greeting(&self) -> String {
        format!("workout-core v{} online", core_version())
    }
}

impl Default for WorkoutCore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_non_empty() {
        assert!(!core_version().is_empty());
    }

    #[test]
    fn echo_returns_input_unchanged() {
        let core = WorkoutCore::new();
        assert_eq!(core.echo("ping".to_string()), "ping");
    }

    #[test]
    fn greeting_contains_version() {
        let core = WorkoutCore::new();
        assert!(core.greeting().contains(&core_version()));
    }
}
