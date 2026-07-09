//! `workout-core` — Workout.md's Rust core, exposed to the native iOS shell
//! through a UniFFI facade.
//!
//! This crate is deliberately minimal. Its only job in this PR is to prove
//! the Rust <-> Swift pipeline builds and links for both the simulator and
//! device, with a trivial call across the FFI boundary landing on a real
//! Rust-owned object. It does not yet carry rig.rs/LLM or Nostr integration
//! — that lands in a follow-up PR.

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
