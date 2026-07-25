import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { generateAIText } from "@/lib/ai/provider";

export const runtime = "nodejs";
export const maxDuration = 60;

type InputItem = { key: string; food_name: string; quantity_g?: number | null; portion_text?: string | null };

function parseJson(text: string) {
  const cleaned = text.replace(/^```json\s*/i, "").replace(/```$/i, "").trim();
  try { return JSON.parse(cleaned); } catch {
    const objectStart = cleaned.indexOf("{");
    const objectEnd = cleaned.lastIndexOf("}");
    if (objectStart >= 0 && objectEnd > objectStart) return JSON.parse(cleaned.slice(objectStart, objectEnd + 1));
    throw new Error("AI yanıtı geçerli JSON formatında değildi.");
  }
}

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Oturum gerekli." }, { status: 401 });

    const { data: membership } = await supabase
      .from("clinic_memberships")
      .select("clinic_id,role")
      .eq("user_id", user.id)
      .eq("is_active", true)
      .single();
    if (!membership || !["owner", "dietitian"].includes(membership.role)) {
      return NextResponse.json({ error: "Bu işlem yalnızca Klinik Sahibi veya Diyetisyen tarafından kullanılabilir." }, { status: 403 });
    }
    const body = await request.json();
    const items = (Array.isArray(body.items) ? body.items : [])
      .map((item: InputItem) => ({
        key: String(item.key || ""),
        food_name: String(item.food_name || "").trim(),
        quantity_g: item.quantity_g == null ? null : Number(item.quantity_g),
        portion_text: item.portion_text ? String(item.portion_text) : null,
      }))
      .filter((item: InputItem) => item.key && item.food_name)
      .slice(0, 30);
    if (!items.length) return NextResponse.json({ error: "Hesaplanacak besin bulunamadı." }, { status: 400 });
    const { error: creditError } = await supabase.rpc("consume_ai_credit_v7", { p_clinic_id: membership.clinic_id, p_units: 1 });
    if (creditError) return NextResponse.json({ error: creditError.message }, { status: 429 });

    const prompt = `NutriClinic AI için diyetisyen destekli besin hesaplama motorusun. Verilen her satır için porsiyona ait yaklaşık enerji ve makro değerlerini hesapla.

Zorunlu kurallar:
- Sonuçlar klinik karar yerine geçmez; güvenilir standart besin kompozisyonu bilgisine dayalı yaklaşık tahmin üret.
- Miktar gram/ml olarak verilmişse toplam değeri o miktara göre hesapla.
- Yalnızca porsiyon metni verilmişse yaygın porsiyon gramajını tahmin et ve estimated_quantity_g alanına yaz.
- Yemek birden çok bileşen içeriyorsa makul standart tarif varsayımı kullan, assumption alanında kısa açıkla.
- Belirsiz veya marka/yağ miktarına duyarlı yemeklerde confidence değerini düşür.
- Her input key aynen korunmalı.
- Sadece geçerli JSON döndür, markdown kullanma.

Girdi:
${JSON.stringify(items)}

JSON şeması:
{"items":[{"key":"string","food_name":"string","estimated_quantity_g":number,"calories":number,"protein_g":number,"carbs_g":number,"fat_g":number,"fiber_g":number,"confidence":"high|medium|low","assumption":"string","source_note":"Yaklaşık standart besin kompozisyonu"}],"clinical_note":"string"}`;

    const { text, provider, model } = await generateAIText({
      content: [{ type: "input_text", text: prompt }],
      maxOutputTokens: 3200,
    });
    const result = parseJson(text);
    return NextResponse.json({ ...result, provider, model });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Besin değerleri hesaplanamadı." }, { status: 500 });
  }
}
