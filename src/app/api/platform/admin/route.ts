import { randomBytes } from "node:crypto";
import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { isPlatformAdminEmail } from "@/lib/platform-admin";
import {
  cleanEmail,
  cleanText,
  isUuid,
  parseStrictBoolean,
  parseBoundedInteger,
  parseBoundedNumber,
  publicErrorMessage,
  sameOriginRequest,
} from "@/lib/api-validation";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type QueryError = { message?: string; code?: string } | null;
type QueryResult<T> = { data: T | null; error: QueryError };

async function authorize() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user || !isPlatformAdminEmail(user.email)) return null;
  return user;
}

function json(body: Record<string, unknown>, status = 200) {
  return NextResponse.json(body, { status, headers: { "Cache-Control": "no-store, max-age=0" } });
}

async function optionalRows<T>(label: string, promise: PromiseLike<QueryResult<T[]>>, warnings: string[]): Promise<T[]> {
  try {
    const result = await promise;
    if (result.error) {
      warnings.push(`${label}: ${result.error.message || "veri alınamadı"}`);
      return [];
    }
    return result.data || [];
  } catch (error) {
    warnings.push(`${label}: ${error instanceof Error ? error.message : "veri alınamadı"}`);
    return [];
  }
}

async function optionalOne<T>(label: string, promise: PromiseLike<QueryResult<T>>, warnings: string[]): Promise<T | null> {
  try {
    const result = await promise;
    if (result.error) {
      warnings.push(`${label}: ${result.error.message || "veri alınamadı"}`);
      return null;
    }
    return result.data || null;
  } catch (error) {
    warnings.push(`${label}: ${error instanceof Error ? error.message : "veri alınamadı"}`);
    return null;
  }
}

async function audit(admin: ReturnType<typeof createAdminClient>, entry: Record<string, unknown>) {
  const { error } = await admin.from("audit_logs").insert(entry);
  return error?.message || null;
}

