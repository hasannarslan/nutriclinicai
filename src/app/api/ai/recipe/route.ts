import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { generateAIText } from "@/lib/ai/provider";

export const runtime = "nodejs";

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

    const body = await request.json();
    const ingredients = String(body.ingredients || "").trim();
    if (!ingredients) return NextResponse.json({ error: "Malzeme bilgisi zorunludur." }, { status: 400 });
    const [{ data: membership }, { data: client }] = await Promise.all([
      supabase.from("clinic_memberships").select("clinic_id,role").eq("user_id", user.id).eq("is_active", true).single(),
      supabase.from("client_profiles").select("id,allergies,disliked_foods,diet_style").eq("user_id", user.id).eq("is_active", true).maybeSingle(),
    ]);
    if (!membership) return NextResponse.json({ error: "Klinik üyeliği bulunamadı." }, { status: 403 });
    const { error: creditError } = await supabase.rpc("consume_ai_credit_v7", { p_clinic_id: membership.clinic_id, p_units: 1 });
    if (creditError) return NextResponse.json({ error: creditError.message }, { status: 429 });

    const allergies = Array.isArray(body.allergies) ? body.allergies : client?.allergies || [];
    const disliked = Array.isArray(body.disliked_foods) ? body.disliked_foods : client?.disliked_foods || [];
    const dietStyle = body.diet_style || client?.diet_style || "Belirtilmedi";
    const maxCalories = Number(body.max_calories) || 400;
    const maxMinutes = Number(body.max_minutes) || 30;
    const mealType = String(body.meal_type || "Öğün");
    const macroTargets = body.macro_targets || null;

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
Aktif plan makro hedefleri: ${JSON.stringify(macroTargets)}

JSON şeması:
{"title":"string","summary":"string","servings":number,"prep_minutes":number,"difficulty":"Kolay|Orta|İleri","calories":number,"protein_g":number,"carbs_g":number,"fat_g":number,"fiber_g":number,"ingredients":["miktarlı malzeme"],"steps":["string"],"substitutions":[{"instead_of":"string","use":"string","reason":"string"}],"shopping_list":["string"],"tags":["string"],"allergy_notes":["string"],"suitability_note":"string","clinical_caution":"string","confidence":"high|medium|low"}`;

    const { text, provider, model } = await generateAIText({
      content: [{ type: "input_text", text: prompt }],
      maxOutputTokens: 1800,
    });
    const recipe = parseJson(text);

    await supabase.from("ai_generated_recipes").insert({
      clinic_id: membership.clinic_id,
      client_id: client?.id || null,
      created_by: user.id,
      ingredients,
      meal_type: mealType,
      max_minutes: maxMinutes,
      max_calories: maxCalories,
      recipe: { ...recipe, ai_provider: provider, ai_model: model },
    });

    return NextResponse.json({ recipe, provider, model });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Tarif oluşturulamadı." }, { status: 500 });
  }
}
