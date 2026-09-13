import bcrypt from "bcryptjs";
import { SignJWT, jwtVerify } from "jose";
import type { NextRequest } from "next/server";

const JWT_SECRET = new TextEncoder().encode(
  process.env.JWT_SECRET || "integrio-dev-secret"
);

// ── Roles ────────────────────────────────────────────────────────────
// Integrio now recognizes exactly two roles. OWNER manages properties,
// bookings, financials, iCal sync and staff. BOOKER handles day-to-day
// booking/guest/property operations for an owner.
//
// Older data (and any request made before the DB migration below has
// run) may still carry legacy values — OWNER_ADMIN, CO_OWNER, ADMIN,
// owner, booker, AUDITOR, auditor, HOUSEKEEPING, housekeeping, STAFF.
// normalizeRole() maps all of those onto the current two roles so the
// app behaves correctly even against not-yet-migrated rows. See
// scripts/migrate-roles.sql for the one-time data migration.
export type Role = "OWNER" | "BOOKER";

const LEGACY_OWNER_ROLES = new Set([
  "owner",
  "OWNER",
  "OWNER_ADMIN",
  "CO_OWNER",
  "ADMIN",
  "AUDITOR",
  "auditor",
]);

const LEGACY_BOOKER_ROLES = new Set([
  "booker",
  "BOOKER",
  "STAFF",
  "HOUSEKEEPING",
  "housekeeping",
]);

// Collapses any legacy or not-yet-migrated role string onto OWNER/BOOKER.
// Unrecognized values fall back to BOOKER (least-privileged) rather than
// throwing, but that fallback should never be silently trusted for data
// migration — see scripts/migrate-roles.sql, which flags unmapped rows
// instead of guessing for the one-time DB fix.
export function normalizeRole(raw: string | null | undefined): Role {
  if (!raw) return "BOOKER";
  if (LEGACY_OWNER_ROLES.has(raw)) return "OWNER";
  if (LEGACY_BOOKER_ROLES.has(raw)) return "BOOKER";
  return "BOOKER";
}

// Which top-level routes are restricted to which role. A route not listed
// here is reachable by any authenticated user, regardless of role. Checked
// in middleware.ts (server-side) — this is the actual enforcement point,
// not just UI hiding.
export const ROUTE_ROLES: Record<string, Role[]> = {
  "/owner": ["OWNER"],
  "/auditor": ["OWNER"],
  "/dashboard/financials": ["OWNER"],
  "/dashboard/reports": ["OWNER"],
  "/dashboard/ical": ["OWNER"],
};

// Maps a role to its "home" route after login / when bounced from a
// route it isn't allowed to view. Single source of truth — imported by
// middleware.ts, login/page.tsx, change-password/page.tsx and
// settings/page.tsx instead of each keeping their own copy.
export function roleHomeRoute(role: string | null | undefined): string {
  return normalizeRole(role) === "OWNER" ? "/owner" : "/dashboard";
}

export async function hashPassword(password: string) {
  return bcrypt.hash(password, 12);
}

export async function verifyPassword(password: string, hashedPassword: string) {
  return bcrypt.compare(password, hashedPassword);
}

export interface TokenPayload {
  id: string;
  email: string;
  username?: string | null;
  name: string;
  role: string;
  // The org/owner this account's data is scoped to. For an OWNER this is
  // their own id; for a BOOKER it's the owner they were invited by.
  owner_id?: string | null;
  avatarColor?: string;
  mustChangePassword?: boolean;
}

export async function createToken(payload: TokenPayload) {
  return new SignJWT({ ...payload })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("7d")
    .sign(JWT_SECRET);
}

export async function verifyToken(token: string): Promise<TokenPayload | null> {
  try {
    const { payload } = await jwtVerify(token, JWT_SECRET);
    return payload as unknown as TokenPayload;
  } catch {
    return null;
  }
}

// Server-side helper for API routes: reads + verifies the httpOnly
// auth-token cookie and returns the authenticated user with a normalized
// role and resolved owner scope (own id for OWNER, owner_id for BOOKER).
// Returns null if there's no valid session — callers should respond 401.
export async function getAuthUser(
  req: NextRequest
): Promise<{ id: string; role: Role; ownerId: string } | null> {
  const token = req.cookies.get("auth-token")?.value;
  if (!token) return null;
  const payload = await verifyToken(token);
  if (!payload) return null;
  const role = normalizeRole(payload.role);
  const ownerId = role === "OWNER" ? payload.id : payload.owner_id || payload.id;
  return { id: payload.id, role, ownerId };
}

// ── Client-side helpers (browser only) ──────────────────────────────
// These read the cached user object that /login writes to localStorage
// after a successful sign-in. They do NOT re-verify the JWT — that only
// happens server-side (middleware.ts / API routes via verifyToken /
// getAuthUser above).

export interface IntegrioUser {
  id: string;
  email: string;
  username?: string | null;
  name: string;
  role: string;
  owner_id: string | null;
  avatarColor?: string;
  mustChangePassword?: boolean;
}

export function getCurrentUser(): IntegrioUser | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem("integrio_user");
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

export function requireRole(
  allowedRoles: string[],
  router: { push: (path: string) => void }
): IntegrioUser | null {
  const user = getCurrentUser();

  if (!user) {
    router.push("/login");
    return null;
  }

  const normalizedAllowed = allowedRoles.map((r) => normalizeRole(r));
  if (!normalizedAllowed.includes(normalizeRole(user.role))) {
    router.push(roleHomeRoute(user.role));
    return null;
  }

  return user;
}

// Properly ends the session: clears the httpOnly auth-token cookie via the
// server (client JS cannot delete an httpOnly cookie directly — a bare
// `document.cookie = "auth-token=; max-age=0"` silently no-ops), then
// clears the local user cache and redirects to login.
export async function logout() {
  try {
    await fetch("/api/auth/logout", { method: "POST" });
  } catch {
    // best-effort — still clear client-side state and redirect below
  }
  if (typeof window !== "undefined") {
    localStorage.removeItem("integrio_user");
    window.location.href = "/login";
  }
}
