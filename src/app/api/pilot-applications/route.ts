import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

function text(value: unknown, max = 500) {
  return String(value ?? "").trim().slice(0, max);
}

export async function POST(request: Request) {
  try {
    const body = await request.json() as Record<string, unknown>;
    if (text(body.website, 120)) {
      return NextResponse.json({ ok: true });
    }

    const fullName = text(body.full_name, 120);
    const email = text(body.email, 180).toLowerCase();
    const phone = text(body.phone, 40) || null;
    const applicantType = text(body.applicant_type, 30) || "clinic_owner";
    const clinicName = text(body.clinic_name, 180) || null;
    const city = text(body.city, 100) || null;
    const message = text(body.message, 2000) || null;
    const teamSize = Math.min(1000, Math.max(1, Number(body.team_size) || 1));
    const activeClientCount = Math.min(1000000, Math.max(0, Number(body.active_client_count) || 0));
    const usesDevices = Boolean(body.uses_devices);

    if (!fullName) return NextResponse.json({ error: "Ad soyad zorunludur." }, { status: 400 });
    if (!/^\S+@\S+\.\S+$/.test(email)) return NextResponse.json({ error: "Geçerli bir e-posta adresi girin." }, { status: 400 });
    if (!["clinic_owner", "dietitian", "clinic_team", "other"].includes(applicantType)) {
      return NextResponse.json({ error: "Başvuru türü geçersiz." }, { status: 400 });
    }

    const admin = createAdminClient();
    const { data: recent } = await admin
      .from("pilot_applications")
      .select("id,created_at")
      .eq("email", email)
      .gte("created_at", new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
      .limit(1);
    if (recent?.length) {
      return NextResponse.json({ error: "Bu e-posta ile son 24 saat içinde zaten başvuru yapılmış." }, { status: 409 });
    }

    const { error } = await admin.from("pilot_applications").insert({
      full_name: fullName,
      email,
      phone,
      applicant_type: applicantType,
      clinic_name: clinicName,
      city,
      team_size: teamSize,
      active_client_count: activeClientCount,
      uses_devices: usesDevices,
      message,
      status: "new",
    });
    if (error) throw error;

    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Başvuru gönderilemedi." }, { status: 500 });
  }
}
