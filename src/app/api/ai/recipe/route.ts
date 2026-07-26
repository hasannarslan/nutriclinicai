import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { generateAIText } from "@/lib/ai/provider";
import { cleanStringArray, cleanText, finiteNumber, parseAIJson, safeJsonValue } from "@/lib/ai/safety";

export const runtime = "nodejs";
export const maxDuration = 60;

function normalizeRecipe(value: Record<string, unknown>) {
  const objectRows = (input: unknown) => (Array.isArray(input) ? input : [])
    .filter((row): row is Record<string, unknown> => Boolean(row && typeof row === "object" && !Array.isArray(row)));
  return {
    title: cleanText(value.title, 180, "Kişiselleştirilmiş tarif"),
    summary: cleanText(value.summary, 900),
    servings: finiteNumber(value.servings, { min: 1, max: 20, fallback: 1 }),
    prep_minutes: finiteNumber(value.prep_minutes, { min: 1, max: 600, fallback: 30 }),
    difficulty: ["Kolay", "Orta", "İleri"].includes(String(value.difficulty)) ? String(value.difficulty) : "Orta",
    calories: finiteNumber(value.calories, { min: 0, max: 20_000, fallback: 0 }),
    protein_g: finiteNumber(value.protein_g, { min: 0, max: 2_000, fallback: 0 }),
    carbs_g: finiteNumber(value.carbs_g, { min: 0, max: 2_000, fallback: 0 }),
    fat_g: finiteNumber(value.fat_g, { min: 0, max: 2_000, fallback: 0 }),
    fiber_g: finiteNumber(value.fiber_g, { min: 0, max: 1_000, fallback: 0 }),
    ingredients: cleanStringArray(value.ingredients, 60, 220),
    steps: cleanStringArray(value.steps, 40, 500),
    substitutions: objectRows(value.substitutions).slice(0, 20).map((row) => ({
      instead_of: cleanText(row.instead_of, 160),
      use: cleanText(row.use, 160),
      reason: cleanText(row.reason, 350),
    })).filter((row) => row.instead_of && row.use),
    shopping_list: cleanStringArray(value.shopping_list, 40, 180),
    tags: cleanStringArray(value.tags, 20, 80),
    allergy_notes: cleanStringArray(value.allergy_notes, 20, 300),
    suitability_note: cleanText(value.suitability_note, 700),
    clinical_caution: cleanText(value.clinical_caution, 700, "Tarif yaklaşık besin değerleri içerir ve diyetisyen değerlendirmesinin yerine geçmez."),
    confidence: ["high", "medium", "low"].includes(String(value.confidence)) ? String(value.confidence) : "low",
  };
}

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Oturum gerekli." }, { status: 401 });

    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) return NextResponse.json({ error: "Geçersiz istek." }, { status: 400 });
    const ingredients = cleanText(body.ingredients, 4000);
    if (!ingredients) return NextResponse.json({ error: "Malzeme bilgisi zorunludur." }, { status: 400 });

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
      .select("id,allergies,disliked_foods,diet_style")
      .eq("clinic_id", membership.clinic_id)
      .eq("user_id", user.id)
      .eq("is_active", true)
      .limit(1)
      .maybeSingle();

    const { error: creditError } = await supabase.rpc("consume_ai_credit_v7", { p_clinic_id: membership.clinic_id, p_units: 1 });
    if (creditError) return NextResponse.json({ error: creditError.message }, { status: 429 });

    const allergies = cleanStringArray(Array.isArray(body.allergies) ? body.allergies : client?.allergies, 30, 100);
    const disliked = cleanStringArray(Array.isArray(body.disliked_foods) ? body.disliked_foods : client?.disliked_foods, 30, 100);
    const dietStyle = cleanText(body.diet_style || client?.diet_style, 120, "Belirtilmedi");
    const maxCalories = finiteNumber(body.max_calories, { min: 50, max: 3000, fallback: 400 });
    const maxMinutes = finiteNumber(body.max_minutes, { min: 5, max: 240, fallback: 30 });
    const mealType = cleanText(body.meal_type, 80, "Öğün");
    const macroTargets = safeJsonValue(body.macro_targets, 2000);

    const prompt = `NutriClinic AI içinde çalışan klinik destekli tarif asistanısın. Kullanıcının evindeki malzemelerle tek bir uygulanabilir tarif üret.
Kurallar:
- Kullanıcının bildirilen alerjenlerini tarifte kesinlikle kullanma ve çapraz bulaşma riski varsa açıkça yaz.
- Sevmediği/kullanmadığı besinleri kullanma.
- Tıbbi tedavi veya hastalık iyileştirme iddiasında bulunma.
- Kalori ve makrolar yaklaşık değerlerdir; her malzeme için net gram/ml veya adet bilgisi ver ve porsiyon hesabını tutarlı yap.
- Tarif pratik, kültürel olarak uygulanabilir ve günlük hayatta bulunabilir malzemelerle hazırlanabilir olmalı.
- Kullanıcının aktif planına uyumu yüzdesel değil, kısa ve somut bir klinik uyum açıklamasıyla belirt.
- En az iki güvenli alternatif malzeme değişimi ve kısa alışveriş listesi üret.
- Maksimum hazırlama süresi ve kalori sınırına mümkün olduğunca uy.
- Yalnızca geçerli JSON döndür; markdown kullanma.

Girdi:
Malzemeler: ${ingredients}
Öğün türü: ${mealType}
Maksimum süre: ${maxMinutes} dakika
Maksimum kalori: ${maxCalories} kcal
Beslenme tarzı: ${dietStyle}
Alerjiler: ${allergies.join(", ") || "Yok/bildirilmedi"}
Sevilmeyen veya kullanılmayan besinler: ${disliked.join(", ") || "Yok/bildirilmedi"}
Aktif plan makro hedefleri: ${macroTargets}

JSON şeması:
{"title":"string","summary":"string","servings":number,"prep_minutes":number,"difficulty":"Kolay|Orta|İleri","calories":number,"protein_g":number,"carbs_g":number,"fat_g":number,"fiber_g":number,"ingredients":["miktarlı malzeme"],"steps":["string"],"substitutions":[{"instead_of":"string","use":"string","reason":"string"}],"shopping_list":["string"],"tags":["string"],"allergy_notes":["string"],"suitability_note":"string","clinical_caution":"string","confidence":"high|medium|low"}`;

    const { text, provider, model } = await generateAIText({
      content: [{ type: "input_text", text: prompt }],
      maxOutputTokens: 1800,
    });
    const recipe = normalizeRecipe(parseAIJson(text));

    const { error: insertError } = await supabase.from("ai_generated_recipes").insert({
      clinic_id: membership.clinic_id,
      client_id: client?.id || null,
      created_by: user.id,
      ingredients,
      meal_type: mealType,
      max_minutes: maxMinutes,
      max_calories: maxCalories,
      recipe: { ...recipe, ai_provider: provider, ai_model: model },
    });
    if (insertError) throw new Error(`Tarif kaydedilemedi: ${insertError.message}`);

    return NextResponse.json({ recipe, provider, model });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Tarif oluşturulamadı." }, { status: 500 });
  }
}
