import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { generateAIText } from "@/lib/ai/provider";

export const runtime = "nodejs";

function parseJson(text: string) {
  const cleaned = text.replace(/^```json\s*/i, "").replace(/```$/i, "").trim();
  return JSON.parse(cleaned);
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
- Kalori ve makrolar yaklaşık değerlerdir; porsiyon hesabını tutarlı yap.
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
{"title":"string","summary":"string","prep_minutes":number,"difficulty":"Kolay|Orta|İleri","calories":number,"protein_g":number,"carbs_g":number,"fat_g":number,"ingredients":["string"],"steps":["string"],"tags":["string"],"allergy_notes":["string"],"suitability_note":"string"}`;

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
