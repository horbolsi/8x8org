import { Request, Response, NextFunction } from "express";
import { CONFIG, Role } from "../config.js";
import { verifyToken } from "../auth/jwt.js";

export type AuthedRequest = Request & {
  user?: { id: string; username: string; role: Role };
};

export function requireAuth(req: AuthedRequest, res: Response, next: NextFunction) {
  const token = req.cookies?.[CONFIG.COOKIE_NAME];
  if (!token) return res.status(401).json({ ok: false, error: "Not authenticated" });

  try {
    const payload = verifyToken(token);
    req.user = payload;
    next();
  } catch {
    return res.status(401).json({ ok: false, error: "Invalid session" });
  }
}

export function requireRole(role: Role) {
  return (req: AuthedRequest, res: Response, next: NextFunction) => {
    if (!req.user) return res.status(401).json({ ok: false, error: "Not authenticated" });
    if (req.user.role !== role) return res.status(403).json({ ok: false, error: "Forbidden" });
    next();
  };
}

export function requireConfirmHeader(req: Request, res: Response, next: NextFunction) {
  const ok = req.header("X-Confirm-Action") === "true";
  if (!ok) return res.status(400).json({ ok: false, error: "Missing X-Confirm-Action: true" });
  next();
}
