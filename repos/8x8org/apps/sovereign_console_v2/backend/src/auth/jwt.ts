import jwt from "jsonwebtoken";
import { CONFIG, Role } from "../config.js";

export type TokenPayload = {
  id: string;
  username: string;
  role: Role;
};

export function signToken(payload: TokenPayload): string {
  return jwt.sign(payload, CONFIG.JWT_SECRET, { expiresIn: "7d" });
}

export function verifyToken(token: string): TokenPayload {
  return jwt.verify(token, CONFIG.JWT_SECRET) as TokenPayload;
}
