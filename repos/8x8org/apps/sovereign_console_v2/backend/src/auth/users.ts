import fs from "node:fs";
import path from "node:path";
import bcrypt from "bcryptjs";
import { CONFIG, Role } from "../config.js";

export type User = {
  id: string;
  username: string;
  passHash: string;
  role: Role;
  createdAt: string;
};

const USERS_FILE = path.join(CONFIG.DB_DIR, "users.json");

function ensureDB() {
  fs.mkdirSync(CONFIG.DB_DIR, { recursive: true });
  if (!fs.existsSync(USERS_FILE)) fs.writeFileSync(USERS_FILE, JSON.stringify({ users: [] }, null, 2));
}

export function loadUsers(): User[] {
  ensureDB();
  const raw = fs.readFileSync(USERS_FILE, "utf8");
  const data = JSON.parse(raw);
  return data.users || [];
}

export function saveUsers(users: User[]) {
  ensureDB();
  fs.writeFileSync(USERS_FILE, JSON.stringify({ users }, null, 2));
}

export function hasAnyUsers(): boolean {
  return loadUsers().length > 0;
}

export function findUserByUsername(username: string): User | undefined {
  return loadUsers().find(u => u.username.toLowerCase() === username.toLowerCase());
}

export function findUserById(id: string): User | undefined {
  return loadUsers().find(u => u.id === id);
}

export async function createUser(username: string, password: string, role: Role): Promise<User> {
  const users = loadUsers();
  const exists = users.find(u => u.username.toLowerCase() === username.toLowerCase());
  if (exists) throw new Error("Username already exists");

  const id = "u_" + Math.random().toString(36).slice(2, 10);
  const passHash = await bcrypt.hash(password, 10);

  const user: User = {
    id,
    username,
    passHash,
    role,
    createdAt: new Date().toISOString()
  };

  users.push(user);
  saveUsers(users);
  return user;
}

export async function verifyPassword(user: User, password: string): Promise<boolean> {
  return bcrypt.compare(password, user.passHash);
}
