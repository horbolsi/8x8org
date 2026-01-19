import express from "express";
import { CONFIG } from "../config.js";
import { signToken } from "../auth/jwt.js";
import { hasAnyUsers, createUser, findUserByUsername, verifyPassword } from "../auth/users.js";
import { requireAuth, AuthedRequest } from "../middleware/auth.js";
import { auditLog } from "../audit/logger.js";

export const authRouter = express.Router();

// Bootstrap admin (first run only)
authRouter.post("/bootstrap-admin", async (req, res) => {
  if (hasAnyUsers()) return res.status(400).json({ ok: false, error: "Bootstrap already completed" });

  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ ok: false, error: "Missing username/password" });

  const user = await createUser(username, password, "admin");
  auditLog({ ts: new Date().toISOString(), user: null, action: "BOOTSTRAP_ADMIN", target: user.username, ok: true });

  return res.json({ ok: true, user: { id: user.id, username: user.username, role: user.role } });
});

authRouter.post("/login", async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ ok: false, error: "Missing username/password" });

  const user = findUserByUsername(username);
  if (!user) {
    auditLog({ ts: new Date().toISOString(), user: null, action: "LOGIN_FAIL", target: username, ok: false });
    return res.status(401).json({ ok: false, error: "Invalid credentials" });
  }

  const ok = await verifyPassword(user, password);
  if (!ok) {
    auditLog({ ts: new Date().toISOString(), user: null, action: "LOGIN_FAIL", target: username, ok: false });
    return res.status(401).json({ ok: false, error: "Invalid credentials" });
  }

  const token = signToken({ id: user.id, username: user.username, role: user.role });
  res.cookie(CONFIG.COOKIE_NAME, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: false
  });

  auditLog({ ts: new Date().toISOString(), user: { id: user.id, username: user.username, role: user.role }, action: "LOGIN_OK", ok: true });

  return res.json({ ok: true, user: { id: user.id, username: user.username, role: user.role } });
});

authRouter.post("/logout", (req, res) => {
  res.clearCookie(CONFIG.COOKIE_NAME);
  return res.json({ ok: true });
});

authRouter.get("/me", requireAuth, (req: AuthedRequest, res) => {
  return res.json({ ok: true, user: req.user });
});
