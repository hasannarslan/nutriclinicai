import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { isPlatformAdminEmail } from "@/lib/platform-admin";
import { isUuid, publicErrorMessage } from "@/lib/api-validation";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type DbError = { message?: string } | null;
type DbResult<T> = { data: T | null; error: DbError };
type DbCountResult = { count: number | null; error: DbError };

function json(body: unknown, status = 200) {
  return NextResponse.json(body, {
    status,
    headers: {
      "cache-control": "no-store, max-age=0",
      pragma: "no-cache",
    },
  });
}

async function authorize() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user || !isPlatformAdminEmail(user.email)) return null;
  return user;
}

function finite(value: unknown) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function warningMessage(label: string, error?: DbError | unknown) {
  const message = error && typeof error === "object" && "message" in error
    ? String((error as { message?: unknown }).message || "").trim()
    : "";
  return message ? `${label}: ${message.slice(0, 220)}` : `${label} alınamadı.`;
}

async function optionalList<T>(label: string, query: PromiseLike<DbResult<T[]>>, warnings: string[]): Promise<T[]> {
  try {
    const result = await query;
    if (result.error) {
      warnings.push(warningMessage(label, result.error));
      return [];
    }
    return result.data || [];
  } catch (error) {
    warnings.push(warningMessage(label, error));
    return [];
  }
}

async function optionalOne<T>(label: string, query: PromiseLike<DbResult<T>>, warnings: string[]): Promise<T | null> {
  try {
    const result = await query;
    if (result.error) {
      warnings.push(warningMessage(label, result.error));
      return null;
    }
    return result.data || null;
  } catch (error) {
    warnings.push(warningMessage(label, error));
    return null;
  }
}

async function optionalCount(label: string, query: PromiseLike<DbCountResult>, warnings: string[]): Promise<number> {
  try {
    const result = await query;
    if (result.error) {
      warnings.push(warningMessage(label, result.error));
      return 0;
    }
    return Math.max(0, Number(result.count || 0));
  } catch (error) {
    warnings.push(warningMessage(label, error));
    return 0;
  }
}

