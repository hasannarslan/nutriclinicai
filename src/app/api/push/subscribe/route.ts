import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) return NextResponse.json({ error: "Oturum gerekli." }, { status: 401 });

    const payload = await request.json().catch(() => null) as {
      endpoint?: unknown;
      keys?: { p256dh?: unknown; auth?: unknown };
      userAgent?: unknown;
    } | null;
    const endpoint = typeof payload?.endpoint === "string" ? payload.endpoint.trim() : "";
    const p256dh = typeof payload?.keys?.p256dh === "string" ? payload.keys.p256dh.trim() : "";
    const authKey = typeof payload?.keys?.auth === "string" ? payload.keys.auth.trim() : "";
    const userAgent = typeof payload?.userAgent === "string" ? payload.userAgent.trim().slice(0, 500) : null;

    let endpointUrl: URL;
    try { endpointUrl = new URL(endpoint); } catch { return NextResponse.json({ error: "Geçersiz push endpoint adresi." }, { status: 400 }); }
    if (endpointUrl.protocol !== "https:" || endpoint.length > 2500 || p256dh.length < 20 || p256dh.length > 500 || authKey.length < 8 || authKey.length > 300) {
      return NextResponse.json({ error: "Geçersiz push aboneliği." }, { status: 400 });
    }

    const { error } = await supabase.from("push_subscriptions").upsert({
      user_id: authData.user.id,
      endpoint,
      p256dh,
      auth_key: authKey,
      user_agent: userAgent,
      last_seen_at: new Date().toISOString(),
    }, { onConflict: "endpoint" });

    if (error) return NextResponse.json({ error: error.message }, { status: 400 });
    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Push aboneliği kaydedilemedi." }, { status: 500 });
  }
}
