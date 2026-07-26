import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { generateAIText } from "@/lib/ai/provider";
import { cleanText, finiteNumber, parseAIJson } from "@/lib/ai/safety";

export const runtime = "nodejs";
export const maxDuration = 60;

type InputItem = { key?: unknown; food_name?: unknown; quantity_g?: unknown; portion_text?: unknown };

function normalizeResult(value: Record<string, unknown>, allowedKeys: Set<string>) {
  const rows = Array.isArray(value.items) ? value.items : [];
  const items = rows
    .filter((row): row is Record<string, unknown> => Boolean(row && typeof row === "object" && !Array.isArray(row)))
    .map((row) => ({
      key: cleanText(row.key, 80),
      food_name: cleanText(row.food_name, 160),
      estimated_quantity_g: finiteNumber(row.estimated_quantity_g, { min: 0, max: 100_000, fallback: 0 }),
      calories: finiteNumber(row.calories, { min: 0, max: 100_000, fallback: 0 }),
      protein_g: finiteNumber(row.protein_g, { min: 0, max: 10_000, fallback: 0 }),
      carbs_g: finiteNumber(row.carbs_g, { min: 0, max: 10_000, fallback: 0 }),
      fat_g: finiteNumber(row.fat_g, { min: 0, max: 10_000, fallback: 0 }),
      fiber_g: finiteNumber(row.fiber_g, { min: 0, max: 10_000, fallback: 0 }),
      confidence: ["high", "medium", "low"].includes(String(row.confidence)) ? String(row.confidence) : "low",
      assumption: cleanText(row.assumption, 500),
      source_note: cleanText(row.source_note, 300, "Yaklaşık standart besin kompozisyonu"),
    }))
    .filter((row) => allowedKeys.has(row.key));
  if (!items.length) throw new Error("AI, kullanılabilir besin sonucu döndürmedi.");
  return { items, clinical_note: cleanText(value.clinical_note, 600) };
}

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Oturum gerekli." }, { status: 401 });

    const { data: membership } = await supabase
      .from("clinic_memberships")
      .select("clinic_id,role,created_at")
      .eq("user_id", user.id)
      .eq("is_active", true)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (!membership || !["owner", "dietitian"].includes(membership.role)) {
      return NextResponse.json({ error: "Bu işlem yalnızca Klinik Sahibi veya Diyetisyen tarafından kullanılabilir." }, { status: 403 });
    }

    const body = await request.json().catch(() => null) as { items?: InputItem[] } | null;
    const items = (Array.isArray(body?.items) ? body.items : [])
      .map((item, index) => ({
        key: cleanText(item.key, 80, `item-${index + 1}`),
        food_name: cleanText(item.food_name, 160),
        quantity_g: item.quantity_g == null ? null : finiteNumber(item.quantity_g, { min: 0.1, max: 100_000, fallback: 100 }),
        portion_text: item.portion_text == null ? null : cleanText(item.portion_text, 120),
      }))
      .filter((item) => item.key && item.food_name)
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
    const result = normalizeResult(parseAIJson(text), new Set(items.map((item) => item.key)));
    return NextResponse.json({ ...result, provider, model });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Besin değerleri hesaplanamadı." }, { status: 500 });
  }
}
