import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

function authorized(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  return request.headers.get("authorization") === `Bearer ${secret}`;
}

export async function GET(request: Request) {
  if (!authorized(request)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  try {
    const admin = createAdminClient();
    const { data: subscriptions, error } = await admin
      .from("clinic_subscriptions")
      .select("clinic_id,status,pilot_ends_at,last_pilot_reminder_days")
      .eq("status", "pilot")
      .not("pilot_ends_at", "is", null);
    if (error) throw error;

    let expired = 0;
    let reminded = 0;
    for (const subscription of subscriptions || []) {
      const end = new Date(subscription.pilot_ends_at as string);
      const remaining = Math.ceil((end.getTime() - Date.now()) / 86400000);
      const { data: owners } = await admin
        .from("clinic_memberships")
        .select("user_id")
        .eq("clinic_id", subscription.clinic_id)
        .eq("role", "owner")
        .eq("is_active", true);

      if (remaining < 0) {
        await admin.from("clinic_subscriptions").update({ status: "expired", last_pilot_reminder_days: 0, updated_at: new Date().toISOString() }).eq("clinic_id", subscription.clinic_id);
        await admin.from("clinics").update({ status: "expired", updated_at: new Date().toISOString() }).eq("id", subscription.clinic_id);
        if (owners?.length) {
          await admin.from("notifications").insert(owners.map((owner) => ({
            clinic_id: subscription.clinic_id,
            recipient_user_id: owner.user_id,
            title: "Pilot erişim süresi sona erdi",
            body: "Klinik verileriniz korunuyor. Kullanıma devam etmek için NutriClinic AI platform yöneticisiyle iletişime geçin.",
            category: "system",
            metadata: { view: "settings", event: "pilot_expired" },
          })));
        }
        expired += 1;
        continue;
      }

      if ([14, 7, 3, 1, 0].includes(remaining) && subscription.last_pilot_reminder_days !== remaining) {
        if (owners?.length) {
          await admin.from("notifications").insert(owners.map((owner) => ({
            clinic_id: subscription.clinic_id,
            recipient_user_id: owner.user_id,
            title: remaining === 0 ? "Pilot sürenizin son günü" : `Pilot sürenizin bitmesine ${remaining} gün kaldı`,
            body: "Pilot geri bildirimlerinizi paneldeki Pilot Geri Bildirimi alanından iletebilir veya süre uzatımı için platform yöneticinizle görüşebilirsiniz.",
            category: "system",
            metadata: { view: "settings", event: "pilot_ending", days_remaining: remaining },
          })));
        }
        await admin.from("clinic_subscriptions").update({ last_pilot_reminder_days: remaining, updated_at: new Date().toISOString() }).eq("clinic_id", subscription.clinic_id);
        reminded += 1;
      }
    }
    return NextResponse.json({ ok: true, processed: subscriptions?.length || 0, reminded, expired });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Pilot lifecycle failed" }, { status: 500 });
  }
}
