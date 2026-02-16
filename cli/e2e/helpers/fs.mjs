import { mkdtempSync, rmSync, readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/** Create a unique temp directory. Returns its absolute path. */
export function createTempDir() {
  return mkdtempSync(join(tmpdir(), "skill-e2e-"));
}

/** Remove a temp directory recursively. */
export function removeTempDir(dir) {
  rmSync(dir, { recursive: true, force: true });
}

/** Read a file as UTF-8 string. */
export function readFile(filePath) {
  return readFileSync(filePath, "utf-8");
}

/** Check if a path exists. */
export function fileExists(filePath) {
  return existsSync(filePath);
}

/** List entries in a directory (non-recursive). */
export function listDir(dirPath) {
  if (!existsSync(dirPath)) return [];
  return readdirSync(dirPath);
}

/** List all files in a directory recursively, returning relative paths. */
export function listFilesRecursive(dirPath) {
  const results = [];
  function walk(dir, prefix) {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      const rel = prefix ? `${prefix}/${entry}` : entry;
      if (statSync(full).isDirectory()) {
        walk(full, rel);
      } else {
        results.push(rel);
      }
    }
  }
  walk(dirPath, "");
  return results.sort();
}
