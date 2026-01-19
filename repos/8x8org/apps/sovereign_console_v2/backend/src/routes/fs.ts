import fs from "node:fs";
import path from "node:path";
import express from "express";
import multer from "multer";
import archiver from "archiver";
import unzipper from "unzipper";

import { CONFIG } from "../config.js";
import { auditLog } from "../audit/logger.js";
import { resolveInWorkspace, relFromWorkspace } from "../utils/pathSafe.js";
import { requireAuth, requireRole, requireConfirmHeader, AuthedRequest } from "../middleware/auth.js";

export const fsRouter = express.Router();

function statSafe(p: string) {
  try { return fs.statSync(p); } catch { return null; }
}

function listTree(absDir: string, depth: number): any {
  const st = statSafe(absDir);
  if (!st) return null;

  const node: any = {
    name: path.basename(absDir),
    path: relFromWorkspace(absDir),
    type: st.isDirectory() ? "dir" : "file",
    size: st.isFile() ? st.size : 0,
    mtime: st.mtime.toISOString()
  };

  if (st.isDirectory() && depth > 0) {
    const items = fs.readdirSync(absDir).sort();
    node.children = items.map((name) => {
      const childAbs = path.join(absDir, name);
      return listTree(childAbs, depth - 1);
    }).filter(Boolean);
  }

  return node;
}

// GET tree
fsRouter.get("/tree", requireAuth, (req: AuthedRequest, res) => {
  const p = String(req.query.path || ".");
  const depth = Math.min(Number(req.query.depth || "4"), 8);
  const abs = resolveInWorkspace(p);

  const node = listTree(abs, depth);
  if (!node) return res.status(404).json({ ok: false, error: "Not found" });
  return res.json({ ok: true, root: node });
});

// GET read
fsRouter.get("/read", requireAuth, (req: AuthedRequest, res) => {
  const p = String(req.query.path || "");
  if (!p) return res.status(400).json({ ok: false, error: "Missing path" });

  const abs = resolveInWorkspace(p);
  const st = statSafe(abs);
  if (!st || !st.isFile()) return res.status(404).json({ ok: false, error: "File not found" });

  if (st.size > CONFIG.MAX_FILE_BYTES * 5) {
    return res.status(413).json({ ok: false, error: "File too large to read in UI" });
  }

  const content = fs.readFileSync(abs, "utf8");
  return res.json({ ok: true, path: p, bytes: st.size, content });
});

// POST write (admin)
fsRouter.post("/write", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { path: p, content } = req.body || {};
  if (!p || typeof p !== "string") return res.status(400).json({ ok: false, error: "Missing path" });
  if (typeof content !== "string") return res.status(400).json({ ok: false, error: "Missing content" });

  const abs = resolveInWorkspace(p);
  const bytes = Buffer.byteLength(content, "utf8");
  if (bytes > CONFIG.MAX_FILE_BYTES) return res.status(413).json({ ok: false, error: "Too large" });

  fs.mkdirSync(path.dirname(abs), { recursive: true });

  // backup
  const bak = abs + ".bak_" + Date.now();
  if (fs.existsSync(abs)) fs.copyFileSync(abs, bak);

  fs.writeFileSync(abs, content, "utf8");

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FILE_WRITE",
    target: p,
    ok: true,
    meta: { bytes, backup: relFromWorkspace(bak) }
  });

  return res.json({ ok: true, path: p, bytes });
});

// POST create file (admin)
fsRouter.post("/create", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { path: p } = req.body || {};
  if (!p || typeof p !== "string") return res.status(400).json({ ok: false, error: "Missing path" });

  const abs = resolveInWorkspace(p);
  if (fs.existsSync(abs)) return res.status(400).json({ ok: false, error: "Already exists" });

  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, "", "utf8");

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FILE_CREATE",
    target: p,
    ok: true
  });

  return res.json({ ok: true, path: p });
});

// POST mkdir (admin)
fsRouter.post("/mkdir", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { path: p } = req.body || {};
  if (!p || typeof p !== "string") return res.status(400).json({ ok: false, error: "Missing path" });

  const abs = resolveInWorkspace(p);
  fs.mkdirSync(abs, { recursive: true });

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "DIR_CREATE",
    target: p,
    ok: true
  });

  return res.json({ ok: true, path: p });
});

// POST rename (admin)
fsRouter.post("/rename", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { from, to } = req.body || {};
  if (!from || !to) return res.status(400).json({ ok: false, error: "Missing from/to" });

  const absFrom = resolveInWorkspace(from);
  const absTo = resolveInWorkspace(to);

  fs.mkdirSync(path.dirname(absTo), { recursive: true });
  fs.renameSync(absFrom, absTo);

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FS_RENAME",
    target: `${from} -> ${to}`,
    ok: true
  });

  return res.json({ ok: true });
});

