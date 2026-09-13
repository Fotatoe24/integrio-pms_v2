// app/api/owner/checklist/route.ts
import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase-server";
import { getAuthUser } from "@/lib/auth";

export async function GET(req: NextRequest) {
  const ownerId = req.nextUrl.searchParams.get("owner_id");
  if (!ownerId) {
    return NextResponse.json({ error: "Missing owner_id" }, { status: 400 });
  }

  const auth = await getAuthUser(req);
  if (!auth || auth.role !== "OWNER" || auth.id !== ownerId) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { data } = await supabaseAdmin
    .from("Checklist")
    .select("*, ChecklistItem(*)")
    .eq("owner_id", ownerId)
    .eq("is_active", true)
    .order("createdAt", { ascending: false });
  return NextResponse.json({ checklists: data || [] });
}

export async function POST(req: NextRequest) {
  // { owner_id, title, items: string[] }
  const { owner_id, title, items } = await req.json();
  if (!owner_id) {
    return NextResponse.json({ error: "Missing owner_id" }, { status: 400 });
  }

  const auth = await getAuthUser(req);
  if (!auth || auth.role !== "OWNER" || auth.id !== owner_id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { data: checklist, error } = await supabaseAdmin
    .from("Checklist")
    .insert({ owner_id, title })
    .select()
    .single();
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });

  const rows = items.map((label: string, i: number) => ({
    checklistId: checklist.id,
    label,
    sort_order: i,
  }));
  if (rows.length) await supabaseAdmin.from("ChecklistItem").insert(rows);

  return NextResponse.json(checklist);
}

export async function PUT(req: NextRequest) {
  // { id, title?, items?: string[] } items replaces the full item list
  const { id, title, items } = await req.json();
  if (!id) {
    return NextResponse.json({ error: "Missing id" }, { status: 400 });
  }

  const auth = await getAuthUser(req);
  const { data: checklist } = await supabaseAdmin
    .from("Checklist")
    .select("id, owner_id")
    .eq("id", id)
    .maybeSingle();

  if (!auth || auth.role !== "OWNER" || !checklist || checklist.owner_id !== auth.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  if (title)
    await supabaseAdmin
      .from("Checklist")
      .update({ title, updatedAt: new Date().toISOString() })
      .eq("id", id);
  if (items) {
    await supabaseAdmin.from("ChecklistItem").delete().eq("checklistId", id);
    const rows = items.map((label: string, i: number) => ({
      checklistId: id,
      label,
      sort_order: i,
    }));
    if (rows.length) await supabaseAdmin.from("ChecklistItem").insert(rows);
  }
  return NextResponse.json({ ok: true });
}

export async function DELETE(req: NextRequest) {
  const id = req.nextUrl.searchParams.get("id");
  if (!id) {
    return NextResponse.json({ error: "Missing id" }, { status: 400 });
  }

  const auth = await getAuthUser(req);
  const { data: checklist } = await supabaseAdmin
    .from("Checklist")
    .select("id, owner_id")
    .eq("id", id)
    .maybeSingle();

  if (!auth || auth.role !== "OWNER" || !checklist || checklist.owner_id !== auth.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  await supabaseAdmin
    .from("Checklist")
    .update({ is_active: false })
    .eq("id", id);
  return NextResponse.json({ ok: true });
}
