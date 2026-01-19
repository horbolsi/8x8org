import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import express from "express";
import { CONFIG } from "../config.js";
import { auditLog } from "../audit/logger.js";
import { resolveInWorkspace } from "../utils/pathSafe.js";
import { requireAuth, requireRole, AuthedRequest } from "../middleware/auth.js";

export const jobsRouter = express.Router();

type JobStep =
  | { type: "write_file"; path: string; content: string }
  | { type: "mkdir"; path: string }
  | { type: "run_cmd"; cmd: string; args?: string[] };

type Job = {
  id: string;
  createdAt: string;
  createdBy: any;
  status: "planned" | "approved" | "running" | "done" | "failed";
  steps: JobStep[];
  logs: string[];
  backups: { path: string; backup: string }[];
};

const JOBS_DIR = path.join(CONFIG.DB_DIR, "jobs");
fs.mkdirSync(JOBS_DIR, { recursive: true });

function jobPath(id: string) {
  return path.join(JOBS_DIR, `${id}.json`);
}

function loadJob(id: string): Job | null {
  const p = jobPath(id);
  if (!fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function saveJob(job: Job) {
  fs.writeFileSync(jobPath(job.id), JSON.stringify(job, null, 2));
}

jobsRouter.post("/plan", requireAuth, async (req: AuthedRequest, res) => {
  // In real use, AI should generate these steps.
  // Here we accept steps from the UI and store as "planned".
  const { steps } = req.body || {};
  if (!Array.isArray(steps) || steps.length === 0) return res.status(400).json({ ok: false, error: "Missing steps[]" });

  const id = "job_" + Date.now() + "_" + Math.random().toString(36).slice(2, 6);
  const job: Job = {
    id,
    createdAt: new Date().toISOString(),
    createdBy: req.user || null,
    status: "planned",
    steps,
    logs: [],
    backups: []
  };

  saveJob(job);
  auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "JOB_PLAN", target: id, ok: true, meta: { steps: steps.length } });

  return res.json({ ok: true, job });
});

jobsRouter.post("/approve", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { id } = req.body || {};
  const job = loadJob(id);
  if (!job) return res.status(404).json({ ok: false, error: "Job not found" });

  job.status = "approved";
  saveJob(job);

  auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "JOB_APPROVE", target: id, ok: true });
  return res.json({ ok: true, job });
});

async function runStep(job: Job, step: JobStep): Promise<void> {
  if (step.type === "mkdir") {
    const abs = resolveInWorkspace(step.path);
    fs.mkdirSync(abs, { recursive: true });
    job.logs.push(`[mkdir] ${step.path}`);
    return;
  }

  if (step.type === "write_file") {
    const abs = resolveInWorkspace(step.path);
    fs.mkdirSync(path.dirname(abs), { recursive: true });

    // backup if exists
    if (fs.existsSync(abs)) {
      const backup = abs + ".jobbak_" + job.id;
      fs.copyFileSync(abs, backup);
      job.backups.push({ path: step.path, backup });
    }

    fs.writeFileSync(abs, step.content, "utf8");
    job.logs.push(`[write_file] ${step.path} (${Buffer.byteLength(step.content, "utf8")} bytes)`);
    return;
  }

  if (step.type === "run_cmd") {
    const cmd = step.cmd;
    const args = (step.args || []).map(String);

    // HARD allowlist minimal for jobs
    const allowed = new Set(["npm", "node", "python", "python3", "git", "rg", "bash"]);
    if (!allowed.has(cmd)) throw new Error(`Job cmd not allowed: ${cmd}`);

    job.logs.push(`[run_cmd] ${cmd} ${args.join(" ")}`);

    await new Promise<void>((resolve, reject) => {
      const child = spawn(cmd, args, { cwd: CONFIG.WORKSPACE_ROOT, stdio: ["ignore", "pipe", "pipe"] });

      child.stdout.on("data", (d) => job.logs.push(d.toString()));
      child.stderr.on("data", (d) => job.logs.push(d.toString()));

      child.on("close", (code) => {
        if (code === 0) resolve();
        else reject(new Error(`${cmd} exited with code ${code}`));
      });
    });

    return;
  }
}

jobsRouter.post("/run", requireAuth, requireRole("admin"), async (req: AuthedRequest, res) => {
  const { id } = req.body || {};
  const job = loadJob(id);
  if (!job) return res.status(404).json({ ok: false, error: "Job not found" });
  if (job.status !== "approved") return res.status(400).json({ ok: false, error: "Job must be approved first" });

  job.status = "running";
  job.logs.push(`== Running job ${id} ==`);
  saveJob(job);

  try {
    for (const step of job.steps) {
      await runStep(job, step);
      saveJob(job);
    }
    job.status = "done";
    job.logs.push("== DONE ==");
    saveJob(job);

    auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "JOB_DONE", target: id, ok: true });
    return res.json({ ok: true, job });
  } catch (e: any) {
    job.status = "failed";
    job.logs.push("== FAILED ==");
    job.logs.push(String(e?.message || e));
    saveJob(job);

    auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "JOB_FAIL", target: id, ok: false, meta: { error: String(e) } });
    return res.status(500).json({ ok: false, error: String(e?.message || e), job });
  }
});

jobsRouter.post("/rollback", requireAuth, requireRole("admin"), async (req: AuthedRequest, res) => {
  const { id } = req.body || {};
  const job = loadJob(id);
  if (!job) return res.status(404).json({ ok: false, error: "Job not found" });

  job.logs.push("== ROLLBACK START ==");
  for (const b of job.backups) {
    try {
      const abs = resolveInWorkspace(b.path);
      if (fs.existsSync(b.backup)) {
        fs.copyFileSync(b.backup, abs);
        job.logs.push(`[rollback] restored ${b.path}`);
      }
    } catch (e: any) {
      job.logs.push(`[rollback] error ${b.path}: ${String(e)}`);
    }
  }
  job.logs.push("== ROLLBACK DONE ==");
  saveJob(job);

  auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "JOB_ROLLBACK", target: id, ok: true });

  return res.json({ ok: true, job });
});

jobsRouter.get("/:id", requireAuth, (req, res) => {
  const job = loadJob(req.params.id);
  if (!job) return res.status(404).json({ ok: false, error: "Not found" });
  return res.json({ ok: true, job });
});
