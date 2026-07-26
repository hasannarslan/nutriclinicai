import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import {
  cleanEmail,
  cleanText,
  parseBoolean,
  parseBoundedInteger,
  publicErrorMessage,
  sameOriginRequest,
} from "@/lib/api-validation";

export const dynamic = "force-dynamic";

function json(body: unknown, status = 200) {
  return NextResponse.json(body, {
    status,
    headers: {
      "cache-control": "no-store, max-age=0",
      pragma: "no-cache",
    },
  });
}

export async function POST(request: Request) {
  if (!sameOriginRequest(request)) return json({ error: "Geçersiz istek kaynağı." }, 403);

  try {
    const contentLength = Number(request.headers.get("content-length") || 0);
    if (Number.isFinite(contentLength) && contentLength > 32_768) return json({ error: "Başvuru verisi çok büyük." }, 413);

    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) return json({ error: "Geçersiz başvuru verisi." }, 400);

    // Botların doldurması beklenen görünmez alan. Gerçek kullanıcıya başarılı cevap döndürülür.
    if (cleanText(body.website, 120)) return json({ ok: true });

    const fullName = cleanText(body.full_name, 120);
    const email = cleanEmail(body.email);
    const phoneValue = cleanText(body.phone, 40).replace(/[^0-9+()\-\s]/g, "");
    const phone = phoneValue || null;
    const applicantType = cleanText(body.applicant_type, 30) || "clinic_owner";
    const clinicName = cleanText(body.clinic_name, 180) || null;
    const city = cleanText(body.city, 100) || null;
    const message = cleanText(body.message, 2000) || null;
    const teamSize = parseBoundedInteger(body.team_size, 1, 1, 1000);
    const activeClientCount = parseBoundedInteger(body.active_client_count, 0, 0, 1_000_000);
    const usesDevices = parseBoolean(body.uses_devices, false);

    if (fullName.length < 2) return json({ error: "Ad soyad zorunludur." }, 400);
    if (!email) return json({ error: "Geçerli bir e-posta adresi girin." }, 400);
    if (!["clinic_owner", "dietitian", "clinic_team", "other"].includes(applicantType)) {
      return json({ error: "Başvuru türü geçersiz." }, 400);
    }

    const admin = createAdminClient();
    const { data: recent, error: recentError } = await admin
      .from("pilot_applications")
      .select("id,created_at")
      .eq("email", email)
      .gte("created_at", new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
      .limit(1);
    if (recentError) throw recentError;
    if (recent?.length) return json({ error: "Bu e-posta ile son 24 saat içinde zaten başvuru yapılmış." }, 409);

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

    return json({ ok: true });
  } catch (error) {
    return json({ error: publicErrorMessage(error, "Başvuru gönderilemedi.") }, 500);
  }
}
