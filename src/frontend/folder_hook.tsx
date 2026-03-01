/**
 * src/frontend/folder_hook.tsx
 *
 * React hook + example component demonstrating how to interact with the
 * ZQ AI Workstation SQLite database from a TypeScript/React frontend via
 * @tauri-apps/plugin-sql.
 *
 * Prerequisites (frontend package.json):
 *   npm install @tauri-apps/plugin-sql
 */

import { useEffect, useState, useCallback } from "react";
import Database from "@tauri-apps/plugin-sql";

// ─── Types ────────────────────────────────────────────────────────────────────

export interface Folder {
  id: number;
  project_id: number;
  parent_id: number | null;
  name: string;
  sort_order: number;
  created_at: string;
  updated_at: string;
}

export interface CreateFolderInput {
  project_id: number;
  parent_id?: number | null;
  name: string;
  sort_order?: number;
}

// ─── DB singleton ─────────────────────────────────────────────────────────────

const DB_URL = "sqlite:zq_workstation.db";
let _db: Database | null = null;

async function getDb(): Promise<Database> {
  if (!_db) {
    _db = await Database.load(DB_URL);
  }
  return _db;
}

// ─── Hook ─────────────────────────────────────────────────────────────────────

/**
 * useFolders
 *
 * Loads all folders for the given `projectId` and exposes helpers to create,
 * rename, and delete them.
 *
 * @example
 * const { folders, loading, error, createFolder, deleteFolder } =
 *   useFolders(projectId);
 */
export function useFolders(projectId: number) {
  const [folders, setFolders] = useState<Folder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // ── fetch ──────────────────────────────────────────────────────────────────

  const fetchFolders = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const db = await getDb();
      const rows = await db.select<Folder[]>(
        `SELECT id, project_id, parent_id, name, sort_order, created_at, updated_at
           FROM folders
          WHERE project_id = $1
          ORDER BY sort_order ASC, name ASC`,
        [projectId]
      );
      setFolders(rows);
    } catch (err) {
      setError(String(err));
    } finally {
      setLoading(false);
    }
  }, [projectId]);

  useEffect(() => {
    fetchFolders();
  }, [fetchFolders]);

  // ── create ─────────────────────────────────────────────────────────────────

  const createFolder = useCallback(
    async (input: CreateFolderInput): Promise<number | null> => {
      try {
        const db = await getDb();
        const result = await db.execute(
          `INSERT INTO folders (project_id, parent_id, name, sort_order)
           VALUES ($1, $2, $3, $4)`,
          [
            input.project_id,
            input.parent_id ?? null,
            input.name,
            input.sort_order ?? 0,
          ]
        );
        await fetchFolders();
        return result.lastInsertId ?? null;
      } catch (err) {
        setError(String(err));
        return null;
      }
    },
    [fetchFolders]
  );

  // ── rename ─────────────────────────────────────────────────────────────────

  const renameFolder = useCallback(
    async (id: number, newName: string): Promise<boolean> => {
      try {
        const db = await getDb();
        await db.execute(`UPDATE folders SET name = $1 WHERE id = $2`, [
          newName,
          id,
        ]);
        await fetchFolders();
        return true;
      } catch (err) {
        setError(String(err));
        return false;
      }
    },
    [fetchFolders]
  );

  // ── delete ─────────────────────────────────────────────────────────────────

  const deleteFolder = useCallback(
    async (id: number): Promise<boolean> => {
      try {
        const db = await getDb();
        await db.execute(`DELETE FROM folders WHERE id = $1`, [id]);
        await fetchFolders();
        return true;
      } catch (err) {
        setError(String(err));
        return false;
      }
    },
    [fetchFolders]
  );

  return { folders, loading, error, createFolder, renameFolder, deleteFolder, refresh: fetchFolders };
}

// ─── Example component ────────────────────────────────────────────────────────

interface FolderListProps {
  projectId: number;
}

/**
 * FolderList
 *
 * A minimal example component rendering folders for a project.
 * Replace the placeholder JSX with your actual UI components.
 */
export function FolderList({ projectId }: FolderListProps) {
  const { folders, loading, error, createFolder, deleteFolder } =
    useFolders(projectId);

  const handleCreate = async () => {
    const name = window.prompt("Folder name:");
    if (name?.trim()) {
      await createFolder({ project_id: projectId, name: name.trim() });
    }
  };

  if (loading) return <p>Loading folders…</p>;
  if (error) return <p style={{ color: "red" }}>Error: {error}</p>;

  return (
    <div>
      <button type="button" onClick={handleCreate}>
        + New folder
      </button>
      <ul>
        {folders.map((f) => (
          <li key={f.id}>
            {f.name}
            <button
              type="button"
              onClick={() => deleteFolder(f.id)}
              style={{ marginLeft: 8 }}
            >
              Delete
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
