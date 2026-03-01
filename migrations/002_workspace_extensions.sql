-- =============================================================================
-- Migration 002: Workspace Extensions
-- Adds richer workspace metadata, pinned items, and member tracking.
-- =============================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Add metadata columns to workspaces
-- (Each migration runs exactly once; no IF NOT EXISTS guard needed here.)
-- ---------------------------------------------------------------------------
ALTER TABLE workspaces ADD COLUMN sort_order    INTEGER NOT NULL DEFAULT 0;
ALTER TABLE workspaces ADD COLUMN last_opened   TEXT;
ALTER TABLE workspaces ADD COLUMN metadata_json TEXT NOT NULL DEFAULT '{}';

-- ---------------------------------------------------------------------------
-- workspace_members
-- Tracks named "personas" or profiles associated with a workspace.
-- (Useful when the app supports multiple user profiles or team exports.)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workspace_members (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    display_name TEXT    NOT NULL,
    avatar_url   TEXT,
    role         TEXT    NOT NULL DEFAULT 'owner'
                          CHECK (role IN ('owner', 'editor', 'viewer')),
    created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- pinned_items
-- Generic pinning: any entity type can be pinned to a workspace dashboard.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pinned_items (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    entity_type  TEXT    NOT NULL
                          CHECK (entity_type IN ('document', 'conversation', 'project', 'folder')),
    entity_id    INTEGER NOT NULL,
    sort_order   INTEGER NOT NULL DEFAULT 0,
    pinned_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    UNIQUE (workspace_id, entity_type, entity_id)
);

-- ---------------------------------------------------------------------------
-- workspace_tags  (many-to-many: workspace ↔ tag)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workspace_tags (
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    tag_id       INTEGER NOT NULL REFERENCES tags(id)       ON DELETE CASCADE,
    PRIMARY KEY (workspace_id, tag_id)
);

-- ---------------------------------------------------------------------------
-- project_templates
-- Reusable project scaffolds (folder hierarchy + default docs).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_templates (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id  INTEGER REFERENCES workspaces(id) ON DELETE CASCADE,
    name          TEXT    NOT NULL,
    description   TEXT,
    template_json TEXT    NOT NULL DEFAULT '{}',  -- serialised folder/doc tree
    created_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_workspace_members_workspace ON workspace_members(workspace_id);
CREATE INDEX IF NOT EXISTS idx_pinned_items_workspace      ON pinned_items(workspace_id);
