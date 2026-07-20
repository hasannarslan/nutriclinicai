import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { generateAIText } from "@/lib/ai/provider";

export const runtime = "nodejs";
export const maxDuration = 60;

function parseJson(text: string) {
  return JSON.parse(text.replace(/^```json\s*/i, "").replace(/```$/i, "").trim());
}

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Oturum gerekli." }, { status: 401 });
    const body = await request.json();
    const imageDataUrl = String(body.image_data_url || "");
    if (!imageDataUrl.startsWith("data:image/")) return NextResponse.json({ error: "Geçerli bir ürün etiketi fotoğrafı yükleyin." }, { status: 400 });
    if (imageDataUrl.length > 10_000_000) return NextResponse.json({ error: "Fotoğraf çok büyük. Daha düşük çözünürlüklü bir görsel kullanın." }, { status: 413 });
    const [{ data: membership }, { data: client }] = await Promise.all([
      supabase.from("clinic_memberships").select("clinic_id,role").eq("user_id", user.id).eq("is_active", true).single(),
      supabase.from("client_profiles").select("id,allergies,disliked_foods,diet_style,additive_reactions").eq("user_id", user.id).eq("is_active", true).maybeSingle(),
    ]);
    if (!membership) return NextResponse.json({ error: "Klinik üyeliği bulunamadı." }, { status: 403 });
    const allergies = Array.isArray(body.allergies) ? body.allergies : client?.allergies || [];
    const disliked = Array.isArray(body.disliked_foods) ? body.disliked_foods : client?.disliked_foods || [];
    const additiveReactions = client?.additive_reactions || [];
    const dietStyle = body.diet_style || client?.diet_style || "Belirtilmedi";

    const prompt = `Bu görseldeki paketli gıdanın ön yüzünü, içindekiler listesini ve alerjen uyarılarını analiz et. NutriClinic AI danışan güvenliği ekranı için sonuç üret.
Kurallar:
- Görselde okunmayan veya belirsiz hiçbir içeriği uydurma.
- Alerjenleri kullanıcının profiliyle eşleştir; eser miktar/aynı hatta üretim uyarılarını da belirt.
- Katkı maddelerini etikette görüldüğü kadarıyla listele; kesin sağlık zararı iddiasında bulunma.
- Sonucun tıbbi veya hukuki güvence olmadığını uncertainty_note alanında açıkla.
- Yalnızca geçerli JSON döndür; markdown kullanma.

Kullanıcı profili:
Alerjiler: ${allergies.join(", ") || "Yok/bildirilmedi"}
Sevilmeyen/kullanılmayan besinler: ${disliked.join(", ") || "Yok/bildirilmedi"}
Bildirilmiş katkı reaksiyonları: ${additiveReactions.join(", ") || "Yok/bildirilmedi"}
Beslenme tarzı: ${dietStyle}

JSON şeması:
{"product_name":"string","detected_ingredients":["string"],"allergen_alerts":[{"allergen":"string","severity":"high|medium|low","reason":"string"}],"additive_findings":[{"code_or_name":"string","note":"string"}],"suitability":"uygun|dikkat|uygun_degil|belirsiz","summary":"string","uncertainty_note":"string"}`;

    const { text, provider, model } = await generateAIText({
      vision: true,
      content: [
        { type: "input_text", text: prompt },
        { type: "input_image", image_url: imageDataUrl, detail: "high" },
      ],
      maxOutputTokens: 1800,
    });
    const scan = parseJson(text);

    await supabase.from("food_label_scans").insert({
      clinic_id: membership.clinic_id,
      client_id: client?.id || null,
      created_by: user.id,
      filename: String(body.filename || "etiket.jpg"),
      result: { ...scan, ai_provider: provider, ai_model: model },
    });
    return NextResponse.json({ scan, provider, model });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Etiket analizi yapılamadı." }, { status: 500 });
  }
}
