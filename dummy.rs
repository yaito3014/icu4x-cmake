// Intentionally empty stub.
//
// This crate exists only to pin icu_capi as a dependency (see Cargo.toml) so
// CMake can build it as a static library via `cargo rustc -p icu_capi`. Cargo
// requires the [lib] target to point at a source file, so this stub stands in
// for one; nothing here is ever compiled into the shipped artifact.
