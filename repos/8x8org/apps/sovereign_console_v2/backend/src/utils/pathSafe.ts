import path from "node:path";
import { CONFIG } from "../config.js";

export function resolveInWorkspace(userPath: string): string {
  // Normalize and ensure it stays inside WORKSPACE_ROOT
  const cleaned = userPath.replace(/\0/g, "");
  const abs = path.resolve(CONFIG.WORKSPACE_ROOT, cleaned);
  const root = CONFIG.WORKSPACE_ROOT;

  if (!abs.startsWith(root + path.sep) && abs !== root) {
    throw new Error("Path escapes workspace root");
  }
  return abs;
}

export function relFromWorkspace(absPath: string): string {
  const rel = path.relative(CONFIG.WORKSPACE_ROOT, absPath);
  return rel || ".";
}