export async function GET(_request: Request, context: { params: Promise<{ clinicId: string }> }) {
  const user = await authorize();
  if (!user) return json({ error: "Yetkisiz erişim" }, 403);

  try {
    const { clinicId } = await context.params;
    if (!isUuid(clinicId)) return json({ error: "Klinik kimliği geçersiz" }, 400);

    const admin = createAdminClient();
    const warnings: string[] = [];
    const clinicResult = await admin
      .from("clinics")
      .select("id,name,slug,status,default_locale,timezone,phone,email,website,address,logo_url,accent_color,created_at,updated_at,onboarding_completed_at")
      .eq("id", clinicId)
      .maybeSingle();

    if (clinicResult.error) throw clinicResult.error;
    if (!clinicResult.data) return json({ error: "Klinik bulunamadı" }, 404);

    const nowIso = new Date().toISOString();
    const [
      subscription,
      memberships,
      clients,
      payments,
      resources,
      packages,
      feedback,
      conversionRequests,
      notes,
      audit,
      clientsTotal,
      clientsActive,
      appointmentsTotal,
      appointmentsUpcoming,
      appointmentsCompleted,
      appointmentsCancelled,
      appointmentsNoShow,
      mealPlansTotal,
      mealPlansActive,
      measurementsTotal,
      resourcesTotal,
      resourcesActive,
      packagesTotal,
      packagesActive,
      feedbackTotal,
      feedbackOpen,
    ] = await Promise.all([
      optionalOne("Abonelik", admin.from("clinic_subscriptions").select("id,clinic_id,plan_slug,status,pilot_started_at,pilot_ends_at,current_period_started_at,current_period_ends_at,billing_provider,cancel_at_period_end,limits_override,metadata,commercial_approved_at,commercial_approved_by_email,commercial_approval_note,agreed_price_try,billing_cycle,converted_from_pilot_at,created_at,updated_at").eq("clinic_id", clinicId).maybeSingle(), warnings),
      optionalList("Klinik üyelikleri", admin.from("clinic_memberships").select("id,user_id,role,is_active,created_at,updated_at").eq("clinic_id", clinicId).order("created_at"), warnings),
      optionalList("Danışanlar", admin.from("client_profiles").select("id,member_no,full_name,email,phone,is_active,created_at,updated_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(200), warnings),
      optionalList("Ödemeler", admin.from("payments").select("id,amount,paid_amount,remaining_amount,currency,status,paid_at,due_date,created_at").eq("clinic_id", clinicId).limit(5000), warnings),
      optionalList("Cihaz ve odalar", admin.from("clinic_resources").select("id,name,resource_type,is_active,created_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(100), warnings),
      optionalList("Paketler", admin.from("client_packages").select("id,name,status,total_price,currency,created_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(100), warnings),
      optionalList("Geri bildirimler", admin.from("pilot_feedback").select("id,clinic_id,category,rating,message,page_path,status,admin_note,created_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(20), warnings),
      optionalList("Geçiş talepleri", admin.from("clinic_conversion_requests").select("id,clinic_id,requested_by,requested_plan_slug,note,status,reviewed_by_email,reviewed_at,admin_note,created_at,updated_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(20), warnings),
      optionalList("Platform notları", admin.from("platform_clinic_notes").select("id,note,created_by_email,created_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(30), warnings),
      optionalList("Denetim kayıtları", admin.from("audit_logs").select("id,actor_user_id,action,target_type,target_id,metadata,created_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(30), warnings),
      optionalCount("Danışan toplamı", admin.from("client_profiles").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId), warnings),
      optionalCount("Aktif danışan toplamı", admin.from("client_profiles").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId).eq("is_active", true), warnings),
      optionalCount("Randevu toplamı", admin.from("appointments").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId), warnings),
      optionalCount("Yaklaşan randevular", admin.from("appointments").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId).gte("starts_at", nowIso).in("status", ["pending", "confirmed"]), warnings),
      optionalCount("Tamamlanan randevular", admin.from("appointments").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId).eq("status", "completed"), warnings),
      optionalCount("İptal edilen randevular", admin.from("appointments").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId).eq("status", "cancelled"), warnings),
      optionalCount("Gelmedi randevuları", admin.from("appointments").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId).eq("status", "no_show"), warnings),
      optionalCount("Menü planı toplamı", admin.from("meal_plans").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId), warnings),
      optionalCount("Aktif menü planları", admin.from("meal_plans").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId).eq("status", "active"), warnings),
      optionalCount("Ölçüm toplamı", admin.from("measurements").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId), warnings),
      optionalCount("Kaynak toplamı", admin.from("clinic_resources").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId), warnings),
      optionalCount("Aktif kaynaklar", admin.from("clinic_resources").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId).eq("is_active", true), warnings),
      optionalCount("Paket toplamı", admin.from("client_packages").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId), warnings),
      optionalCount("Aktif paketler", admin.from("client_packages").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId).eq("status", "active"), warnings),
      optionalCount("Geri bildirim toplamı", admin.from("pilot_feedback").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId), warnings),
      optionalCount("Açık geri bildirimler", admin.from("pilot_feedback").select("id", { count: "exact", head: true }).eq("clinic_id", clinicId).in("status", ["new", "reviewing", "planned"]), warnings),
    ]);

    const userIds = Array.from(new Set((memberships as Array<{ user_id?: string }>).map((item) => item.user_id).filter((value): value is string => Boolean(value))));
    const profiles = userIds.length
      ? await optionalList("Üye profilleri", admin.from("profiles").select("id,full_name,email,phone,preferred_locale,created_at,updated_at").in("id", userIds), warnings)
      : [];
    const profileMap = new Map((profiles as Array<{ id: string }>).map((profile) => [profile.id, profile]));

    const subscriptionRow = subscription as { plan_slug?: string } | null;
    const plan = subscriptionRow?.plan_slug
      ? await optionalOne("Plan bilgisi", admin.from("subscription_plans").select("slug,name,description,monthly_price_try,max_dietitians,max_staff,max_active_clients,monthly_ai_credits,storage_gb,features").eq("slug", subscriptionRow.plan_slug).maybeSingle(), warnings)
      : null;

    const paymentRows = payments as Array<{ currency?: string | null; status?: string; amount?: number | string | null; paid_amount?: number | string | null; remaining_amount?: number | string | null }>;
    const paymentCurrencies = Array.from(new Set(paymentRows.map((item) => item.currency || "TRY")));
    const financials = paymentCurrencies.map((currency) => {
      const rows = paymentRows.filter((item) => (item.currency || "TRY") === currency && !["cancelled", "refunded"].includes(item.status || ""));
      return {
        currency,
        total: rows.reduce((total, item) => total + finite(item.amount), 0),
        paid: rows.reduce((total, item) => total + finite(item.paid_amount), 0),
        remaining: rows.reduce((total, item) => total + (item.remaining_amount == null ? Math.max(0, finite(item.amount) - finite(item.paid_amount)) : finite(item.remaining_amount)), 0),
      };
    });

    if (paymentRows.length === 5000) warnings.push("Finans özeti son 5.000 ödeme kaydı üzerinden hesaplandı.");

    const members = (memberships as Array<{ user_id: string }>).map((membership) => ({
      ...membership,
      profile: profileMap.get(membership.user_id) || null,
    }));

    return json({
      clinic: clinicResult.data,
      subscription: subscription ? { ...(subscription as Record<string, unknown>), plan } : null,
      members,
      clients,
      resources,
      packages,
      feedback,
      conversionRequests,
      notes,
      audit,
      warnings,
      stats: {
        members: {
          total: members.filter((item) => (item as { is_active?: boolean }).is_active).length,
          owners: members.filter((item) => (item as { is_active?: boolean; role?: string }).is_active && (item as { role?: string }).role === "owner").length,
          dietitians: members.filter((item) => (item as { is_active?: boolean; role?: string }).is_active && (item as { role?: string }).role === "dietitian").length,
          secretaries: members.filter((item) => (item as { is_active?: boolean; role?: string }).is_active && (item as { role?: string }).role === "secretary").length,
        },
        clients: { active: clientsActive, total: clientsTotal },
        appointments: {
          total: appointmentsTotal,
          upcoming: appointmentsUpcoming,
          completed: appointmentsCompleted,
          cancelled: appointmentsCancelled,
          no_show: appointmentsNoShow,
        },
        mealPlans: { total: mealPlansTotal, active: mealPlansActive },
        measurements: measurementsTotal,
        resources: { total: resourcesTotal, active: resourcesActive },
        packages: { total: packagesTotal, active: packagesActive },
        feedback: { total: feedbackTotal, open: feedbackOpen },
        financials,
      },
    });
  } catch (error) {
    return json({ error: publicErrorMessage(error, "Klinik detayları alınamadı") }, 500);
  }
}
