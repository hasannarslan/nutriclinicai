"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Activity,
  Bell,
  CalendarClock,
  Check,
  CheckCheck,
  CircleDollarSign,
  Gift,
  LoaderCircle,
  MessageCircle,
  UtensilsCrossed,
  X,
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { intlLocales, normalizeLocale } from "@/lib/i18n";
import type { Role } from "@/lib/types";

type View =
  | "dashboard"
  | "appointments"
  | "clients"
  | "payments"
  | "mealPlans"
  | "measurements"
  | "loyalty"
  | "community"
  | "packages"
  | "resources"
  | "forms"
  | "documents"
  | "messages"
  | "followup"
  | "team"
  | "settings";

type NotificationRow = {
  id: string;
  clinic_id: string;
  recipient_user_id: string;
  title: string;
  body: string;
  category: string;
  metadata: Record<string, unknown> | null;
  action_view?: View | null;
  read_at: string | null;
  created_at: string;
};

function categoryIcon(category: string) {
  if (category.includes("meal")) return <UtensilsCrossed size={17} />;
  if (category.includes("measurement")) return <Activity size={17} />;
  if (category.includes("payment")) return <CircleDollarSign size={17} />;
  if (category.includes("appointment")) return <CalendarClock size={17} />;
  if (category.includes("loyalty") || category.includes("reward")) return <Gift size={17} />;
  if (category.includes("community")) return <MessageCircle size={17} />;
  return <Bell size={17} />;
}

function relativeTime(value: string, locale: string) {
  const date = new Date(value);
  const seconds = Math.round((date.getTime() - Date.now()) / 1000);
  const abs = Math.abs(seconds);
  const intlLocale = intlLocales[normalizeLocale(locale)];
  const formatter = new Intl.RelativeTimeFormat(intlLocale, { numeric: "auto" });
  if (abs < 60) return formatter.format(seconds, "second");
  const minutes = Math.round(seconds / 60);
  if (Math.abs(minutes) < 60) return formatter.format(minutes, "minute");
  const hours = Math.round(minutes / 60);
  if (Math.abs(hours) < 24) return formatter.format(hours, "hour");
  const days = Math.round(hours / 24);
  if (Math.abs(days) < 30) return formatter.format(days, "day");
  return date.toLocaleDateString(intlLocale, { day: "2-digit", month: "short", year: "numeric" });
}

function defaultAction(category: string, role: Role): View {
  if (category.includes("meal")) return "mealPlans";
  if (category.includes("measurement")) return "measurements";
  if (category.includes("payment")) return role === "client" ? "settings" : "payments";
  if (category.includes("appointment")) return "appointments";
  if (category.includes("loyalty") || category.includes("reward")) return "loyalty";
  if (category.includes("community")) return "community";
  if (category.includes("package")) return "packages";
  if (category.includes("message")) return "messages";
  if (category.includes("task") || category.includes("adherence")) return "followup";
  if (category.includes("document")) return "documents";
  return "dashboard";
}