export async function GET() {
  const user = await authorize();
  if (!user) return json({ error: "Yetkisiz erişim" }, 403);

  try {
    const admin = createAdminClient();
    const warnings: string[] = [];
    const clinicsResult = await admin.from("clinics").select("id,name,slug,status,default_locale,timezone,created_at,updated_at").order("created_at", { ascending: false });
    if (clinicsResult.error) throw clinicsResult.error;

    const [subscriptions, memberships, clients, pilotInvites, pilotApplications, feedback, plans, conversionRequests] = await Promise.all([
      optionalRows("Abonelikler", admin.from("clinic_subscriptions").select("clinic_id,plan_slug,status,pilot_started_at,pilot_ends_at,current_period_started_at,current_period_ends_at,commercial_approved_at,commercial_approved_by_email,agreed_price_try,billing_cycle,updated_at"), warnings),
      optionalRows("Klinik üyelikleri", admin.from("clinic_memberships").select("clinic_id,role,is_active"), warnings),
      optionalRows("Danışanlar", admin.from("client_profiles").select("clinic_id,is_active"), warnings),
      optionalRows("Pilot davetleri", admin.from("pilot_invites").select("id,token,label,contact_email,plan_slug,pilot_days,max_uses,used_count,expires_at,is_active,created_by_email,created_at").order("created_at", { ascending: false }).limit(200), warnings),
      optionalRows("Pilot başvuruları", admin.from("pilot_applications").select("id,full_name,email,phone,applicant_type,clinic_name,city,team_size,active_client_count,uses_devices,message,status,admin_note,created_at,updated_at").order("created_at", { ascending: false }).limit(500), warnings),
      optionalRows("Geri bildirimler", admin.from("pilot_feedback").select("id,clinic_id,user_id,category,rating,message,page_path,status,admin_note,created_at").order("created_at", { ascending: false }).limit(500), warnings),
      optionalRows("Planlar", admin.from("subscription_plans").select("slug,name,monthly_price_try,max_dietitians,max_staff,max_active_clients,monthly_ai_credits,is_public,is_active,sort_order").order("sort_order"), warnings),
      optionalRows("Geçiş talepleri", admin.from("clinic_conversion_requests").select("id,clinic_id,requested_by,requested_plan_slug,note,status,reviewed_by_email,reviewed_at,admin_note,created_at,updated_at").order("created_at", { ascending: false }).limit(500), warnings),
    ]);

    const subscriptionMap = new Map(subscriptions.map((row) => [String((row as { clinic_id: string }).clinic_id), row]));
    const membershipCounts = new Map<string, { owners: number; dietitians: number; secretaries: number; total: number }>();
    for (const row of memberships as Array<{ clinic_id: string; role: string; is_active: boolean }>) {
      if (!row.is_active) continue;
      const current = membershipCounts.get(row.clinic_id) || { owners: 0, dietitians: 0, secretaries: 0, total: 0 };
      current.total += 1;
      if (row.role === "owner") current.owners += 1;
      if (row.role === "dietitian") current.dietitians += 1;
      if (row.role === "secretary") current.secretaries += 1;
      membershipCounts.set(row.clinic_id, current);
    }

    const clientCounts = new Map<string, number>();
    for (const row of clients as Array<{ clinic_id: string; is_active: boolean }>) {
      if (!row.is_active) continue;
      clientCounts.set(row.clinic_id, (clientCounts.get(row.clinic_id) || 0) + 1);
    }

    const latestConversion = new Map<string, unknown>();
    for (const row of conversionRequests as Array<{ clinic_id: string }>) {
      if (!latestConversion.has(row.clinic_id)) latestConversion.set(row.clinic_id, row);
    }

    const clinics = (clinicsResult.data || []).map((clinic) => ({
      ...clinic,
      subscription: subscriptionMap.get(clinic.id) || null,
      memberships: membershipCounts.get(clinic.id) || { owners: 0, dietitians: 0, secretaries: 0, total: 0 },
      active_clients: clientCounts.get(clinic.id) || 0,
      conversion_request: latestConversion.get(clinic.id) || null,
    }));

    return json({
      clinics,
      pilotInvites,
      pilotApplications,
      feedback,
      plans,
      conversionRequests,
      warnings,
      metrics: {
        clinics: clinics.length,
        pilotClinics: clinics.filter((clinic) => (clinic.subscription as { plan_slug?: string; status?: string } | null)?.plan_slug === "pilot" && ["pilot", "trialing"].includes((clinic.subscription as { status?: string } | null)?.status || "")).length,
        activeUsers: (memberships as Array<{ is_active: boolean }>).filter((row) => row.is_active).length,
        activeClients: (clients as Array<{ is_active: boolean }>).filter((row) => row.is_active).length,
        openFeedback: (feedback as Array<{ status: string }>).filter((row) => ["new", "reviewing", "planned"].includes(row.status)).length,
        openApplications: (pilotApplications as Array<{ status: string }>).filter((row) => ["new", "contacted"].includes(row.status)).length,
        pendingConversions: (conversionRequests as Array<{ status: string }>).filter((row) => row.status === "pending").length,
      },
    });
  } catch (error) {
    return json({ error: publicErrorMessage(error, "Platform verileri alınamadı") }, 500);
  }
}

