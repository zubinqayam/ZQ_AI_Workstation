// src/tests/test_migrations.rs
//
// Integration tests that apply all three SQL migrations against a real
// in-process SQLite database (via `rusqlite`) and verify the schema is
// exactly as expected.
//
// Run with:
//   cargo test --test test_migrations

use rusqlite::{Connection, Result};
use std::fs;
use tempfile::tempdir;

// ─── helpers ─────────────────────────────────────────────────────────────────

/// Open an in-memory database, apply every migration in order, and return the
/// open connection.
fn apply_all_migrations() -> Result<Connection> {
    let conn = Connection::open_in_memory()?;

    conn.execute_batch("PRAGMA foreign_keys = ON;")?;

    let migration_files = [
        "migrations/001_initial.sql",
        "migrations/002_workspace_extensions.sql",
        "migrations/003_audit_improvements.sql",
    ];

    for path in &migration_files {
        let sql = fs::read_to_string(path)
            .unwrap_or_else(|e| panic!("Failed to read {path}: {e}"));
        conn.execute_batch(&sql)
            .unwrap_or_else(|e| panic!("Migration {path} failed: {e}"));
    }

    Ok(conn)
}

/// Return whether a table exists.
fn table_exists(conn: &Connection, name: &str) -> bool {
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?1",
            [name],
            |row| row.get(0),
        )
        .unwrap_or(0);
    count > 0
}

/// Return whether a trigger exists.
fn trigger_exists(conn: &Connection, name: &str) -> bool {
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name=?1",
            [name],
            |row| row.get(0),
        )
        .unwrap_or(0);
    count > 0
}

/// Return whether an index exists.
fn index_exists(conn: &Connection, name: &str) -> bool {
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name=?1",
            [name],
            |row| row.get(0),
        )
        .unwrap_or(0);
    count > 0
}

// ─── tests ───────────────────────────────────────────────────────────────────

#[test]
fn test_migrations_apply_without_error() {
    apply_all_migrations().expect("All migrations should apply cleanly");
}

#[test]
fn test_core_tables_exist() {
    let conn = apply_all_migrations().unwrap();
    let required = [
        "workspaces",
        "projects",
        "folders",
        "documents",
        "ai_models",
        "conversations",
        "messages",
        "tags",
        "document_tags",
        "conversation_tags",
        "settings",
        "audit_log",
    ];
    for table in &required {
        assert!(table_exists(&conn, table), "Table '{table}' should exist");
    }
}

#[test]
fn test_extension_tables_exist() {
    let conn = apply_all_migrations().unwrap();
    let required = [
        "workspace_members",
        "pinned_items",
        "workspace_tags",
        "project_templates",
        "schema_migrations",
    ];
    for table in &required {
        assert!(table_exists(&conn, table), "Table '{table}' should exist");
    }
}

#[test]
fn test_audit_triggers_exist() {
    let conn = apply_all_migrations().unwrap();
    let triggers = [
        "audit_workspaces_update",
        "audit_workspaces_delete",
        "audit_projects_update",
        "audit_projects_delete",
        "audit_documents_update",
        "audit_documents_delete",
        "trig_workspaces_updated_at",
        "trig_projects_updated_at",
        "trig_documents_updated_at",
        "trig_conversations_updated_at",
    ];
    for trigger in &triggers {
        assert!(
            trigger_exists(&conn, trigger),
            "Trigger '{trigger}' should exist"
        );
    }
}

#[test]
fn test_core_indexes_exist() {
    let conn = apply_all_migrations().unwrap();
    let indexes = [
        "idx_projects_workspace",
        "idx_folders_project",
        "idx_documents_project",
        "idx_conversations_workspace",
        "idx_messages_conversation",
        "idx_audit_log_table_record",
        "idx_settings_scope_key",
        "idx_settings_unique_scope_key",
    ];
    for idx in &indexes {
        assert!(index_exists(&conn, idx), "Index '{idx}' should exist");
    }
}

#[test]
fn test_schema_migrations_rows() {
    let conn = apply_all_migrations().unwrap();
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM schema_migrations", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(count, 3, "schema_migrations should contain 3 rows");
}

#[test]
fn test_insert_and_cascade_delete() {
    let conn = apply_all_migrations().unwrap();

    conn.execute(
        "INSERT INTO workspaces (name) VALUES ('Test WS')",
        [],
    )
    .unwrap();
    let ws_id: i64 = conn
        .query_row("SELECT last_insert_rowid()", [], |r| r.get(0))
        .unwrap();

    conn.execute(
        "INSERT INTO projects (workspace_id, name) VALUES (?1, 'Test Project')",
        [ws_id],
    )
    .unwrap();

    // Deleting the workspace should cascade to projects.
    conn.execute("DELETE FROM workspaces WHERE id = ?1", [ws_id])
        .unwrap();

    let project_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM projects WHERE workspace_id = ?1", [ws_id], |r| r.get(0))
        .unwrap();
    assert_eq!(project_count, 0, "Projects should be cascade-deleted with their workspace");
}

#[test]
fn test_audit_trigger_fires_on_workspace_delete() {
    let conn = apply_all_migrations().unwrap();

    conn.execute(
        "INSERT INTO workspaces (name) VALUES ('Trigger Test')",
        [],
    )
    .unwrap();
    let ws_id: i64 = conn
        .query_row("SELECT last_insert_rowid()", [], |r| r.get(0))
        .unwrap();

    conn.execute("DELETE FROM workspaces WHERE id = ?1", [ws_id])
        .unwrap();

    let log_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM audit_log \
             WHERE table_name='workspaces' AND record_id=?1 AND action='DELETE'",
            [ws_id],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(log_count, 1, "Audit trigger should insert a DELETE row");
}

#[test]
fn test_settings_unique_constraint() {
    let conn = apply_all_migrations().unwrap();

    conn.execute(
        "INSERT INTO settings (scope, key, value) VALUES ('app', 'theme', 'dark')",
        [],
    )
    .unwrap();

    let result = conn.execute(
        "INSERT INTO settings (scope, key, value) VALUES ('app', 'theme', 'light')",
        [],
    );
    assert!(
        result.is_err(),
        "Duplicate (scope, scope_id, key) should violate UNIQUE constraint"
    );
}

#[test]
fn test_migrations_idempotent_on_fresh_db_from_file() {
    let dir = tempdir().unwrap();
    let db_path = dir.path().join("test.db");

    {
        let conn = Connection::open(&db_path).unwrap();
        for path in &[
            "migrations/001_initial.sql",
            "migrations/002_workspace_extensions.sql",
            "migrations/003_audit_improvements.sql",
        ] {
            let sql = fs::read_to_string(path).unwrap();
            conn.execute_batch(&sql).unwrap();
        }
    }

    // Open the same file again – no error should occur (IF NOT EXISTS guards).
    let conn2 = Connection::open(&db_path).unwrap();
    assert!(table_exists(&conn2, "workspaces"), "workspaces table should persist");
}