export function NotificationCenter({
  userId,
  role,
  locale,
  onNavigate,
}: {
  userId: string;
  role: Role;
  locale: string;
  onNavigate: (view: View) => void;
}) {
  const supabase = useMemo(() => createClient(), []);
  const rootRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState<NotificationRow[]>([]);
  const [toast, setToast] = useState<NotificationRow | null>(null);
  const unread = rows.filter((row) => !row.read_at).length;

  const load = useCallback(async () => {
    setLoading(true);
    await supabase.rpc("sync_due_notifications_v5");
    const { data, error } = await supabase
      .from("notifications")
      .select("id,clinic_id,recipient_user_id,title,body,category,metadata,action_view,read_at,created_at")
      .eq("recipient_user_id", userId)
      .order("created_at", { ascending: false })
      .limit(50);
    if (!error) setRows((data || []) as NotificationRow[]);
    setLoading(false);
  }, [supabase, userId]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const channel = supabase
      .channel(`notifications:${userId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "notifications",
          filter: `recipient_user_id=eq.${userId}`,
        },
        (payload) => {
          const incoming = payload.new as NotificationRow;
          setRows((current) => [incoming, ...current.filter((row) => row.id !== incoming.id)].slice(0, 50));
          setToast(incoming);
          if ("Notification" in window && Notification.permission === "granted" && "serviceWorker" in navigator) {
            void navigator.serviceWorker.ready.then((registration) => registration.showNotification(incoming.title, {
              body: incoming.body,
              icon: "/icon.svg",
              badge: "/icon.svg",
              data: { url: "/dashboard" },
            })).catch(() => undefined);
          }
          window.setTimeout(() => setToast((current) => (current?.id === incoming.id ? null : current)), 5500);
        },
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "notifications",
          filter: `recipient_user_id=eq.${userId}`,
        },
        (payload) => {
          const incoming = payload.new as NotificationRow;
          setRows((current) => current.map((row) => (row.id === incoming.id ? incoming : row)));
        },
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [supabase, userId]);

  useEffect(() => {
    function closeOnOutside(event: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", closeOnOutside);
    return () => document.removeEventListener("mousedown", closeOnOutside);
  }, []);

  async function markRead(row: NotificationRow) {
    if (!row.read_at) {
      const readAt = new Date().toISOString();
      setRows((current) => current.map((item) => (item.id === row.id ? { ...item, read_at: readAt } : item)));
      await supabase.from("notifications").update({ read_at: readAt }).eq("id", row.id);
    }
    const action = row.action_view || (row.metadata?.action_view as View | undefined) || defaultAction(row.category, role);
    onNavigate(action);
    setOpen(false);
  }

  async function markAllRead() {
    const readAt = new Date().toISOString();
    setRows((current) => current.map((row) => ({ ...row, read_at: row.read_at || readAt })));
    await supabase
      .from("notifications")
      .update({ read_at: readAt })
      .eq("recipient_user_id", userId)
      .is("read_at", null);
  }

  return (
    <>
      {toast && (
        <button type="button" className="notification-toast" onClick={() => void markRead(toast)}>
          <span>{categoryIcon(toast.category)}</span>
          <div><b>{toast.title}</b><small>{toast.body}</small></div>
          <X size={15} onClick={(event) => { event.stopPropagation(); setToast(null); }} />
        </button>
      )}
      <div className="notification-center" ref={rootRef}>
        <button
          type="button"
          className={`notification-bell ${open ? "active" : ""}`}
          aria-label={unread ? `${unread} okunmamış bildirim` : "Bildirimler"}
          aria-expanded={open}
          onClick={() => setOpen((value) => !value)}
        >
          <Bell size={20} />
          {unread > 0 && <span>{unread > 99 ? "99+" : unread}</span>}
        </button>

        {open && (
          <section className="notification-panel" aria-label="Bildirim merkezi">
            <header>
              <div><span className="section-kicker">NUTRICLINIC AI</span><h3>Bildirimler</h3></div>
              {unread > 0 && <button type="button" onClick={markAllRead}><CheckCheck size={15} />Tümünü okundu yap</button>}
            </header>
            <div className="notification-list">
              {loading ? (
                <div className="notification-empty"><LoaderCircle className="spin" /><p>Bildirimler yükleniyor…</p></div>
              ) : rows.length === 0 ? (
                <div className="notification-empty"><Bell /><b>Henüz bildirim yok</b><p>Yeni menü, ölçüm, ödeme ve yaklaşan tarihler burada görünecek.</p></div>
              ) : rows.map((row) => (
                <button type="button" key={row.id} className={`notification-row ${row.read_at ? "" : "unread"}`} onClick={() => void markRead(row)}>
                  <span className="notification-row-icon">{categoryIcon(row.category)}</span>
                  <span className="notification-row-copy">
                    <b>{row.title}</b>
                    <small>{row.body}</small>
                    <time>{relativeTime(row.created_at, locale)}</time>
                  </span>
                  <span className="notification-row-state">{row.read_at ? <Check size={14} /> : <i />}</span>
                </button>
              ))}
            </div>
          </section>
        )}
      </div>
    </>
  );
}
