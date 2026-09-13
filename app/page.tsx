import { redirect } from "next/navigation";
import { cookies } from "next/headers";
import { verifyToken, roleHomeRoute } from "@/lib/auth";

export default async function Home() {
  const token = (await cookies()).get("auth-token")?.value;
  const payload = token ? await verifyToken(token) : null;

  redirect(payload ? roleHomeRoute(payload.role) : "/login");
}