// POST copy (admin)
fsRouter.post("/copy", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { from, to } = req.body || {};
  if (!from || !to) return res.status(400).json({ ok: false, error: "Missing from/to" });

  const absFrom = resolveInWorkspace(from);
  const absTo = resolveInWorkspace(to);
  const st = statSafe(absFrom);
  if (!st) return res.status(404).json({ ok: false, error: "Source missing" });

  fs.mkdirSync(path.dirname(absTo), { recursive: true });
  if (st.isFile()) {
    fs.copyFileSync(absFrom, absTo);
  } else {
    // directory copy (simple recursive)
    const copyDir = (src: string, dst: string) => {
      fs.mkdirSync(dst, { recursive: true });
      for (const item of fs.readdirSync(src)) {
        const s = path.join(src, item);
        const d = path.join(dst, item);
        const sst = fs.statSync(s);
        if (sst.isDirectory()) copyDir(s, d);
        else fs.copyFileSync(s, d);
      }
    };
    copyDir(absFrom, absTo);
  }

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FS_COPY",
    target: `${from} -> ${to}`,
    ok: true
  });

  return res.json({ ok: true });
});

// POST delete (admin + confirm)
fsRouter.post("/delete", requireAuth, requireRole("admin"), requireConfirmHeader, (req: AuthedRequest, res) => {
  const { path: p } = req.body || {};
  if (!p || typeof p !== "string") return res.status(400).json({ ok: false, error: "Missing path" });

  const abs = resolveInWorkspace(p);
  if (!fs.existsSync(abs)) return res.status(404).json({ ok: false, error: "Not found" });

  const trashDir = path.join(CONFIG.RUNTIME_ROOT, "trash");
  fs.mkdirSync(trashDir, { recursive: true });

  const base = path.basename(abs);
  const moved = path.join(trashDir, base + ".deleted_" + Date.now());
  fs.renameSync(abs, moved);

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FS_DELETE",
    target: p,
    ok: true,
    meta: { movedTo: relFromWorkspace(moved) }
  });

  return res.json({ ok: true, movedTo: moved });
});

// Upload (admin)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: CONFIG.MAX_UPLOAD_BYTES }
});

fsRouter.post("/upload", requireAuth, requireRole("admin"), upload.single("file"), (req: AuthedRequest, res) => {
  const targetDir = String(req.query.dir || ".");
  if (!req.file) return res.status(400).json({ ok: false, error: "No file" });

  const absDir = resolveInWorkspace(targetDir);
  fs.mkdirSync(absDir, { recursive: true });

  const safeName = req.file.originalname.replace(/[^\w.\-()+ ]/g, "_");
  const dest = path.join(absDir, safeName);

  fs.writeFileSync(dest, req.file.buffer);

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FS_UPLOAD",
    target: path.join(targetDir, safeName),
    ok: true,
    meta: { bytes: req.file.size }
  });

  return res.json({ ok: true, path: path.join(targetDir, safeName), bytes: req.file.size });
});

// Download
fsRouter.get("/download", requireAuth, (req: AuthedRequest, res) => {
  const p = String(req.query.path || "");
  if (!p) return res.status(400).json({ ok: false, error: "Missing path" });

  const abs = resolveInWorkspace(p);
  const st = statSafe(abs);
  if (!st || !st.isFile()) return res.status(404).json({ ok: false, error: "Not found" });

  res.setHeader("Content-Disposition", `attachment; filename="${path.basename(abs)}"`);
  res.setHeader("Content-Type", "application/octet-stream");
  fs.createReadStream(abs).pipe(res);
});

// Zip (admin)
fsRouter.post("/zip", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { path: p, out } = req.body || {};
  if (!p || !out) return res.status(400).json({ ok: false, error: "Missing path/out" });

  const absSrc = resolveInWorkspace(p);
  const absOut = resolveInWorkspace(out);

  const st = statSafe(absSrc);
  if (!st) return res.status(404).json({ ok: false, error: "Source not found" });

  fs.mkdirSync(path.dirname(absOut), { recursive: true });

  const output = fs.createWriteStream(absOut);
  const archive = archiver("zip", { zlib: { level: 9 } });

  output.on("close", () => {
    auditLog({
      ts: new Date().toISOString(),
      user: req.user || null,
      action: "FS_ZIP",
      target: `${p} -> ${out}`,
      ok: true,
      meta: { bytes: archive.pointer() }
    });
    res.json({ ok: true, out, bytes: archive.pointer() });
  });

  archive.on("error", (err) => res.status(500).json({ ok: false, error: String(err) }));

  archive.pipe(output);
  if (st.isDirectory()) archive.directory(absSrc, false);
  else archive.file(absSrc, { name: path.basename(absSrc) });
  archive.finalize().catch(() => {});
});

// Unzip (admin)
fsRouter.post("/unzip", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { zipPath, outDir } = req.body || {};
  if (!zipPath || !outDir) return res.status(400).json({ ok: false, error: "Missing zipPath/outDir" });

  const absZip = resolveInWorkspace(zipPath);
  const absOut = resolveInWorkspace(outDir);

  if (!fs.existsSync(absZip)) return res.status(404).json({ ok: false, error: "Zip not found" });
  fs.mkdirSync(absOut, { recursive: true });

  fs.createReadStream(absZip)
    .pipe(unzipper.Extract({ path: absOut }))
    .on("close", () => {
      auditLog({
        ts: new Date().toISOString(),
        user: req.user || null,
        action: "FS_UNZIP",
        target: `${zipPath} -> ${outDir}`,
        ok: true
      });
      res.json({ ok: true });
    })
    .on("error", (e: any) => res.status(500).json({ ok: false, error: String(e) }));
});
