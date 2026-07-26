import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { generateAIText } from "@/lib/ai/provider";
import { cleanStringArray, cleanText, parseAIJson } from "@/lib/ai/safety";

export const runtime = "nodejs";
export const maxDuration = 60;

function normalizeScan(value: Record<string, unknown>) {
  const objectRows = (input: unknown) => (Array.isArray(input) ? input : [])
    .filter((row): row is Record<string, unknown> => Boolean(row && typeof row === "object" && !Array.isArray(row)));
  return {
    product_name: cleanText(value.product_name, 180),
    brand: cleanText(value.brand, 120) || null,
    label_readability: ["high", "medium", "low"].includes(String(value.label_readability)) ? String(value.label_readability) : "low",
    detected_ingredients: cleanStringArray(value.detected_ingredients, 80, 140),
    allergen_alerts: objectRows(value.allergen_alerts).slice(0, 30).map((row) => ({
      allergen: cleanText(row.allergen, 100),
      severity: ["high", "medium", "low"].includes(String(row.severity)) ? String(row.severity) : "low",
      reason: cleanText(row.reason, 400),
    })).filter((row) => row.allergen),
    additive_findings: objectRows(value.additive_findings).slice(0, 40).map((row) => ({
      code_or_name: cleanText(row.code_or_name, 100),
      note: cleanText(row.note, 400),
    })).filter((row) => row.code_or_name),
    marketing_claims: cleanStringArray(value.marketing_claims, 30, 180),
    suitability: ["uygun", "dikkat", "uygun_degil", "belirsiz"].includes(String(value.suitability)) ? String(value.suitability) : "belirsiz",
    summary: cleanText(value.summary, 1000),
    recommended_actions: cleanStringArray(value.recommended_actions, 10, 300),
    uncertainty_note: cleanText(value.uncertainty_note, 700, "Bu sonuç görsel okunabilirliğine bağlı yaklaşık bir AI analizidir; klinik değerlendirme yerine geçmez."),
  };
}

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Oturum gerekli." }, { status: 401 });
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) return NextResponse.json({ error: "Geçersiz istek." }, { status: 400 });

    const imageDataUrl = cleanText(body.image_data_url, 10_000_001);
    if (!/^data:image\/(?:jpeg|jpg|png|webp);base64,/i.test(imageDataUrl)) {
      return NextResponse.json({ error: "JPEG, PNG veya WebP biçiminde geçerli bir ürün etiketi fotoğrafı yükleyin." }, { status: 400 });
    }
    if (imageDataUrl.length > 10_000_000) return NextResponse.json({ error: "Fotoğraf çok büyük. Daha düşük çözünürlüklü bir görsel kullanın." }, { status: 413 });

    const { data: membership } = await supabase
      .from("clinic_memberships")
      .select("clinic_id,role,created_at")
      .eq("user_id", user.id)
      .eq("is_active", true)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (!membership) return NextResponse.json({ error: "Klinik üyeliği bulunamadı." }, { status: 403 });

    const { data: client } = await supabase
      .from("client_profiles")
      .select("id,allergies,disliked_foods,diet_style,additive_reactions")
      .eq("clinic_id", membership.clinic_id)
      .eq("user_id", user.id)
      .eq("is_active", true)
      .limit(1)
      .maybeSingle();

    const { error: creditError } = await supabase.rpc("consume_ai_credit_v7", { p_clinic_id: membership.clinic_id, p_units: 1 });
    if (creditError) return NextResponse.json({ error: creditError.message }, { status: 429 });

    const allergies = cleanStringArray(Array.isArray(body.allergies) ? body.allergies : client?.allergies, 30, 100);
    const disliked = cleanStringArray(Array.isArray(body.disliked_foods) ? body.disliked_foods : client?.disliked_foods, 30, 100);
    const additiveReactions = cleanStringArray(client?.additive_reactions, 30, 120);
    const dietStyle = cleanText(body.diet_style || client?.diet_style, 120, "Belirtilmedi");

    const prompt = `Bu görseldeki paketli gıdanın ön yüzünü, içindekiler listesini ve alerjen uyarılarını analiz et. NutriClinic AI danışan güvenliği ekranı için sonuç üret.
Kurallar:
- Görselde okunmayan veya belirsiz hiçbir içeriği uydurma.
- Alerjenleri kullanıcının profiliyle eşleştir; eser miktar/aynı hatta üretim uyarılarını da belirt.
- Katkı maddelerini etikette görüldüğü kadarıyla listele; kesin sağlık zararı iddiasında bulunma.
- Ön yüz pazarlama ifadeleri ile gerçek içindekiler/alerjen bilgisini birbirinden ayır.
- Görsel kalitesini ve okunabilirlik düzeyini ayrıca değerlendir.
- Ürünün neden uygun veya uygunsuz olduğunu üç maddelik eyleme dönük bir özetle açıkla.
- Sonucun tıbbi veya hukuki güvence olmadığını uncertainty_note alanında açıkla.
- Yalnızca geçerli JSON döndür; markdown kullanma.

Kullanıcı profili:
Alerjiler: ${allergies.join(", ") || "Yok/bildirilmedi"}
Sevilmeyen/kullanılmayan besinler: ${disliked.join(", ") || "Yok/bildirilmedi"}
Bildirilmiş katkı reaksiyonları: ${additiveReactions.join(", ") || "Yok/bildirilmedi"}
Beslenme tarzı: ${dietStyle}

JSON şeması:
{"product_name":"string","brand":"string|null","label_readability":"high|medium|low","detected_ingredients":["string"],"allergen_alerts":[{"allergen":"string","severity":"high|medium|low","reason":"string"}],"additive_findings":[{"code_or_name":"string","note":"string"}],"marketing_claims":["string"],"suitability":"uygun|dikkat|uygun_degil|belirsiz","summary":"string","recommended_actions":["string"],"uncertainty_note":"string"}`;

    const { text, provider, model } = await generateAIText({
      vision: true,
      content: [
        { type: "input_text", text: prompt },
        { type: "input_image", image_url: imageDataUrl, detail: "high" },
      ],
      maxOutputTokens: 1800,
    });
    const scan = normalizeScan(parseAIJson(text));

    const { error: insertError } = await supabase.from("food_label_scans").insert({
      clinic_id: membership.clinic_id,
      client_id: client?.id || null,
      created_by: user.id,
      filename: cleanText(body.filename, 180, "etiket.jpg"),
      result: { ...scan, ai_provider: provider, ai_model: model },
    });
    if (insertError) throw new Error(`Etiket analizi kaydedilemedi: ${insertError.message}`);
    return NextResponse.json({ scan, provider, model });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Etiket analizi yapılamadı." }, { status: 500 });
  }
}
