// src/lib.rs
// Re-exports migration definitions so they can be shared between main.rs and tests.
//
// The Tauri-specific types are only compiled when the "tauri" feature is enabled
// (the default). Run `cargo test --no-default-features` to build the test suite
// in headless environments that lack GTK / WebKit system libraries.

#[cfg(feature = "tauri")]
use tauri_plugin_sql::{Migration, MigrationKind};

/// Returns the ordered list of SQL migrations for `sqlite:zq_workstation.db`.
///
/// Each migration is embedded at compile-time via `include_str!` so the binary
/// is fully self-contained – no external SQL files need to be distributed.
#[cfg(feature = "tauri")]
pub fn db_migrations() -> Vec<Migration> {
    vec![
        Migration {
            version:     1,
            description: "initial_core_schema",
            sql:         include_str!("../migrations/001_initial.sql"),
            kind:        MigrationKind::Up,
        },
        Migration {
            version:     2,
            description: "workspace_extensions",
            sql:         include_str!("../migrations/002_workspace_extensions.sql"),
            kind:        MigrationKind::Up,
        },
        Migration {
            version:     3,
            description: "audit_improvements",
            sql:         include_str!("../migrations/003_audit_improvements.sql"),
            kind:        MigrationKind::Up,
        },
    ]
}
