-- =============================================================================
-- Migration 001: Initial Core Schema
-- ZQ AI Workstation – foundational tables
-- =============================================================================

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- workspaces
-- Top-level containers that group related projects and conversations.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workspaces (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    description TEXT,
    color       TEXT    DEFAULT '#6366f1',   -- UI accent color (hex)
    icon        TEXT    DEFAULT 'folder',    -- icon identifier for the UI
    is_active   INTEGER NOT NULL DEFAULT 1,  -- 0 = archived
    created_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- projects
-- Projects live inside a workspace and contain folders/documents.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS projects (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name         TEXT    NOT NULL,
    description  TEXT,
    status       TEXT    NOT NULL DEFAULT 'active'
                         CHECK (status IN ('active', 'archived', 'completed')),
    created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- folders
-- Hierarchical folders within a project (self-referencing).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS folders (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    parent_id  INTEGER REFERENCES folders(id) ON DELETE CASCADE,
    name       TEXT    NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- documents
-- Files / notes stored within a folder.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS documents (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id   INTEGER REFERENCES folders(id) ON DELETE SET NULL,
    project_id  INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title       TEXT    NOT NULL,
    content     TEXT,                           -- raw text / markdown
    mime_type   TEXT    NOT NULL DEFAULT 'text/markdown',
    file_path   TEXT,                           -- optional path to an on-disk file
    size_bytes  INTEGER,
    checksum    TEXT,                           -- SHA-256 of content
    is_pinned   INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- ai_models
-- Registered AI model configurations (local or remote).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_models (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT    NOT NULL UNIQUE,
    provider     TEXT    NOT NULL DEFAULT 'local'
                          CHECK (provider IN ('local', 'openai', 'anthropic', 'ollama', 'custom')),
    model_id     TEXT    NOT NULL,              -- model identifier / slug
    endpoint     TEXT,                          -- API base URL (NULL for local)
    context_size INTEGER NOT NULL DEFAULT 4096,
    is_default   INTEGER NOT NULL DEFAULT 0,
    config_json  TEXT    NOT NULL DEFAULT '{}', -- extra provider-specific config
    created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- conversations
-- AI chat sessions; may be scoped to a workspace/project.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversations (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id INTEGER REFERENCES workspaces(id) ON DELETE SET NULL,
    project_id   INTEGER REFERENCES projects(id)  ON DELETE SET NULL,
    model_id     INTEGER REFERENCES ai_models(id)  ON DELETE SET NULL,
    title        TEXT    NOT NULL DEFAULT 'New conversation',
    system_prompt TEXT,
    temperature  REAL    NOT NULL DEFAULT 0.7
                          CHECK (temperature >= 0.0 AND temperature <= 2.0),
    max_tokens   INTEGER NOT NULL DEFAULT 2048,
    is_pinned    INTEGER NOT NULL DEFAULT 0,
    created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- messages
-- Individual turns within a conversation.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS messages (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role            TEXT    NOT NULL CHECK (role IN ('system', 'user', 'assistant', 'tool')),
    content         TEXT    NOT NULL,
    token_count     INTEGER,
    finish_reason   TEXT,                       -- 'stop', 'length', 'tool_calls', …
    metadata_json   TEXT    NOT NULL DEFAULT '{}',
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- tags
-- Reusable labels for cross-entity tagging.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tags (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    name  TEXT NOT NULL UNIQUE,
    color TEXT NOT NULL DEFAULT '#94a3b8'
);

-- ---------------------------------------------------------------------------
-- document_tags  (many-to-many)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS document_tags (
    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    tag_id      INTEGER NOT NULL REFERENCES tags(id)      ON DELETE CASCADE,
    PRIMARY KEY (document_id, tag_id)
);

-- ---------------------------------------------------------------------------
-- conversation_tags  (many-to-many)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversation_tags (
    conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    tag_id          INTEGER NOT NULL REFERENCES tags(id)           ON DELETE CASCADE,
    PRIMARY KEY (conversation_id, tag_id)
);

-- ---------------------------------------------------------------------------
-- settings
-- Key/value store for application and workspace-level configuration.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS settings (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    scope        TEXT    NOT NULL DEFAULT 'app'
                          CHECK (scope IN ('app', 'workspace', 'user')),
    scope_id     INTEGER,               -- NULL for app-wide, workspace_id otherwise
    key          TEXT    NOT NULL,
    value        TEXT    NOT NULL,
    value_type   TEXT    NOT NULL DEFAULT 'string'
                          CHECK (value_type IN ('string', 'number', 'boolean', 'json')),
    updated_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- NULL-safe unique index: COALESCE maps NULL scope_id to -1 so that
-- two app-wide rows with the same key are correctly rejected.
CREATE UNIQUE INDEX IF NOT EXISTS idx_settings_unique_scope_key
    ON settings(scope, COALESCE(scope_id, -1), key);

-- ---------------------------------------------------------------------------
-- audit_log
-- Append-only record of significant state changes.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name  TEXT    NOT NULL,
    record_id   INTEGER NOT NULL,
    action      TEXT    NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data    TEXT,                   -- JSON snapshot before change
    new_data    TEXT,                   -- JSON snapshot after change
    changed_by  TEXT    NOT NULL DEFAULT 'system',
    changed_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_projects_workspace     ON projects(workspace_id);
CREATE INDEX IF NOT EXISTS idx_folders_project        ON folders(project_id);
CREATE INDEX IF NOT EXISTS idx_folders_parent         ON folders(parent_id);
CREATE INDEX IF NOT EXISTS idx_documents_project      ON documents(project_id);
CREATE INDEX IF NOT EXISTS idx_documents_folder       ON documents(folder_id);
CREATE INDEX IF NOT EXISTS idx_conversations_workspace ON conversations(workspace_id);
CREATE INDEX IF NOT EXISTS idx_conversations_project  ON conversations(project_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation  ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_table_record ON audit_log(table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_settings_scope_key     ON settings(scope, scope_id, key);