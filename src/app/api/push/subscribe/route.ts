import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) return NextResponse.json({ error: "Oturum gerekli." }, { status: 401 });

    const payload = await request.json() as {
      endpoint?: string;
      keys?: { p256dh?: string; auth?: string };
      userAgent?: string;
    };
    if (!payload.endpoint || !payload.keys?.p256dh || !payload.keys?.auth) {
      return NextResponse.json({ error: "Geçersiz push aboneliği." }, { status: 400 });
    }

    const { error } = await supabase.from("push_subscriptions").upsert({
      user_id: authData.user.id,
      endpoint: payload.endpoint,
      p256dh: payload.keys.p256dh,
      auth_key: payload.keys.auth,
      user_agent: payload.userAgent || null,
      last_seen_at: new Date().toISOString(),
    }, { onConflict: "endpoint" });

    if (error) return NextResponse.json({ error: error.message }, { status: 400 });
    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Push aboneliği kaydedilemedi." }, { status: 500 });
  }
}
