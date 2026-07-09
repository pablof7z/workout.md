//! `workout-core`'s own `uniffi-bindgen` binary.
//!
//! Built only when the `bindgen` feature is enabled
//! (`cargo run --features bindgen --bin uniffi-bindgen`), so a normal
//! `cargo build`/`cargo check` never links the UniFFI CLI. Running the
//! bindgen binary from the exact same crate/version as the library it
//! introspects guarantees the generator and the library agree on the UniFFI
//! wire format — a globally installed `uniffi-bindgen` binary is not
//! guaranteed to match this crate's `uniffi` version.

fn main() {
    uniffi::uniffi_bindgen_main()
}
