-- =============================================================================
-- Migration 003: Audit Improvements
-- Adds structured change-tracking triggers and a schema_migrations table.
-- =============================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- schema_migrations
-- Records which SQL migrations have been applied and when.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    version     TEXT NOT NULL PRIMARY KEY,
    description TEXT NOT NULL DEFAULT '',
    applied_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Record all three migrations now that the schema is complete.
INSERT OR IGNORE INTO schema_migrations (version, description) VALUES
    ('001', 'Initial core schema'),
    ('002', 'Workspace extensions'),
    ('003', 'Audit improvements');

-- ---------------------------------------------------------------------------
-- Enrich audit_log with session / actor context
-- (Each migration runs exactly once; no IF NOT EXISTS guard needed here.)
-- ---------------------------------------------------------------------------
ALTER TABLE audit_log ADD COLUMN session_id TEXT;
ALTER TABLE audit_log ADD COLUMN ip_address TEXT;

-- ---------------------------------------------------------------------------
-- Triggers: auto-populate audit_log on workspaces changes
-- ---------------------------------------------------------------------------
CREATE TRIGGER IF NOT EXISTS audit_workspaces_update
AFTER UPDATE ON workspaces
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_data, new_data)
    VALUES (
        'workspaces',
        OLD.id,
        'UPDATE',
        json_object(
            'id', OLD.id, 'name', OLD.name, 'is_active', OLD.is_active,
            'updated_at', OLD.updated_at
        ),
        json_object(
            'id', NEW.id, 'name', NEW.name, 'is_active', NEW.is_active,
            'updated_at', NEW.updated_at
        )
    );
END;

CREATE TRIGGER IF NOT EXISTS audit_workspaces_delete
AFTER DELETE ON workspaces
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_data)
    VALUES (
        'workspaces',
        OLD.id,
        'DELETE',
        json_object(
            'id', OLD.id, 'name', OLD.name, 'is_active', OLD.is_active
        )
    );
END;

-- ---------------------------------------------------------------------------
-- Triggers: auto-populate audit_log on projects changes
-- ---------------------------------------------------------------------------
CREATE TRIGGER IF NOT EXISTS audit_projects_update
AFTER UPDATE ON projects
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_data, new_data)
    VALUES (
        'projects',
        OLD.id,
        'UPDATE',
        json_object(
            'id', OLD.id, 'name', OLD.name, 'status', OLD.status,
            'workspace_id', OLD.workspace_id
        ),
        json_object(
            'id', NEW.id, 'name', NEW.name, 'status', NEW.status,
            'workspace_id', NEW.workspace_id
        )
    );
END;

CREATE TRIGGER IF NOT EXISTS audit_projects_delete
AFTER DELETE ON projects
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_data)
    VALUES (
        'projects',
        OLD.id,
        'DELETE',
        json_object(
            'id', OLD.id, 'name', OLD.name, 'status', OLD.status,
            'workspace_id', OLD.workspace_id
        )
    );
END;

-- ---------------------------------------------------------------------------
-- Triggers: auto-populate audit_log on documents changes
-- ---------------------------------------------------------------------------
CREATE TRIGGER IF NOT EXISTS audit_documents_update
AFTER UPDATE ON documents
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_data, new_data)
    VALUES (
        'documents',
        OLD.id,
        'UPDATE',
        json_object(
            'id', OLD.id, 'title', OLD.title, 'project_id', OLD.project_id,
            'folder_id', OLD.folder_id, 'updated_at', OLD.updated_at
        ),
        json_object(
            'id', NEW.id, 'title', NEW.title, 'project_id', NEW.project_id,
            'folder_id', NEW.folder_id, 'updated_at', NEW.updated_at
        )
    );
END;

CREATE TRIGGER IF NOT EXISTS audit_documents_delete
AFTER DELETE ON documents
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_data)
    VALUES (
        'documents',
        OLD.id,
        'DELETE',
        json_object(
            'id', OLD.id, 'title', OLD.title, 'project_id', OLD.project_id
        )
    );
END;

-- ---------------------------------------------------------------------------
-- Triggers: auto-update `updated_at` on workspaces / projects / documents
-- ---------------------------------------------------------------------------
CREATE TRIGGER IF NOT EXISTS trig_workspaces_updated_at
AFTER UPDATE ON workspaces
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE workspaces
    SET    updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE  id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trig_projects_updated_at
AFTER UPDATE ON projects
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE projects
    SET    updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE  id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trig_documents_updated_at
AFTER UPDATE ON documents
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE documents
    SET    updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE  id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trig_conversations_updated_at
AFTER UPDATE ON conversations
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE conversations
    SET    updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    WHERE  id = NEW.id;
END;
