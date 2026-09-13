import { NextRequest, NextResponse } from "next/server";
import { verifyToken, normalizeRole, roleHomeRoute, ROUTE_ROLES } from "@/lib/auth";

const publicRoutes = [
  "/login",
  "/signup",
  "/forgot-password",
  "/reset-password",
  "/setup",
  "/verify",
  "/api/auth/login",
  "/api/ical",
  "/api/invite-employee",
  "/api/forgot-password",
  "/api/reset-password",
  "/api/cron",
  "/api/sync-ical",
  "/api/bot/availability",
  "/api/bot/parse-availability",
  "/api/bot/create-booking",
  "/api/bot/check-booking-status",
  "/api/housekeeping/login-log",
  "/api/housekeeping/schedule",
  "/api/housekeeping/checklist",
  "/api/owner/redflags",
  "/api/owner/checklist",
];

// Auth entry points that an already-authenticated user shouldn't have to
// see again — if their session cookie is still valid, send them straight
// to their dashboard instead of showing the login/signup form.
const authEntryRoutes = ["/login", "/signup"];

// ROUTE_ROLES keys are the new-style routes (e.g. /dashboard/financials).
// Some of your actual pages still live under different paths (e.g. the
// owner dashboard is /owner, not /dashboard/admin) — matched by longest
// prefix below so a more specific rule always wins over a shorter one.
function findRouteRule(pathname: string): string | null {
  const matches = Object.keys(ROUTE_ROLES).filter((route) =>
    pathname.startsWith(route)
  );
  if (matches.length === 0) return null;
  return matches.sort((a, b) => b.length - a.length)[0];
}

export async function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  const token = req.cookies.get("auth-token")?.value;
  const payload = token ? await verifyToken(token) : null;

  const isPublic = publicRoutes.some((route) => pathname.startsWith(route));

  // Already-authenticated user hitting /login or /signup: skip straight to
  // their dashboard instead of showing the form again.
  if (payload && authEntryRoutes.some((route) => pathname.startsWith(route))) {
    return NextResponse.redirect(new URL(roleHomeRoute(payload.role), req.url));
  }

  if (isPublic) {
    return NextResponse.next();
  }

  if (!token) {
    return NextResponse.redirect(new URL("/login", req.url));
  }

  if (!payload) {
    // Cookie present but invalid/expired — treat as logged out.
    const response = NextResponse.redirect(new URL("/login", req.url));
    response.cookies.delete("auth-token");
    return response;
  }

  const routeRule = findRouteRule(pathname);
  if (routeRule) {
    const allowedRoles = ROUTE_ROLES[routeRule];
    if (!allowedRoles.includes(normalizeRole(payload.role))) {
      // Authenticated, but not allowed on this route — bounce to their
      // own home instead of /login, since they ARE logged in.
      return NextResponse.redirect(new URL(roleHomeRoute(payload.role), req.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:png|jpg|jpeg|gif|svg|webp|ico)$).*)",
  ],
};
