# ZQ AI Workstation

A production-grade, extensible AI workstation built with **Tauri v2 + Rust + React/TypeScript**.  
This document covers the database layer: schema design, migrations, integration, security, and how to extend the system.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Database Overview](#database-overview)
5. [Schema Reference](#schema-reference)
6. [Migrations](#migrations)
7. [Rust Backend Integration](#rust-backend-integration)
8. [React / TypeScript Frontend Integration](#react--typescript-frontend-integration)
9. [Testing](#testing)
10. [Security](#security)
11. [Backups](#backups)
12. [Extending the Schema](#extending-the-schema)
13. [Best Practices](#best-practices)

---

## Project Structure

```
ZQ_AI_Workstation/
├── Cargo.toml                        # Rust package manifest
├── tauri.conf.json                   # Tauri v2 configuration
├── migrations/
│   ├── 001_initial.sql               # Core schema (tables, indexes)
│   ├── 002_workspace_extensions.sql  # Workspace richness (members, pins, templates)
│   └── 003_audit_improvements.sql    # Audit triggers, updated_at triggers, schema_migrations
├── src/
│   ├── main.rs                       # Tauri entry point (migrations wired at startup)
│   ├── lib.rs                        # Migration definitions (shared with tests)
│   ├── tests/
│   │   └── test_migrations.rs        # Integration tests for the database schema
│   └── frontend/
│       └── folder_hook.tsx           # Example React hook for folder CRUD
└── README.md
```

---

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Rust | 1.77 |
| Node.js | 20 LTS |
| Tauri CLI | 2.x (`cargo install tauri-cli --version "^2"`) |
| SQLite | bundled via `rusqlite` (no system install needed) |

---

## Quick Start

```bash
# 1. Install Rust dependencies
cargo build

# 2. Install frontend dependencies (adjust to your package manager)
npm install

# 3. Run in development mode (opens the desktop window + hot reload)
cargo tauri dev

# 4. Build for production
cargo tauri build
```

The SQLite database (`zq_workstation.db`) is created and fully migrated automatically on first launch inside the Tauri app-data directory.

---

## Database Overview

| Aspect | Detail |
|--------|--------|
| Engine | SQLite 3 (bundled) |
| Path | `{app_data}/zq_workstation.db` |
| WAL mode | Enabled in migration 001 for safe concurrent reads |
| Foreign keys | Enforced (`PRAGMA foreign_keys = ON`) |
| Timestamps | All stored as ISO-8601 UTC strings (`YYYY-MM-DDTHH:MM:SSZ`) |

---

## Schema Reference

### Core Tables (migration 001)

#### `workspaces`
Top-level containers grouping projects and conversations.

| Column | Type | Notes |
|--------|------|-------|
| `id` | INTEGER PK | Auto-increment |
| `name` | TEXT | Required |
| `description` | TEXT | Optional |
| `color` | TEXT | Hex accent color, default `#6366f1` |
| `icon` | TEXT | UI icon identifier |
| `is_active` | INTEGER | `1` = active, `0` = archived |
| `created_at` | TEXT | ISO-8601 UTC |
| `updated_at` | TEXT | ISO-8601 UTC, auto-updated via trigger |

#### `projects`
Projects live inside a workspace.

| Column | Type | Notes |
|--------|------|-------|
| `id` | INTEGER PK | |
| `workspace_id` | INTEGER FK | → `workspaces.id` (CASCADE DELETE) |
| `name` | TEXT | |
| `status` | TEXT | `active` \| `archived` \| `completed` |

#### `folders`
Hierarchical folder tree within a project (self-referencing).

#### `documents`
Files or notes stored within a folder; can hold inline `content` (Markdown/plain text) or reference an on-disk `file_path`.

#### `ai_models`
Registry of AI model configurations. Provider values: `local`, `openai`, `anthropic`, `ollama`, `custom`.

#### `conversations`
AI chat sessions, optionally scoped to a workspace/project and a specific model.

#### `messages`
Individual turns within a conversation. Roles: `system`, `user`, `assistant`, `tool`.

#### `tags` / `document_tags` / `conversation_tags`
Reusable label system with many-to-many join tables.

#### `settings`
Key/value store for `app`, `workspace`, or `user`-scoped configuration.

#### `audit_log`
Append-only change record (table name, record id, action, before/after JSON snapshots).

### Extension Tables (migration 002)

| Table | Purpose |
|-------|---------|
| `workspace_members` | Named personas/profiles per workspace |
| `pinned_items` | Generic pinning of any entity to a workspace dashboard |
| `workspace_tags` | Tag assignments to workspaces |
| `project_templates` | Reusable project scaffolds (serialised folder/doc tree) |

Additional columns on `workspaces`: `sort_order`, `last_opened`, `metadata_json`.

### Audit Infrastructure (migration 003)

| Object | Type | Purpose |
|--------|------|---------|
| `schema_migrations` | Table | Version tracking for applied migrations |
| `audit_*_update/delete` | Triggers | Fire on UPDATE/DELETE of workspaces, projects, documents |
| `trig_*_updated_at` | Triggers | Auto-set `updated_at` when a row changes |

---

## Migrations

Migrations are plain SQL files numbered sequentially. They are **embedded** at compile-time via `include_str!` in `src/lib.rs` and applied automatically by `tauri-plugin-sql` on startup.

### Adding a new migration

1. Create `migrations/004_my_feature.sql` with your DDL (always use `IF NOT EXISTS` / `IF NOT EXISTS` guards).
2. Add an entry to `db_migrations()` in `src/lib.rs`:
   ```rust
   Migration {
       version:     4,
       description: "my_feature",
       sql:         include_str!("../migrations/004_my_feature.sql"),
       kind:        MigrationKind::Up,
   },
   ```
3. Insert a row into `schema_migrations` at the end of the SQL file:
   ```sql
   INSERT OR IGNORE INTO schema_migrations (version, description)
   VALUES ('004', 'My feature description');
   ```
4. Add a test case in `src/tests/test_migrations.rs`.

### Migration guarantees

- `CREATE TABLE IF NOT EXISTS` makes every `CREATE TABLE` statement re-entrant.
- `ALTER TABLE … ADD COLUMN` statements do **not** support `IF NOT EXISTS` in SQLite; they are safe because `tauri-plugin-sql` tracks applied migration versions and never re-applies a completed migration.

---

## Rust Backend Integration

```toml
# Cargo.toml
[dependencies]
tauri            = { version = "2" }
tauri-plugin-sql = { version = "2", features = ["sqlite"] }
```

```rust
// src/main.rs
use zq_ai_workstation_lib::db_migrations;

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
```

The `db_migrations()` function in `src/lib.rs` returns an ordered `Vec<Migration>`. Extend it whenever you add a new SQL file.

---

## React / TypeScript Frontend Integration

### Install the plugin

```bash
npm install @tauri-apps/plugin-sql
```

### Load the database

```typescript
import Database from "@tauri-apps/plugin-sql";

const db = await Database.load("sqlite:zq_workstation.db");
```

### Query example

```typescript
const workspaces = await db.select<{ id: number; name: string }[]>(
  "SELECT id, name FROM workspaces WHERE is_active = 1 ORDER BY sort_order"
);
```

### Execute example

```typescript
await db.execute(
  "INSERT INTO workspaces (name, color) VALUES ($1, $2)",
  ["My Workspace", "#f43f5e"]
);
```

### useFolders hook

See [`src/frontend/folder_hook.tsx`](src/frontend/folder_hook.tsx) for a complete example of a React hook that loads, creates, renames, and deletes folders with proper loading and error states.

```tsx
import { useFolders, FolderList } from "./folder_hook";

function ProjectView({ projectId }: { projectId: number }) {
  return <FolderList projectId={projectId} />;
}
```

---

## Testing

Tests use `rusqlite` (with the bundled SQLite feature) and `tempfile` so they run fully offline without a running Tauri instance.

```bash
# Run all migration integration tests
# (--no-default-features skips Tauri system libs — works in headless CI/dev environments)
cargo test --test test_migrations --no-default-features

# Run a specific test
cargo test --test test_migrations --no-default-features -- test_audit_trigger_fires_on_workspace_delete
```

The test suite (`src/tests/test_migrations.rs`) verifies:

- All migrations apply without error (fresh in-memory DB)
- Every required table exists after migration
- Every audit trigger exists
- Every core index exists
- `schema_migrations` contains exactly 3 rows
- INSERT + CASCADE DELETE works correctly
- Audit trigger fires on workspace delete
- Settings UNIQUE constraint is enforced
- Migrations are idempotent on a file-based DB

---

## Security

| Concern | Mitigation |
|---------|-----------|
| **SQL injection** | Always use parameterised queries (`$1`, `$2`, …). Never interpolate user input into SQL strings. |
| **Foreign keys** | `PRAGMA foreign_keys = ON` is set in every migration; prevents orphaned records. |
| **WAL mode** | Enables safe concurrent readers and crash-safe writes. |
| **Database path** | Stored in the OS app-data directory (e.g., `%APPDATA%` on Windows, `~/.local/share` on Linux). Users cannot easily tamper with it. |
| **API key storage** | Do **not** store secrets in the `settings` table in plaintext. Use Tauri's `stronghold` plugin or the OS keychain. |
| **CSP** | `tauri.conf.json` sets a strict Content-Security-Policy; review before enabling external script sources. |
| **Audit log** | The `audit_log` table is append-only by convention; grant `DELETE` privilege only to maintenance operations. |

---

## Backups

SQLite databases are single files — backups are straightforward:

```bash
# Hot backup using the SQLite Online Backup API (safe while the app is running)
sqlite3 zq_workstation.db ".backup /path/to/backup/zq_workstation_$(date +%Y%m%d).db"

# Or simply copy the file when the app is closed
cp zq_workstation.db /path/to/backup/
```

For automated backups, consider:
- Scheduling a daily backup via cron / Task Scheduler.
- Implementing a Tauri command that calls the SQLite backup API on a timer.
- Syncing the backup file to cloud storage (S3, Backblaze B2, etc.).

---

## Extending the Schema

1. **New entity type** – add a table in a new `migrations/00N_*.sql`, reference `workspaces` or `projects` with `ON DELETE CASCADE`.
2. **Many-to-many** – follow the `document_tags` / `conversation_tags` pattern (composite PK join table).
3. **Soft deletes** – add an `is_deleted INTEGER NOT NULL DEFAULT 0` column and a partial index: `CREATE INDEX … WHERE is_deleted = 0`.
4. **Full-text search** – create an FTS5 virtual table: `CREATE VIRTUAL TABLE documents_fts USING fts5(title, content, content=documents, content_rowid=id);`
5. **Versioned documents** – add a `document_versions` table with `document_id`, `version`, `content`, `created_at`.

---

## Best Practices

- Keep migrations **forward-only** and never edit an already-applied migration file.
- Use `INSERT OR IGNORE` / `INSERT OR REPLACE` when idempotency is required.
- Prefer ISO-8601 UTC strings for all timestamps to avoid timezone bugs.
- Use `EXPLAIN QUERY PLAN` in development to verify index usage on hot queries.
- Keep `config_json` / `metadata_json` blobs small; extract frequently-queried fields into real columns.
- Use transactions (`BEGIN` / `COMMIT`) for multi-step writes to maintain atomicity.
