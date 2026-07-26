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

function sum(values: Array<number | string | null | undefined>) {
  return values.reduce<number>((total, value) => total + Number(value || 0), 0);
}

export async function GET(_request: Request, context: { params: Promise<{ clinicId: string }> }) {
  const user = await authorize();
  if (!user) return NextResponse.json({ error: "Yetkisiz erişim" }, { status: 403 });

  try {
    const { clinicId } = await context.params;
    if (!clinicId) return NextResponse.json({ error: "Klinik kimliği zorunludur" }, { status: 400 });
    const admin = createAdminClient();

    const [clinicResult, subscriptionResult, membershipsResult, clientsResult, appointmentsResult, mealPlansResult, measurementsResult, paymentsResult, resourcesResult, packagesResult, feedbackResult, conversionResult, notesResult, auditResult] = await Promise.all([
      admin.from("clinics").select("id,name,slug,status,default_locale,timezone,phone,email,website,address,logo_url,accent_color,created_at,updated_at,onboarding_completed_at").eq("id", clinicId).single(),
      admin.from("clinic_subscriptions").select("id,clinic_id,plan_slug,status,pilot_started_at,pilot_ends_at,current_period_started_at,current_period_ends_at,billing_provider,cancel_at_period_end,limits_override,metadata,commercial_approved_at,commercial_approved_by_email,commercial_approval_note,agreed_price_try,billing_cycle,converted_from_pilot_at,created_at,updated_at").eq("clinic_id", clinicId).maybeSingle(),
      admin.from("clinic_memberships").select("id,user_id,role,is_active,created_at,updated_at").eq("clinic_id", clinicId).order("created_at"),
      admin.from("client_profiles").select("id,member_no,full_name,email,phone,is_active,created_at,updated_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }),
      admin.from("appointments").select("id,status,starts_at,created_at").eq("clinic_id", clinicId),
      admin.from("meal_plans").select("id,status,created_at,updated_at").eq("clinic_id", clinicId),
      admin.from("measurements").select("id,measured_at").eq("clinic_id", clinicId),
      admin.from("payments").select("id,amount,paid_amount,remaining_amount,currency,status,paid_at,due_date,created_at").eq("clinic_id", clinicId),
      admin.from("clinic_resources").select("id,name,resource_type,is_active,created_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }),
      admin.from("client_packages").select("id,name,status,total_price,currency,created_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }),
      admin.from("pilot_feedback").select("id,category,rating,message,page_path,status,admin_note,created_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(20),
      admin.from("clinic_conversion_requests").select("id,requested_by,requested_plan_slug,note,status,reviewed_by_email,reviewed_at,admin_note,created_at,updated_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(20),
      admin.from("platform_clinic_notes").select("id,note,created_by_email,created_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(30),
      admin.from("audit_logs").select("id,actor_user_id,action,target_type,target_id,metadata,created_at").eq("clinic_id", clinicId).order("created_at", { ascending: false }).limit(30),
    ]);

    const results = [clinicResult, subscriptionResult, membershipsResult, clientsResult, appointmentsResult, mealPlansResult, measurementsResult, paymentsResult, resourcesResult, packagesResult, feedbackResult, conversionResult, notesResult, auditResult];
    const firstError = results.find((result) => result.error)?.error;
    if (firstError) throw firstError;

    const memberships = membershipsResult.data || [];
    const userIds = Array.from(new Set(memberships.map((item) => item.user_id).filter(Boolean)));
    const profilesResult = userIds.length
      ? await admin.from("profiles").select("id,full_name,email,phone,preferred_locale,created_at,updated_at").in("id", userIds)
      : { data: [], error: null };
    if (profilesResult.error) throw profilesResult.error;
    const profileMap = new Map((profilesResult.data || []).map((profile) => [profile.id, profile]));

    const subscription = subscriptionResult.data;
    const planResult = subscription?.plan_slug
      ? await admin.from("subscription_plans").select("slug,name,description,monthly_price_try,max_dietitians,max_staff,max_active_clients,monthly_ai_credits,storage_gb,features").eq("slug", subscription.plan_slug).maybeSingle()
      : { data: null, error: null };
    if (planResult.error) throw planResult.error;

    const appointments = appointmentsResult.data || [];
    const payments = paymentsResult.data || [];
    const now = Date.now();
    const paymentCurrencies = Array.from(new Set(payments.map((item) => item.currency || "TRY")));
    const financials = paymentCurrencies.map((currency) => {
      const rows = payments.filter((item) => (item.currency || "TRY") === currency && !["cancelled", "refunded"].includes(item.status));
      return {
        currency,
        total: sum(rows.map((item) => item.amount)),
        paid: sum(rows.map((item) => item.paid_amount)),
        remaining: sum(rows.map((item) => item.remaining_amount)),
      };
    });

    const members = memberships.map((membership) => ({
      ...membership,
      profile: profileMap.get(membership.user_id) || null,
    }));

    return NextResponse.json({
      clinic: clinicResult.data,
      subscription: subscription ? { ...subscription, plan: planResult.data } : null,
      members,
      clients: clientsResult.data || [],
      resources: resourcesResult.data || [],
      packages: packagesResult.data || [],
      feedback: feedbackResult.data || [],
      conversionRequests: conversionResult.data || [],
      notes: notesResult.data || [],
      audit: auditResult.data || [],
      stats: {
        members: {
          total: members.filter((item) => item.is_active).length,
          owners: members.filter((item) => item.is_active && item.role === "owner").length,
          dietitians: members.filter((item) => item.is_active && item.role === "dietitian").length,
          secretaries: members.filter((item) => item.is_active && item.role === "secretary").length,
        },
        clients: {
          active: (clientsResult.data || []).filter((item) => item.is_active).length,
          total: (clientsResult.data || []).length,
        },
        appointments: {
          total: appointments.length,
          upcoming: appointments.filter((item) => new Date(item.starts_at).getTime() >= now && ["pending", "confirmed"].includes(item.status)).length,
          completed: appointments.filter((item) => item.status === "completed").length,
          cancelled: appointments.filter((item) => item.status === "cancelled").length,
          no_show: appointments.filter((item) => item.status === "no_show").length,
        },
        mealPlans: {
          total: (mealPlansResult.data || []).length,
          active: (mealPlansResult.data || []).filter((item) => item.status === "active").length,
        },
        measurements: (measurementsResult.data || []).length,
        resources: {
          total: (resourcesResult.data || []).length,
          active: (resourcesResult.data || []).filter((item) => item.is_active).length,
        },
        packages: {
          total: (packagesResult.data || []).length,
          active: (packagesResult.data || []).filter((item) => item.status === "active").length,
        },
        feedback: {
          total: (feedbackResult.data || []).length,
          open: (feedbackResult.data || []).filter((item) => ["new", "reviewing", "planned"].includes(item.status)).length,
        },
        financials,
      },
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Klinik detayları alınamadı" }, { status: 500 });
  }
}