export async function POST(request: Request) {
  const user = await authorize();
  if (!user) return json({ error: "Yetkisiz erişim" }, 403);
  if (!sameOriginRequest(request)) return json({ error: "Geçersiz istek kaynağı" }, 403);

  try {
    const contentLength = Number(request.headers.get("content-length") || 0);
    if (contentLength > 64_000) return json({ error: "İstek verisi çok büyük" }, 413);
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) return json({ error: "Geçersiz istek verisi" }, 400);

    const action = cleanText(body.action, 80);
    const admin = createAdminClient();

    if (action === "create_pilot_invite") {
      const label = cleanText(body.label, 180);
      const rawEmail = cleanText(body.contact_email, 254);
      const contactEmail = rawEmail ? cleanEmail(rawEmail) : null;
      if (!label) return json({ error: "Pilot etiketi zorunludur" }, 400);
      if (rawEmail && !contactEmail) return json({ error: "E-posta adresi geçersiz" }, 400);
      const pilotDays = parseBoundedInteger(body.pilot_days, 90, 7, 365);
      const expiresDays = parseBoundedInteger(body.expires_days, 14, 1, 90);
      const maxUses = parseBoundedInteger(body.max_uses, 1, 1, 20);
      const token = randomBytes(16).toString("hex").toUpperCase();
      const { data, error } = await admin.from("pilot_invites").insert({
        token,
        label,
        contact_email: contactEmail,
        plan_slug: "pilot",
        pilot_days: pilotDays,
        max_uses: maxUses,
        expires_at: new Date(Date.now() + expiresDays * 86_400_000).toISOString(),
        created_by_email: user.email,
      }).select("id,token,label,contact_email,pilot_days,max_uses,used_count,expires_at,is_active,created_at").single();
      if (error) throw error;
      return json({ invite: data });
    }

    if (action === "extend_pilot") {
      const clinicId = cleanText(body.clinic_id, 50);
      if (!isUuid(clinicId)) return json({ error: "Klinik kimliği geçersiz" }, 400);
      const days = parseBoundedInteger(body.days, 30, 1, 365);
      const { data, error } = await admin.rpc("platform_extend_pilot_v81", {
        p_clinic_id: clinicId,
        p_days: days,
        p_admin_email: user.email || "Platform Admin",
        p_actor_user_id: user.id,
      });
      if (error) throw error;
      return json({ ok: true, pilot_ends_at: data });
    }

    if (action === "approve_paid_access") {
      const clinicId = cleanText(body.clinic_id, 50);
      const requestIdValue = cleanText(body.request_id, 50);
      const requestId = requestIdValue && isUuid(requestIdValue) ? requestIdValue : null;
      const planSlug = cleanText(body.plan_slug, 80);
      const billingCycle = cleanText(body.billing_cycle, 20) || "monthly";
      const agreedPrice = parseBoundedNumber(body.agreed_price_try, null, 0, 100_000_000);
      const approvalNote = cleanText(body.approval_note, 5000) || null;
      if (!isUuid(clinicId)) return json({ error: "Klinik kimliği geçersiz" }, 400);
      if (!planSlug || ["pilot", "founder"].includes(planSlug)) return json({ error: "Ücretli plan seçmelisiniz" }, 400);
      if (!["monthly", "annual", "manual"].includes(billingCycle)) return json({ error: "Faturalama dönemi geçersiz" }, 400);
      if (requestIdValue && !requestId) return json({ error: "Geçiş talebi kimliği geçersiz" }, 400);
      if (body.agreed_price_try !== "" && body.agreed_price_try != null && agreedPrice === null) return json({ error: "Anlaşılan fiyat geçersiz" }, 400);

      const { data, error } = await admin.rpc("platform_approve_paid_access_v81", {
        p_clinic_id: clinicId,
        p_request_id: requestId,
        p_plan_slug: planSlug,
        p_billing_cycle: billingCycle,
        p_agreed_price_try: agreedPrice,
        p_approval_note: approvalNote,
        p_admin_email: user.email || "Platform Admin",
        p_actor_user_id: user.id,
      });
      if (error) throw error;
      return json({ ok: true, result: data });
    }

    if (action === "reject_conversion_request") {
      const clinicId = cleanText(body.clinic_id, 50);
      const requestId = cleanText(body.request_id, 50);
      const adminNote = cleanText(body.admin_note, 5000) || null;
      if (!isUuid(clinicId) || !isUuid(requestId)) return json({ error: "Talep bilgisi geçersiz" }, 400);
      const { data, error } = await admin.from("clinic_conversion_requests").update({ status: "rejected", reviewed_by_email: user.email, reviewed_at: new Date().toISOString(), admin_note: adminNote, updated_at: new Date().toISOString() }).eq("id", requestId).eq("clinic_id", clinicId).eq("status", "pending").select("id").maybeSingle();
      if (error) throw error;
      if (!data) return json({ error: "Bekleyen geçiş talebi bulunamadı" }, 404);
      await audit(admin, { clinic_id: clinicId, actor_user_id: user.id, action: "clinic_paid_conversion_rejected", target_type: "clinic", target_id: clinicId, metadata: { request_id: requestId, note: adminNote, reviewed_by_email: user.email } });
      return json({ ok: true });
    }

    if (action === "save_clinic_note") {
      const clinicId = cleanText(body.clinic_id, 50);
      const note = cleanText(body.note, 5000);
      if (!isUuid(clinicId)) return json({ error: "Klinik kimliği geçersiz" }, 400);
      if (note.length < 2) return json({ error: "Klinik notu en az 2 karakter olmalıdır" }, 400);
      const { data, error } = await admin.from("platform_clinic_notes").insert({ clinic_id: clinicId, note, created_by_email: user.email || "Platform Admin" }).select("id").single();
      if (error) throw error;
      return json({ ok: true, id: data.id });
    }

    if (action === "set_clinic_status") {
      const clinicId = cleanText(body.clinic_id, 50);
      const status = cleanText(body.status, 30);
      if (!isUuid(clinicId)) return json({ error: "Klinik kimliği geçersiz" }, 400);
      if (!["active", "paused", "expired", "cancelled"].includes(status)) return json({ error: "Durum geçersiz" }, 400);
      const { error } = await admin.rpc("platform_set_clinic_status_v81", {
        p_clinic_id: clinicId,
        p_status: status,
        p_admin_email: user.email || "Platform Admin",
        p_actor_user_id: user.id,
      });
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "change_plan") {
      const clinicId = cleanText(body.clinic_id, 50);
      const planSlug = cleanText(body.plan_slug, 80);
      if (!isUuid(clinicId) || !planSlug) return json({ error: "Klinik ve plan zorunludur" }, 400);
      if (planSlug === "pilot") return json({ error: "Bir klinik genel plan değişikliğiyle pilot plana alınamaz. Pilot davet akışını kullanın." }, 400);
      const { error } = await admin.rpc("platform_change_plan_v81", {
        p_clinic_id: clinicId,
        p_plan_slug: planSlug,
        p_admin_email: user.email || "Platform Admin",
        p_actor_user_id: user.id,
      });
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "set_invite_active") {
      const inviteId = cleanText(body.invite_id, 50);
      if (!isUuid(inviteId)) return json({ error: "Davet kimliği geçersiz" }, 400);
      const isActive = parseStrictBoolean(body.is_active);
      if (isActive === null) return json({ error: "Davet durumu geçersiz" }, 400);
      const { data, error } = await admin.from("pilot_invites").update({ is_active: isActive, updated_at: new Date().toISOString() }).eq("id", inviteId).select("id").maybeSingle();
      if (error) throw error;
      if (!data) return json({ error: "Pilot daveti bulunamadı" }, 404);
      return json({ ok: true });
    }

    if (action === "update_pilot_application") {
      const applicationId = cleanText(body.application_id, 50);
      const status = cleanText(body.status, 30) || "contacted";
      const adminNote = cleanText(body.admin_note, 5000) || null;
      if (!isUuid(applicationId)) return json({ error: "Başvuru kimliği geçersiz" }, 400);
      if (!["new", "contacted", "approved", "waitlist", "rejected", "closed"].includes(status)) return json({ error: "Başvuru durumu geçersiz" }, 400);
      const { data, error } = await admin.from("pilot_applications").update({ status, admin_note: adminNote, reviewed_by_email: user.email, reviewed_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", applicationId).select("id").maybeSingle();
      if (error) throw error;
      if (!data) return json({ error: "Pilot başvurusu bulunamadı" }, 404);
      return json({ ok: true });
    }

    if (action === "update_feedback") {
      const feedbackId = cleanText(body.feedback_id, 50);
      const status = cleanText(body.status, 30) || "reviewing";
      const adminNote = cleanText(body.admin_note, 5000) || null;
      if (!isUuid(feedbackId)) return json({ error: "Geri bildirim kimliği geçersiz" }, 400);
      if (!["new", "reviewing", "planned", "resolved", "closed"].includes(status)) return json({ error: "Geri bildirim durumu geçersiz" }, 400);
      const { data, error } = await admin.from("pilot_feedback").update({ status, admin_note: adminNote, updated_at: new Date().toISOString() }).eq("id", feedbackId).select("id").maybeSingle();
      if (error) throw error;
      if (!data) return json({ error: "Geri bildirim bulunamadı" }, 404);
      return json({ ok: true });
    }

    return json({ error: "Bilinmeyen işlem" }, 400);
  } catch (error) {
    return json({ error: publicErrorMessage(error, "Platform işlemi tamamlanamadı") }, 500);
  }
}
