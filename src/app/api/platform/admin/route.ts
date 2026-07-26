import { randomBytes } from "node:crypto";
import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { isPlatformAdminEmail } from "@/lib/platform-admin";

export const dynamic = "force-dynamic";

async function authorize() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user || !isPlatformAdminEmail(user.email)) return null;
  return user;
}

export async function GET() {
  const user = await authorize();
  if (!user) return NextResponse.json({ error: "Yetkisiz erişim" }, { status: 403 });
  try {
    const admin = createAdminClient();
    const [clinicsResult, subscriptionsResult, membershipsResult, clientsResult, invitesResult, applicationsResult, feedbackResult, plansResult, conversionResult] = await Promise.all([
      admin.from("clinics").select("id,name,slug,status,default_locale,timezone,created_at,updated_at").order("created_at", { ascending: false }),
      admin.from("clinic_subscriptions").select("clinic_id,plan_slug,status,pilot_started_at,pilot_ends_at,current_period_started_at,current_period_ends_at,commercial_approved_at,commercial_approved_by_email,agreed_price_try,billing_cycle,updated_at"),
      admin.from("clinic_memberships").select("clinic_id,role,is_active"),
      admin.from("client_profiles").select("clinic_id,is_active"),
      admin.from("pilot_invites").select("id,token,label,contact_email,plan_slug,pilot_days,max_uses,used_count,expires_at,is_active,created_by_email,created_at").order("created_at", { ascending: false }).limit(100),
      admin.from("pilot_applications").select("id,full_name,email,phone,applicant_type,clinic_name,city,team_size,active_client_count,uses_devices,message,status,admin_note,created_at,updated_at").order("created_at", { ascending: false }).limit(200),
      admin.from("pilot_feedback").select("id,clinic_id,user_id,category,rating,message,page_path,status,admin_note,created_at").order("created_at", { ascending: false }).limit(100),
      admin.from("subscription_plans").select("slug,name,monthly_price_try,max_dietitians,max_staff,max_active_clients,monthly_ai_credits,is_public,is_active,sort_order").order("sort_order"),
      admin.from("clinic_conversion_requests").select("id,clinic_id,requested_by,requested_plan_slug,note,status,reviewed_by_email,reviewed_at,admin_note,created_at,updated_at").order("created_at", { ascending: false }).limit(200),
    ]);
    const firstError = [clinicsResult, subscriptionsResult, membershipsResult, clientsResult, invitesResult, applicationsResult, feedbackResult, plansResult, conversionResult].find((result) => result.error)?.error;
    if (firstError) throw firstError;

    const subscriptions = new Map((subscriptionsResult.data || []).map((row) => [row.clinic_id, row]));
    const membershipCounts = new Map<string, { owners: number; dietitians: number; secretaries: number; total: number }>();
    for (const row of membershipsResult.data || []) {
      if (!row.is_active) continue;
      const current = membershipCounts.get(row.clinic_id) || { owners: 0, dietitians: 0, secretaries: 0, total: 0 };
      current.total += 1;
      if (row.role === "owner") current.owners += 1;
      if (row.role === "dietitian") current.dietitians += 1;
      if (row.role === "secretary") current.secretaries += 1;
      membershipCounts.set(row.clinic_id, current);
    }
    const clientCounts = new Map<string, number>();
    for (const row of clientsResult.data || []) {
      if (!row.is_active) continue;
      clientCounts.set(row.clinic_id, (clientCounts.get(row.clinic_id) || 0) + 1);
    }
    const latestConversion = new Map<string, NonNullable<typeof conversionResult.data>[number]>();
    for (const row of conversionResult.data || []) {
      if (!latestConversion.has(row.clinic_id)) latestConversion.set(row.clinic_id, row);
    }
    const clinics = (clinicsResult.data || []).map((clinic) => ({
      ...clinic,
      subscription: subscriptions.get(clinic.id) || null,
      memberships: membershipCounts.get(clinic.id) || { owners: 0, dietitians: 0, secretaries: 0, total: 0 },
      active_clients: clientCounts.get(clinic.id) || 0,
      conversion_request: latestConversion.get(clinic.id) || null,
    }));

    return NextResponse.json({
      clinics,
      pilotInvites: invitesResult.data || [],
      pilotApplications: applicationsResult.data || [],
      feedback: feedbackResult.data || [],
      plans: plansResult.data || [],
      conversionRequests: conversionResult.data || [],
      metrics: {
        clinics: clinics.length,
        pilotClinics: clinics.filter((clinic) => clinic.subscription?.status === "pilot").length,
        activeUsers: (membershipsResult.data || []).filter((row) => row.is_active).length,
        activeClients: (clientsResult.data || []).filter((row) => row.is_active).length,
        openFeedback: (feedbackResult.data || []).filter((row) => row.status === "new" || row.status === "reviewing").length,
        openApplications: (applicationsResult.data || []).filter((row) => row.status === "new" || row.status === "contacted").length,
        pendingConversions: (conversionResult.data || []).filter((row) => row.status === "pending").length,
      },
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Veriler alınamadı" }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const user = await authorize();
  if (!user) return NextResponse.json({ error: "Yetkisiz erişim" }, { status: 403 });
  try {
    const body = await request.json() as Record<string, unknown>;
    const action = String(body.action || "");
    const admin = createAdminClient();

    if (action === "create_pilot_invite") {
      const label = String(body.label || "").trim();
      const contactEmail = String(body.contact_email || "").trim().toLowerCase() || null;
      const pilotDays = Math.min(365, Math.max(7, Number(body.pilot_days) || 90));
      const expiresDays = Math.min(90, Math.max(1, Number(body.expires_days) || 14));
      const maxUses = Math.min(20, Math.max(1, Number(body.max_uses) || 1));
      if (!label) return NextResponse.json({ error: "Pilot etiketi zorunludur" }, { status: 400 });
      const token = randomBytes(8).toString("hex").toUpperCase();
      const { data, error } = await admin.from("pilot_invites").insert({
        token,
        label,
        contact_email: contactEmail,
        plan_slug: "pilot",
        pilot_days: pilotDays,
        max_uses: maxUses,
        expires_at: new Date(Date.now() + expiresDays * 86400000).toISOString(),
        created_by_email: user.email,
      }).select().single();
      if (error) throw error;
      return NextResponse.json({ invite: data });
    }

    if (action === "extend_pilot") {
      const clinicId = String(body.clinic_id || "");
      const days = Math.min(365, Math.max(1, Number(body.days) || 30));
      const { data: current, error: readError } = await admin.from("clinic_subscriptions").select("pilot_ends_at").eq("clinic_id", clinicId).single();
      if (readError) throw readError;
      const base = current.pilot_ends_at && new Date(current.pilot_ends_at) > new Date() ? new Date(current.pilot_ends_at) : new Date();
      base.setUTCDate(base.getUTCDate() + days);
      const { error } = await admin.from("clinic_subscriptions").update({ pilot_ends_at: base.toISOString(), status: "pilot", updated_at: new Date().toISOString() }).eq("clinic_id", clinicId);
      if (error) throw error;
      await admin.from("clinics").update({ status: "pilot", updated_at: new Date().toISOString() }).eq("id", clinicId);
      await admin.from("audit_logs").insert({ clinic_id: clinicId, actor_user_id: user.id, action: "pilot_extended_by_platform", target_type: "clinic", target_id: clinicId, metadata: { days, by_email: user.email } });
      return NextResponse.json({ ok: true });
    }

    if (action === "approve_paid_access") {
      const clinicId = String(body.clinic_id || "");
      const requestId = String(body.request_id || "") || null;
      const planSlug = String(body.plan_slug || "");
      const billingCycle = String(body.billing_cycle || "monthly");
      const agreedPrice = body.agreed_price_try === "" || body.agreed_price_try === null || body.agreed_price_try === undefined ? null : Number(body.agreed_price_try);
      const approvalNote = String(body.approval_note || "").trim() || null;
      if (!clinicId) return NextResponse.json({ error: "Klinik kimliği zorunludur" }, { status: 400 });
      if (!planSlug || ["pilot", "founder"].includes(planSlug)) return NextResponse.json({ error: "Ücretli plan seçmelisiniz" }, { status: 400 });
      if (!["monthly", "annual", "manual"].includes(billingCycle)) return NextResponse.json({ error: "Faturalama dönemi geçersiz" }, { status: 400 });
      if (agreedPrice !== null && (!Number.isFinite(agreedPrice) || agreedPrice < 0)) return NextResponse.json({ error: "Anlaşılan fiyat geçersiz" }, { status: 400 });
      const { data: plan, error: planError } = await admin.from("subscription_plans").select("slug,monthly_price_try").eq("slug", planSlug).eq("is_active", true).single();
      if (planError) throw planError;
      const now = new Date();
      const periodEnd = new Date(now);
      if (billingCycle === "annual") periodEnd.setUTCFullYear(periodEnd.getUTCFullYear() + 1);
      else if (billingCycle === "monthly") periodEnd.setUTCMonth(periodEnd.getUTCMonth() + 1);
      const finalPrice = agreedPrice ?? Number(plan.monthly_price_try || 0);
      const { error } = await admin.from("clinic_subscriptions").update({
        plan_slug: planSlug,
        status: "active",
        current_period_started_at: now.toISOString(),
        current_period_ends_at: billingCycle === "manual" ? null : periodEnd.toISOString(),
        billing_cycle: billingCycle,
        agreed_price_try: finalPrice,
        commercial_approved_at: now.toISOString(),
        commercial_approved_by_email: user.email,
        commercial_approval_note: approvalNote,
        converted_from_pilot_at: now.toISOString(),
        cancel_at_period_end: false,
        updated_at: now.toISOString(),
      }).eq("clinic_id", clinicId);
      if (error) throw error;
      const clinicUpdate = await admin.from("clinics").update({ status: "active", updated_at: now.toISOString() }).eq("id", clinicId);
      if (clinicUpdate.error) throw clinicUpdate.error;
      if (requestId) {
        const requestUpdate = await admin.from("clinic_conversion_requests").update({ status: "approved", reviewed_by_email: user.email, reviewed_at: now.toISOString(), admin_note: approvalNote, updated_at: now.toISOString() }).eq("id", requestId).eq("clinic_id", clinicId);
        if (requestUpdate.error) throw requestUpdate.error;
      } else {
        await admin.from("clinic_conversion_requests").update({ status: "approved", reviewed_by_email: user.email, reviewed_at: now.toISOString(), admin_note: approvalNote, updated_at: now.toISOString() }).eq("clinic_id", clinicId).eq("status", "pending");
      }
      await admin.from("audit_logs").insert({ clinic_id: clinicId, actor_user_id: user.id, action: "clinic_paid_access_approved", target_type: "clinic", target_id: clinicId, metadata: { plan_slug: planSlug, billing_cycle: billingCycle, agreed_price_try: finalPrice, request_id: requestId, approved_by_email: user.email, note: approvalNote } });
      return NextResponse.json({ ok: true });
    }

    if (action === "reject_conversion_request") {
      const clinicId = String(body.clinic_id || "");
      const requestId = String(body.request_id || "");
      const adminNote = String(body.admin_note || "").trim() || null;
      if (!clinicId || !requestId) return NextResponse.json({ error: "Talep bilgisi eksik" }, { status: 400 });
      const { error } = await admin.from("clinic_conversion_requests").update({ status: "rejected", reviewed_by_email: user.email, reviewed_at: new Date().toISOString(), admin_note: adminNote, updated_at: new Date().toISOString() }).eq("id", requestId).eq("clinic_id", clinicId);
      if (error) throw error;
      await admin.from("audit_logs").insert({ clinic_id: clinicId, actor_user_id: user.id, action: "clinic_paid_conversion_rejected", target_type: "clinic", target_id: clinicId, metadata: { request_id: requestId, note: adminNote, reviewed_by_email: user.email } });
      return NextResponse.json({ ok: true });
    }

    if (action === "save_clinic_note") {
      const clinicId = String(body.clinic_id || "");
      const note = String(body.note || "").trim();
      if (!clinicId || note.length < 2) return NextResponse.json({ error: "Klinik notu en az 2 karakter olmalıdır" }, { status: 400 });
      const { error } = await admin.from("platform_clinic_notes").insert({ clinic_id: clinicId, note, created_by_email: user.email || "Platform Admin" });
      if (error) throw error;
      return NextResponse.json({ ok: true });
    }

    if (action === "set_clinic_status") {
      const clinicId = String(body.clinic_id || "");
      const status = String(body.status || "");
      if (!["active", "pilot", "paused", "expired", "cancelled"].includes(status)) return NextResponse.json({ error: "Durum geçersiz" }, { status: 400 });
      const { error } = await admin.from("clinics").update({ status, updated_at: new Date().toISOString() }).eq("id", clinicId);
      if (error) throw error;
      const subscriptionStatus = status === "active" ? "active" : status === "pilot" ? "pilot" : status;
      await admin.from("clinic_subscriptions").update({ status: subscriptionStatus, updated_at: new Date().toISOString() }).eq("clinic_id", clinicId);
      return NextResponse.json({ ok: true });
    }

    if (action === "change_plan") {
      const clinicId = String(body.clinic_id || "");
      const planSlug = String(body.plan_slug || "");
      const { error } = await admin.from("clinic_subscriptions").update({ plan_slug: planSlug, updated_at: new Date().toISOString() }).eq("clinic_id", clinicId);
      if (error) throw error;
      return NextResponse.json({ ok: true });
    }

    if (action === "set_invite_active") {
      const inviteId = String(body.invite_id || "");
      const isActive = Boolean(body.is_active);
      const { error } = await admin.from("pilot_invites").update({ is_active: isActive, updated_at: new Date().toISOString() }).eq("id", inviteId);
      if (error) throw error;
      return NextResponse.json({ ok: true });
    }

    if (action === "update_pilot_application") {
      const applicationId = String(body.application_id || "");
      const status = String(body.status || "contacted");
      const adminNote = String(body.admin_note || "").trim() || null;
      if (!["new", "contacted", "approved", "waitlist", "rejected", "closed"].includes(status)) {
        return NextResponse.json({ error: "Başvuru durumu geçersiz" }, { status: 400 });
      }
      const { error } = await admin.from("pilot_applications").update({
        status,
        admin_note: adminNote,
        reviewed_by_email: user.email,
        reviewed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("id", applicationId);
      if (error) throw error;
      return NextResponse.json({ ok: true });
    }

    if (action === "update_feedback") {
      const feedbackId = String(body.feedback_id || "");
      const status = String(body.status || "reviewing");
      const adminNote = String(body.admin_note || "").trim() || null;
      const { error } = await admin.from("pilot_feedback").update({ status, admin_note: adminNote, updated_at: new Date().toISOString() }).eq("id", feedbackId);
      if (error) throw error;
      return NextResponse.json({ ok: true });
    }

    return NextResponse.json({ error: "Bilinmeyen işlem" }, { status: 400 });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "İşlem başarısız" }, { status: 500 });
  }
}
