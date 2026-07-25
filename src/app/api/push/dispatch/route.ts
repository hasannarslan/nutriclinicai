import { NextResponse } from "next/server";
import { createClient as createAdminClient } from "@supabase/supabase-js";
import webpush from "web-push";

type NotificationRow = {
  id: string;
  recipient_user_id: string;
  title: string;
  body: string;
  action_view: string | null;
  metadata: Record<string, unknown> | null;
};
type SubscriptionRow = { id:string; user_id:string; endpoint:string; p256dh:string; auth_key:string };

export async function GET(request: Request) {
  const cronSecret = process.env.CRON_SECRET;
  if (!cronSecret || request.headers.get("authorization") !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRole = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const vapidPublic = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;
  const vapidPrivate = process.env.VAPID_PRIVATE_KEY;
  const vapidSubject = process.env.VAPID_SUBJECT || "mailto:admin@nutriclinic.app";
  if (!url || !serviceRole || !vapidPublic || !vapidPrivate) {
    return NextResponse.json({ error: "Push environment variables are missing." }, { status: 503 });
  }

  webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);
  const admin = createAdminClient(url, serviceRole, { auth: { persistSession: false, autoRefreshToken: false } });
  const since = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
  const { data: notifications, error: notificationError } = await admin
    .from("notifications")
    .select("id,recipient_user_id,title,body,action_view,metadata")
    .is("read_at", null)
    .gte("created_at", since)
    .order("created_at", { ascending: true })
    .limit(100);
  if (notificationError) return NextResponse.json({ error: notificationError.message }, { status: 500 });

  const rows = (notifications || []) as NotificationRow[];
  if (!rows.length) return NextResponse.json({ ok: true, sent: 0, failed: 0 });
  const userIds = [...new Set(rows.map((row) => row.recipient_user_id))];
  const { data: subscriptions, error: subscriptionError } = await admin
    .from("push_subscriptions")
    .select("id,user_id,endpoint,p256dh,auth_key")
    .in("user_id", userIds);
  if (subscriptionError) return NextResponse.json({ error: subscriptionError.message }, { status: 500 });

  const notificationIds = rows.map((row) => row.id);
  const { data: previousLogs } = await admin
    .from("push_delivery_logs")
    .select("notification_id,subscription_id")
    .in("notification_id", notificationIds);
  const delivered = new Set((previousLogs || []).map((row) => `${row.notification_id}:${row.subscription_id}`));
  const grouped = new Map<string, SubscriptionRow[]>();
  for (const subscription of (subscriptions || []) as SubscriptionRow[]) {
    grouped.set(subscription.user_id, [...(grouped.get(subscription.user_id) || []), subscription]);
  }

  let sent = 0;
  let failed = 0;
  for (const notification of rows) {
    for (const subscription of grouped.get(notification.recipient_user_id) || []) {
      const key = `${notification.id}:${subscription.id}`;
      if (delivered.has(key)) continue;
      try {
        await webpush.sendNotification({
          endpoint: subscription.endpoint,
          keys: { p256dh: subscription.p256dh, auth: subscription.auth_key },
        }, JSON.stringify({
          title: notification.title,
          body: notification.body,
          url: `/dashboard${notification.action_view ? `?view=${encodeURIComponent(notification.action_view)}` : ""}`,
        }), { TTL: 60 * 60 });
        await admin.from("push_delivery_logs").insert({ notification_id: notification.id, subscription_id: subscription.id, status: "sent" });
        sent += 1;
      } catch (error) {
        const statusCode = typeof error === "object" && error && "statusCode" in error ? Number((error as {statusCode?:number}).statusCode) : 0;
        const status = statusCode === 404 || statusCode === 410 ? "expired" : "failed";
        await admin.from("push_delivery_logs").upsert({
          notification_id: notification.id,
          subscription_id: subscription.id,
          status,
          error_message: error instanceof Error ? error.message.slice(0, 500) : "Push delivery failed",
        }, { onConflict: "notification_id,subscription_id" });
        if (status === "expired") await admin.from("push_subscriptions").delete().eq("id", subscription.id);
        failed += 1;
      }
    }
  }

  return NextResponse.json({ ok: true, sent, failed });
}
