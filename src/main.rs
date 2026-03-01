// src/main.rs
// Tauri v2 entry point for ZQ AI Workstation.
//
// Registers tauri-plugin-sql with the three database migrations so the SQLite
// database is automatically created and fully migrated before any window opens.

// Prevent a console window from appearing on Windows in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

#[cfg(feature = "tauri")]
use zq_ai_workstation_lib::db_migrations;

#[cfg(feature = "tauri")]
fn main() {
    tauri::Builder::default()
        .plugin(
            tauri_plugin_sql::Builder::default()
                .add_migrations("sqlite:zq_workstation.db", db_migrations())
                .build(),
        )
        .run(tauri::generate_context!())
        .expect("error while running ZQ AI Workstation");
}

// Stub entry point when building without the Tauri feature (e.g. for testing).
#[cfg(not(feature = "tauri"))]
fn main() {}
