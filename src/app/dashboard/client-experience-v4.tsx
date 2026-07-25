"use client";
/* eslint-disable @next/next/no-img-element */

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Activity, AlertTriangle, Apple, ArrowLeft, Beef, BrainCircuit, CalendarDays, Camera,
  Check, ChevronLeft, ChevronRight, CircleGauge, Clock3, Droplets, Dumbbell, Flame,
  HeartPulse, ImagePlus, LoaderCircle, Minus, Plus, RefreshCw, Salad, Scale, ScanLine,
  Sparkles, Target, UtensilsCrossed, WandSparkles, Weight, X, WalletCards, CreditCard, CheckCircle2, ShieldCheck,
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";

const goals = [
  ["lose_weight", "Kilo vermek", "⚖️"],
  ["maintain_weight", "Kiloyu korumak", "🎯"],
  ["gain_muscle", "Kas yapmak", "💪"],
  ["feel_fitter", "Daha formda olmak", "🥗"],
  ["improve_health", "Genel sağlığı iyileştirmek", "❤️"],
];
const motivations = ["Forma girmek", "Alerjenlerden kaçınmak", "Kronik durumu desteklemek", "Enerjiyi artırmak", "Daha düzenli beslenmek"];
const activities = [
  ["sedentary", "Aktif değil", "Günün çoğu oturarak geçiyor"],
  ["light", "Hafif aktif", "Haftada 1–2 hafif aktivite"],
  ["moderate", "Orta aktif", "Haftada 3–4 egzersiz"],
  ["active", "Aktif", "Haftada 5+ egzersiz"],
];
const conditions = ["Hipertansiyon", "Hiperlipidemi", "Diyabet", "GÖRH (Reflü)", "Yağlı Karaciğer", "Hipotiroidizm", "Laktoz İntoleransı", "IBS", "PKOS", "İBH", "Hipertiroidizm", "Çölyak"];
const dietStyles = ["Dengeli", "Vejetaryen", "Düşük karbonhidrat", "Yüksek protein", "Glütensiz", "Sütsüz", "Ketojenik"];
const allergens = ["Yer fıstığı", "Sert kabuklu yemişler", "Süt ürünleri", "Yumurta", "Kabuklu deniz ürünleri", "Balık", "Soya", "Gluten", "Susam", "Sülfitler", "Hardal", "Yumuşakçalar", "Tohumlar"];
const reactions = ["Mide problemi", "Cilt döküntüleri / Kurdeşen", "Baş ağrısı / Baş dönmesi", "Solunum sorunları", "Yorgunluk / Ruh hali değişimleri"];

type Onboarding = {
  completed: boolean;
  primary_goal: string;
  motivation_reasons: string[];
  gender: string;
  birth_date: string;
  height_cm: number | null;
  current_weight_kg: number | null;
  target_weight_kg: number | null;
  activity_level: string;
  calorie_knowledge: string;
  diet_style: string;
  chronic_conditions: string[];
  allergies: string[];
  additive_reactions: string[];
  water_goal_ml: number;
  goal_pace_kg_per_week: number;
};

type DailyHub = {
  date: string;
  client: {
    id: string;
    name: string;
    goal: string | null;
    height_cm: number | null;
    current_weight_kg: number | null;
    target_weight_kg: number | null;
    water_goal_ml: number;
    allergies: string[];
    disliked_foods: string[];
    diet_style: string | null;
  };
  plan: null | {
    id: string;
    title: string;
    target_calories: number;
    target_protein_g: number;
    target_carbs_g: number;
    target_fat_g: number;
    dietitian_note: string | null;
  };
  consumed: { calories: number; protein_g: number; carbs_g: number; fat_g: number };
  meals: Array<{
    id: string; meal_name: string; food_name: string; portion_text: string | null;
    calories: number; protein_g: number; carbs_g: number; fat_g: number; completed: boolean;
  }>;
  water_ml: number;
  burned_calories: number;
  weight_history: Array<{ date: string; weight_kg: number }>;
  activities: Array<{ id:string; activity_type:string; duration_minutes:number; calories_burned:number; note:string|null; created_at:string }>;
};

type RecipeResult = {
  title: string;
  summary: string;
  prep_minutes: number;
  difficulty: string;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  fiber_g?: number;
  servings?: number;
  confidence?: string;
  clinical_caution?: string;
  substitutions?: Array<{instead_of:string;use:string;reason:string}>;
  shopping_list?: string[];
  ingredients: string[];
  steps: string[];
  tags: string[];
  allergy_notes: string[];
  suitability_note: string;
};

type ScanResult = {
  product_name?: string;
  brand?: string|null;
  label_readability?: string;
  recommended_actions?: string[];
  marketing_claims?: string[];
  detected_ingredients: string[];
  allergen_alerts: Array<{ allergen: string; severity: "high" | "medium" | "low"; reason: string }>;
  additive_findings: Array<{ code_or_name: string; note: string }>;
  suitability: "uygun" | "dikkat" | "uygun_degil" | "belirsiz";
  summary: string;
  uncertainty_note: string;
};

type ClientPayment = {
  id: string;
  service_type: string;
  description: string | null;
  amount: number;
  paid_amount: number;
  remaining_amount: number;
  currency: string;
  status: "pending" | "partial" | "paid" | "refunded" | "cancelled";
  method: "cash" | "card" | "iban" | "other" | null;
  paid_at: string | null;
  created_at: string;
  due_date: string | null;
  reminder_sent_at: string | null;
};

function money(value: number) {
  return new Intl.NumberFormat("tr-TR", { style: "currency", currency: "TRY" }).format(Number(value || 0));
}
function paymentStatusText(status: ClientPayment["status"] | null) {
  return ({ pending: "Ödeme bekliyor", partial: "Kısmi ödeme", paid: "Ödeme alındı", refunded: "İade edildi", cancelled: "İptal edildi" } as Record<string, string>)[status || ""] || "Ödeme kaydı yok";
}
function paymentMethodText(method: ClientPayment["method"]) {
  return ({ cash: "Nakit", card: "Kart", iban: "IBAN", other: "Diğer" } as Record<string, string>)[method || ""] || "Yöntem belirtilmedi";
}

function toggle(list: string[], value: string) {
  return list.includes(value) ? list.filter((item) => item !== value) : [...list, value];
}
function dateKey(date: Date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}
function ageFromDate(value: string) {
  if (!value) return null;
  const birth = new Date(value);
  const now = new Date();
  let age = now.getFullYear() - birth.getFullYear();
  const month = now.getMonth() - birth.getMonth();
  if (month < 0 || (month === 0 && now.getDate() < birth.getDate())) age -= 1;
  return age;
}
function bmi(height: number | null, weight: number | null) {
  if (!height || !weight) return null;
  return weight / Math.pow(height / 100, 2);
}
function bmiStatus(value: number | null) {
  if (!value) return "Veri bekleniyor";
  if (value < 18.5) return "Düşük kilo";
  if (value < 25) return "Sağlıklı aralık";
  if (value < 30) return "Kilolu aralık";
  return "Obezite aralığı";
}
function healthyRange(height: number | null) {
  if (!height) return null;
  const meter2 = Math.pow(height / 100, 2);
  return [18.5 * meter2, 24.9 * meter2];
}
function goalLabel(key: string) {
  return goals.find(([value]) => value === key)?.[1] || key;
}

export function ClientExperienceV4({ clinicId }: { clinicId: string }) {
  const supabase = useMemo(() => createClient(), []);
  const [data, setData] = useState<Onboarding | null>(null);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    const { data: result, error } = await supabase.rpc("get_my_onboarding_v4");
    if (error) setMessage(error.message);
    else setData(result as Onboarding);
    setLoading(false);
  }, [supabase]);

  useEffect(() => { void load(); }, [load, clinicId]);

  if (loading) return <div className="v4-center"><LoaderCircle className="spin" /><p>Kişisel profil hazırlanıyor…</p></div>;
  if (!data) return <div className="notice-bar"><AlertTriangle size={17} />{message || "Danışan profili bulunamadı."}</div>;
  if (!data.completed) return <OnboardingWizard initial={data} onCompleted={setData} />;
  return <ClientDailyHub onboarding={data} clinicId={clinicId} />;
}

function OnboardingWizard({ initial, onCompleted }: { initial: Onboarding; onCompleted: (value: Onboarding) => void }) {
  const supabase = useMemo(() => createClient(), []);
  const [step, setStep] = useState(0);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [form, setForm] = useState<Onboarding>({
    ...initial,
    primary_goal: initial.primary_goal || "",
    motivation_reasons: initial.motivation_reasons || [],
    gender: initial.gender || "",
    birth_date: initial.birth_date || "",
    height_cm: initial.height_cm || 170,
    current_weight_kg: initial.current_weight_kg || 70,
    target_weight_kg: initial.target_weight_kg || 65,
    activity_level: initial.activity_level || "",
    calorie_knowledge: initial.calorie_knowledge || "",
    diet_style: initial.diet_style || "Dengeli",
    chronic_conditions: initial.chronic_conditions || [],
    allergies: initial.allergies || [],
    additive_reactions: initial.additive_reactions || [],
    water_goal_ml: initial.water_goal_ml || 2000,
    goal_pace_kg_per_week: initial.goal_pace_kg_per_week || 0.5,
  });

  const totalSteps = 10;
  const currentBmi = bmi(form.height_cm, form.current_weight_kg);
  const range = healthyRange(form.height_cm);
  const difference = Math.abs((form.current_weight_kg || 0) - (form.target_weight_kg || 0));
  const weeks = form.goal_pace_kg_per_week ? Math.ceil(difference / form.goal_pace_kg_per_week) : 0;
  const estimatedDate = new Date(); estimatedDate.setDate(estimatedDate.getDate() + weeks * 7);

  function canContinue() {
    if (step === 0) return Boolean(form.primary_goal);
    if (step === 1) return form.motivation_reasons.length > 0;
    if (step === 2) return Boolean(form.gender);
    if (step === 3) return Boolean(form.birth_date);
    if (step === 4) return Boolean(form.height_cm && form.current_weight_kg);
    if (step === 5) return Boolean(form.target_weight_kg);
    if (step === 7) return Boolean(form.activity_level);
    if (step === 8) return Boolean(form.calorie_knowledge);
    return true;
  }

  async function finish() {
    setSaving(true); setMessage("");
    const { data, error } = await supabase.rpc("complete_client_onboarding_v4", {
      p_primary_goal: form.primary_goal,
      p_motivation_reasons: form.motivation_reasons,
      p_gender: form.gender,
      p_birth_date: form.birth_date,
      p_height_cm: form.height_cm,
      p_current_weight_kg: form.current_weight_kg,
      p_target_weight_kg: form.target_weight_kg,
      p_activity_level: form.activity_level,
      p_calorie_knowledge: form.calorie_knowledge,
      p_diet_style: form.diet_style,
      p_chronic_conditions: form.chronic_conditions,
      p_allergies: form.allergies,
      p_additive_reactions: form.additive_reactions,
      p_water_goal_ml: form.water_goal_ml,
      p_goal_pace_kg_per_week: form.goal_pace_kg_per_week,
    });
    if (error) setMessage(error.message);
    else onCompleted(data as Onboarding);
    setSaving(false);
  }

  const content = [
    <ChoiceStep key="goal" title="Hedefiniz nedir?" description="Diyetisyeniniz planınızı bu hedefi dikkate alarak hazırlayacak.">
      <div className="v4-choice-list">{goals.map(([value, label, emoji]) => <button key={value} className={form.primary_goal === value ? "selected" : ""} onClick={() => setForm({ ...form, primary_goal: value })}><span>{emoji}</span><b>{label}</b><i>{form.primary_goal === value && <Check size={18} />}</i></button>)}</div>
    </ChoiceStep>,
    <ChoiceStep key="motivation" title="Sizi buraya getiren nedir?" description="Birden fazla neden seçebilirsiniz.">
      <div className="v4-choice-list compact">{motivations.map((value) => <button key={value} className={form.motivation_reasons.includes(value) ? "selected" : ""} onClick={() => setForm({ ...form, motivation_reasons: toggle(form.motivation_reasons, value) })}><b>{value}</b><i>{form.motivation_reasons.includes(value) && <Check size={18} />}</i></button>)}</div>
    </ChoiceStep>,
    <ChoiceStep key="gender" title="Cinsiyetinizi seçin" description="Metabolizma tahmininde kullanılan temel bilgilerden biridir.">
      <div className="v4-two-choice"><button className={form.gender === "male" ? "selected" : ""} onClick={() => setForm({ ...form, gender: "male" })}><span>👨</span><b>Erkek</b></button><button className={form.gender === "female" ? "selected" : ""} onClick={() => setForm({ ...form, gender: "female" })}><span>👩</span><b>Kadın</b></button></div><button className={`v4-pill-choice ${form.gender === "unspecified" ? "selected" : ""}`} onClick={() => setForm({ ...form, gender: "unspecified" })}>Belirtmek istemiyorum</button>
    </ChoiceStep>,
    <ChoiceStep key="birth" title="Ne zaman doğdunuz?" description="Yaş, enerji gereksinimi değerlendirmesinde kullanılır.">
      <div className="v4-single-input"><CalendarDays /><input type="date" value={form.birth_date} onChange={(e) => setForm({ ...form, birth_date: e.target.value })} /><strong>{ageFromDate(form.birth_date) ? `${ageFromDate(form.birth_date)} yaş` : "Tarih seçin"}</strong></div>
    </ChoiceStep>,
    <ChoiceStep key="body" title="Boy ve mevcut kilo" description="Bu değerler yalnızca tahmini analiz üretir; klinik ölçümünün yerine geçmez.">
      <div className="v4-measure-grid"><label><span>Boy</span><div><input type="number" min="100" max="250" step="0.5" value={form.height_cm || ""} onChange={(e) => setForm({ ...form, height_cm: Number(e.target.value) })} /><b>cm</b></div></label><label><span>Mevcut kilo</span><div><input type="number" min="20" max="500" step="0.1" value={form.current_weight_kg || ""} onChange={(e) => setForm({ ...form, current_weight_kg: Number(e.target.value) })} /><b>kg</b></div></label></div>
    </ChoiceStep>,
    <ChoiceStep key="target" title="Hedef kilonuz nedir?" description="Hedefiniz diyetisyen tarafından klinik değerlendirme sonrası revize edilebilir.">
      <div className="v4-target-weight"><Target /><input type="number" min="20" max="500" step="0.1" value={form.target_weight_kg || ""} onChange={(e) => setForm({ ...form, target_weight_kg: Number(e.target.value) })} /><b>kg</b></div><label className="v4-range-label">Haftalık hedef temposu <strong>{form.goal_pace_kg_per_week.toFixed(1)} kg</strong><input type="range" min="0.1" max="1.5" step="0.1" value={form.goal_pace_kg_per_week} onChange={(e) => setForm({ ...form, goal_pace_kg_per_week: Number(e.target.value) })} /></label>
    </ChoiceStep>,
    <ChoiceStep key="analysis" title="Kişisel ön analiziniz" description="Bu ekran tıbbi tanı değildir; diyetisyeninizin değerlendirmesine yardımcı olur.">
      <div className="v4-analysis-card"><div className="v4-analysis-top"><span><small>Yaş</small><b>{ageFromDate(form.birth_date) || "—"}</b></span><span><small>Boy</small><b>{form.height_cm} cm</b></span><span><small>Kilo</small><b>{form.current_weight_kg} kg</b></span></div><div className="v4-bmi"><CircleGauge /><div><small>Beden kütle indeksi</small><strong>{currentBmi?.toFixed(1) || "—"}</strong><b>{bmiStatus(currentBmi)}</b></div></div><div className="v4-analysis-facts"><p>Sağlıklı BMI aralığı: <b>18.5–24.9</b></p><p>Tahmini sağlıklı kilo aralığı: <b>{range ? `${range[0].toFixed(1)}–${range[1].toFixed(1)} kg` : "—"}</b></p><p>Seçilen hedef: <b>{form.target_weight_kg} kg</b></p></div></div>
    </ChoiceStep>,
    <ChoiceStep key="activity" title="Aktivite seviyeniz nedir?" description="Günlük enerji ihtiyacının hesaplanmasına yardımcı olur.">
      <div className="v4-activity-grid">{activities.map(([value, label, description]) => <button key={value} className={form.activity_level === value ? "selected" : ""} onClick={() => setForm({ ...form, activity_level: value })}><Dumbbell /><b>{label}</b><small>{description}</small></button>)}</div>
    </ChoiceStep>,
    <ChoiceStep key="knowledge" title="Kalori ve kilo ilişkisini ne kadar biliyorsunuz?" description="Eğitim içeriklerinin seviyesini size göre ayarlarız.">
      <div className="v4-choice-list compact">{[["good", "Evet, temel ilişkiyi biliyorum"], ["some", "Kısmen biliyorum"], ["new", "Bu konuda desteğe ihtiyacım var"]].map(([value, label]) => <button key={value} className={form.calorie_knowledge === value ? "selected" : ""} onClick={() => setForm({ ...form, calorie_knowledge: value })}><b>{label}</b><i>{form.calorie_knowledge === value && <Check size={18} />}</i></button>)}</div>
    </ChoiceStep>,
    <ChoiceStep key="health" title="Beslenme ve sağlık tercihleri" description="Alerji ve sağlık bildirimleri menü yazılırken diyetisyene otomatik uyarı verir.">
      <div className="v4-health-step"><h3>Kronik durumlar</h3><div className="v4-chip-grid">{conditions.map((value) => <button key={value} className={form.chronic_conditions.includes(value) ? "selected" : ""} onClick={() => setForm({ ...form, chronic_conditions: toggle(form.chronic_conditions, value) })}>{value}</button>)}</div><h3>Beslenme tarzı</h3><div className="v4-chip-grid">{dietStyles.map((value) => <button key={value} className={form.diet_style === value ? "selected" : ""} onClick={() => setForm({ ...form, diet_style: value })}>{value}</button>)}</div><h3>Alerjiler</h3><div className="v4-chip-grid">{allergens.map((value) => <button key={value} className={form.allergies.includes(value) ? "selected danger" : ""} onClick={() => setForm({ ...form, allergies: toggle(form.allergies, value) })}>{value}</button>)}</div><h3>Katkı maddesi reaksiyonları</h3><div className="v4-chip-grid">{reactions.map((value) => <button key={value} className={form.additive_reactions.includes(value) ? "selected" : ""} onClick={() => setForm({ ...form, additive_reactions: toggle(form.additive_reactions, value) })}>{value}</button>)}</div><label className="v4-water-goal"><Droplets />Günlük su hedefi<input type="number" min="500" max="8000" step="250" value={form.water_goal_ml} onChange={(e) => setForm({ ...form, water_goal_ml: Number(e.target.value) })} /><b>ml</b></label><div className="v4-estimate"><Sparkles /><div><b>Tahmini hedef tarihi</b><p>{weeks ? estimatedDate.toLocaleDateString("tr-TR", { day: "numeric", month: "long", year: "numeric" }) : "Hedef seçildiğinde hesaplanır"}</p><small>Bu yalnızca matematiksel bir tahmindir; gerçek ilerleme kişiden kişiye değişir.</small></div></div></div>
    </ChoiceStep>,
  ];

  return <div className="v4-onboarding-shell">
    <div className="v4-onboarding-top"><button disabled={step === 0} onClick={() => setStep((value) => Math.max(0, value - 1))}><ArrowLeft /></button><div className="v4-progress"><span style={{ width: `${((step + 1) / totalSteps) * 100}%` }} /></div><b>{step + 1} / {totalSteps}</b></div>
    <div className="v4-onboarding-body">{content[step]}</div>
    {message && <div className="notice-bar"><AlertTriangle size={17} />{message}</div>}
    <div className="v4-onboarding-actions">{step === totalSteps - 1 ? <button className="v4-primary" disabled={saving} onClick={finish}>{saving ? <LoaderCircle className="spin" /> : <Check />}Profili tamamla</button> : <button className="v4-primary" disabled={!canContinue()} onClick={() => setStep((value) => Math.min(totalSteps - 1, value + 1))}>Devam et<ChevronRight /></button>}</div>
  </div>;
}

function ChoiceStep({ title, description, children }: { title: string; description: string; children: React.ReactNode }) {
  return <section className="v4-choice-step"><span className="section-kicker">KİŞİSELLEŞTİRME</span><h1>{title}</h1><p>{description}</p><div className="v4-choice-content">{children}</div></section>;
}

function ClientDailyHub({ onboarding, clinicId }: { onboarding: Onboarding; clinicId: string }) {
  const supabase = useMemo(() => createClient(), []);
  const [date, setDate] = useState(() => dateKey(new Date()));
  const [hub, setHub] = useState<DailyHub | null>(null);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");
  const [waterAmount, setWaterAmount] = useState(250);
  const [weightValue, setWeightValue] = useState("");
  const [activityForm, setActivityForm] = useState({ type: "Yürüyüş", duration: "30", calories: "150" });
  const [panel, setPanel] = useState<"none" | "recipe" | "scan">("none");
  const [uploadingMeal, setUploadingMeal] = useState("");
  const [payments, setPayments] = useState<ClientPayment[]>([]);

  const load = useCallback(async () => {
    setLoading(true); setMessage("");
    const { data, error } = await supabase.rpc("get_client_daily_hub_v4", { p_date: date });
    if (error) {
      setMessage(error.message);
    } else {
      const nextHub = data as DailyHub;
      setHub(nextHub);
      const { data: paymentRows, error: paymentError } = await supabase
        .from("payments")
        .select("id,service_type,description,amount,paid_amount,remaining_amount,currency,status,method,paid_at,due_date,reminder_sent_at,created_at")
        .eq("client_id", nextHub.client.id)
        .order("created_at", { ascending: false });
      if (paymentError) setMessage(paymentError.message);
      else setPayments((paymentRows || []) as ClientPayment[]);
    }
    setLoading(false);
  }, [date, supabase]);
  useEffect(() => { void load(); }, [load]);

  async function addWater(amount: number) {
    const { error } = await supabase.rpc("add_water_v4", { p_amount_ml: amount, p_log_date: date });
    if (error) setMessage(error.message); else await load();
  }
  async function addWeight() {
    const value = Number(weightValue); if (!value) return;
    const { error } = await supabase.rpc("add_client_weight_v4", { p_weight_kg: value, p_weight_date: date });
    if (error) setMessage(error.message); else { setWeightValue(""); await load(); }
  }
  async function addActivity() {
    const { error } = await supabase.rpc("add_activity_v4", { p_activity_type: activityForm.type, p_duration_minutes: Number(activityForm.duration), p_calories_burned: Number(activityForm.calories), p_note: null, p_activity_date: date });
    if (error) setMessage(error.message); else await load();
  }
  async function toggleMeal(itemId: string, completed: boolean) {
    if (!hub) return;
    if (completed) {
      const { error } = await supabase.from("meal_completions").delete().eq("item_id", itemId).eq("consumed_on", date);
      if (error) setMessage(error.message); else await load();
    } else {
      const { error } = await supabase.from("meal_completions").insert({ item_id: itemId, client_id: hub.client.id, consumed_on: date, completion_percent: 100 });
      if (error) setMessage(error.message); else await load();
    }
  }
  async function uploadMealPhoto(mealName: string, file: File | null) {
    if (!file || !hub?.plan) return;
    setUploadingMeal(mealName); setMessage("");
    const safeName = file.name.toLocaleLowerCase("tr-TR").replace(/[^a-z0-9._-]+/g, "-");
    const path = `${hub.client.id}/${hub.plan.id}/${date}/${globalThis.crypto.randomUUID()}-${safeName}`;
    const { error: uploadError } = await supabase.storage.from("meal-photos").upload(path, file, { upsert: false });
    if (uploadError) { setMessage(uploadError.message); setUploadingMeal(""); return; }
    const { error } = await supabase.from("meal_photos").insert({ clinic_id: clinicId, client_id: hub.client.id, meal_plan_id: hub.plan.id, meal_name: mealName, consumed_on: date, photo_path: path });
    if (error) setMessage(error.message); else setMessage(`${mealName} fotoğrafı diyetisyeninize gönderildi.`);
    setUploadingMeal("");
  }

  if (loading && !hub) return <div className="v4-center"><LoaderCircle className="spin" />Günlük plan hazırlanıyor…</div>;
  if (!hub) return <div className="notice-bar"><AlertTriangle size={17} />{message || "Günlük takip yüklenemedi."}</div>;

  const target = hub.plan?.target_calories || 0;
  const consumed = Number(hub.consumed.calories || 0);
  const remaining = Math.max(0, target - consumed + Number(hub.burned_calories || 0));
  const percent = target ? Math.min(100, (consumed / target) * 100) : 0;
  const groups = Array.from(new Set(hub.meals.map((item) => item.meal_name)));
  const dates = Array.from({ length: 7 }, (_, index) => { const d = new Date(); d.setDate(d.getDate() - 2 + index); return d; });
  const latestWeight = hub.client.current_weight_kg;
  const paidTotal = payments.reduce((sum, payment) => sum + Number(payment.paid_amount || 0), 0);
  const outstandingTotal = payments.filter((payment) => payment.status === "pending" || payment.status === "partial").reduce((sum, payment) => sum + Number(payment.remaining_amount ?? Math.max(0, Number(payment.amount)-Number(payment.paid_amount||0))), 0);
  const latestPayment = payments[0] || null;
  const nextDuePayment = payments.filter((payment) => (payment.status === "pending" || payment.status === "partial") && payment.due_date).sort((a,b) => String(a.due_date).localeCompare(String(b.due_date)))[0] || null;
  const dueDays = nextDuePayment?.due_date ? Math.ceil((new Date(`${nextDuePayment.due_date}T12:00:00`).getTime() - new Date(new Date().toDateString()).getTime()) / 86400000) : null;

  return <div className="v4-daily-shell">
    <div className="v4-daily-hero v5-client-hero"><div><span className="section-kicker">NUTRICLINIC GÜNLÜK BAKIM</span><h1>Bugünkü klinik planın</h1><p>{hub.plan ? `${hub.plan.title} • ${goalLabel(onboarding.primary_goal)}` : "Diyetisyeniniz planınızı yayınladığında beslenme, su, aktivite ve ilerleme takibiniz burada birleşir."}</p><div className="v5-care-chips"><span><HeartPulse size={15}/>Diyetisyen kontrollü</span><span><ShieldCheck size={15}/>Alerji profiline bağlı</span><span><Target size={15}/>Hedefe özel</span></div></div><div className="v4-hero-avatar"><Apple /></div></div>
    {message && <div className="notice-bar"><AlertTriangle size={17} />{message}<button onClick={() => setMessage("")}><X size={15} /></button></div>}
    <div className="v4-week-strip">{dates.map((item) => <button key={dateKey(item)} className={date === dateKey(item) ? "selected" : ""} onClick={() => setDate(dateKey(item))}><span>{item.toLocaleDateString("tr-TR", { weekday: "short" })}</span><b>{item.getDate()}</b></button>)}</div>

    <section className={`v4-payment-overview ${outstandingTotal > 0 ? "attention" : paidTotal > 0 ? "paid" : "empty"}`}>
      <div className="v4-payment-icon">{outstandingTotal > 0 ? <Clock3 /> : paidTotal > 0 ? <CheckCircle2 /> : <WalletCards />}</div>
      <div className="v4-payment-copy">
        <span className="section-kicker">ÖDEME DURUMU</span>
        <h2>{latestPayment ? paymentStatusText(latestPayment.status) : "Henüz ödeme kaydı yok"}</h2>
        <p>{nextDuePayment ? `${nextDuePayment.service_type} • Kalan ${money(Number(nextDuePayment.remaining_amount ?? Math.max(0,Number(nextDuePayment.amount)-Number(nextDuePayment.paid_amount||0))))} • ${dueDays == null ? "Tarih belirlenmedi" : dueDays < 0 ? `${Math.abs(dueDays)} gün gecikti` : dueDays === 0 ? "Son ödeme bugün" : `${dueDays} gün kaldı`}` : latestPayment ? `${latestPayment.service_type} • ${paymentMethodText(latestPayment.method)} • ${new Date(latestPayment.paid_at || latestPayment.created_at).toLocaleDateString("tr-TR")}` : "Klinik tarafından ödeme kaydı oluşturulduğunda burada görünecek."}</p>
      </div>
      <div className="v4-payment-metrics">
        <span><small>Alınan</small><b>{money(paidTotal)}</b></span>
        <span><small>Bekleyen</small><b>{money(outstandingTotal)}</b></span>
        {nextDuePayment?.due_date && <span className={dueDays != null && dueDays < 0 ? "overdue" : ""}><small>Son ödeme</small><b>{new Date(nextDuePayment.due_date).toLocaleDateString("tr-TR")}</b></span>}
      </div>
      <button type="button" onClick={() => window.dispatchEvent(new CustomEvent("nutriclinic:navigate", { detail: "settings" }))}><CreditCard />Ödeme geçmişi</button>
    </section>

    <section className="v4-budget-section"><div className="v4-section-head"><div><span className="section-kicker">GÜNLÜK BÜTÇE</span><h2>Kalori ve makro takibi</h2></div><button onClick={load}><RefreshCw size={17} /></button></div><div className="v4-budget-grid"><div className="v4-calorie-ring" style={{ "--progress": `${percent * 3.6}deg` } as React.CSSProperties}><div><small>Kalan</small><strong>{Math.round(remaining)}</strong><b>kcal</b></div></div><div className="v4-macro-list"><Macro label="Karbonhidrat" icon="🍞" value={hub.consumed.carbs_g} target={hub.plan?.target_carbs_g || 0} /><Macro label="Protein" icon="🍗" value={hub.consumed.protein_g} target={hub.plan?.target_protein_g || 0} /><Macro label="Yağ" icon="🧀" value={hub.consumed.fat_g} target={hub.plan?.target_fat_g || 0} /></div></div></section>

    <section className="v4-discover"><div className="v4-section-head"><div><span className="section-kicker">KEŞFET</span><h2>AI destekli araçlar</h2></div></div><div className="v4-discover-grid"><button onClick={() => setPanel("scan")}><ScanLine /><span><b>Yiyecek tarayıcı</b><small>Etiketi fotoğraflayın; alerjen ve katkıları kontrol edin.</small></span></button><button onClick={() => setPanel("recipe")}><WandSparkles /><span><b>AI tarifi</b><small>Evdeki malzemelerle planınıza uygun tarif üretin.</small></span></button><button onClick={() => document.getElementById("water-card")?.scrollIntoView({ behavior: "smooth" })}><BrainCircuit /><span><b>Günlük içgörü</b><small>Su, öğün, aktivite ve hedef özetinizi görün.</small></span></button></div></section>

    {panel === "recipe" && <AIRecipePanel hub={hub} onClose={() => setPanel("none")} />}
    {panel === "scan" && <FoodScannerPanel hub={hub} onClose={() => setPanel("none")} />}

    <section className="v4-meals"><div className="v4-section-head"><div><span className="section-kicker">TÜKETİLEN</span><h2>Öğünler</h2></div><strong><Flame size={17} />{Math.round(consumed)} kcal</strong></div>{!hub.plan ? <div className="v4-empty"><UtensilsCrossed /><b>Aktif menü bulunmuyor</b><p>Diyetisyeniniz bir plan yayınladığında öğünler burada listelenecek.</p></div> : groups.map((group) => { const items = hub.meals.filter((item) => item.meal_name === group); const completedCount = items.filter((item) => item.completed).length; return <article className="v4-meal-card" key={group}><header><div><MealIcon meal={group} /><span><b>{group}</b><small>{completedCount}/{items.length} tamamlandı • {Math.round(items.reduce((sum, item) => sum + Number(item.calories), 0))} kcal</small></span></div><label className="v4-meal-photo"><input type="file" accept="image/*" onChange={(e) => { void uploadMealPhoto(group, e.target.files?.[0] || null); e.currentTarget.value = ""; }} />{uploadingMeal === group ? <LoaderCircle className="spin" size={19} /> : <ImagePlus size={19} />}<span>Fotoğraf</span></label></header><div>{items.map((item) => <button key={item.id} className={item.completed ? "completed" : ""} onClick={() => toggleMeal(item.id, item.completed)}><span className="v4-check">{item.completed && <Check size={14} />}</span><span><b>{item.food_name}</b><small>{item.portion_text || "Porsiyon belirtilmedi"} • {Math.round(item.calories)} kcal</small></span></button>)}</div></article>; })}</section>

    <div className="v4-tracker-grid">
      <section id="water-card" className="v4-tracker-card water"><div className="v4-tracker-head"><Droplets /><div><span>Su</span><strong>{hub.water_ml} ml</strong><small>Hedef: {hub.client.water_goal_ml} ml</small></div></div><div className="v4-water-progress"><span style={{ width: `${Math.min(100, (hub.water_ml / Math.max(1, hub.client.water_goal_ml)) * 100)}%` }} /></div><div className="v4-inline-add"><button onClick={() => setWaterAmount(Math.max(50, waterAmount - 50))}><Minus /></button><b>{waterAmount} ml</b><button onClick={() => setWaterAmount(Math.min(2000, waterAmount + 50))}><Plus /></button><button className="v4-add-action" onClick={() => addWater(waterAmount)}>Ekle</button></div></section>
      <section className="v4-tracker-card"><div className="v4-tracker-head"><Scale /><div><span>Kilo</span><strong>{latestWeight ? `${latestWeight} kg` : "—"}</strong><small>Hedef: {hub.client.target_weight_kg || "—"} kg</small></div></div><div className="v4-weight-line">{hub.weight_history.map((entry, index) => <span key={entry.date} style={{ height: `${20 + ((entry.weight_kg - Math.min(...hub.weight_history.map((x) => x.weight_kg), entry.weight_kg)) * 5)}px` }} title={`${entry.date}: ${entry.weight_kg} kg`} />)}</div><div className="v4-inline-input"><input type="number" step="0.1" placeholder="Yeni kilo" value={weightValue} onChange={(e) => setWeightValue(e.target.value)} /><button onClick={addWeight}><Plus />Kaydet</button></div></section>
      <section className="v4-tracker-card activity"><div className="v4-tracker-head"><Activity /><div><span>Aktiviteler</span><strong>{Math.round(hub.burned_calories)} kcal</strong><small>{hub.activities?.length || 0} manuel kayıt</small></div></div>{hub.activities?.length>0&&<div className="v5-activity-history">{hub.activities.map(activity=><article key={activity.id}><span><Activity size={15}/></span><div><b>{activity.activity_type}</b><small>{activity.duration_minutes} dakika • {Math.round(Number(activity.calories_burned))} kcal{activity.note?` • ${activity.note}`:""}</small></div></article>)}</div>}<div className="v4-activity-form"><input value={activityForm.type} onChange={(e) => setActivityForm({ ...activityForm, type: e.target.value })} placeholder="Aktivite" /><input type="number" value={activityForm.duration} onChange={(e) => setActivityForm({ ...activityForm, duration: e.target.value })} placeholder="Dakika" /><input type="number" value={activityForm.calories} onChange={(e) => setActivityForm({ ...activityForm, calories: e.target.value })} placeholder="kcal" /><button onClick={addActivity}><Plus />Egzersiz ekle</button></div></section>
    </div>
  </div>;
}

function Macro({ label, icon, value, target }: { label: string; icon: string; value: number; target: number }) {
  const percent = target ? Math.min(100, (Number(value) / Number(target)) * 100) : 0;
  return <div className="v4-macro"><span>{icon}</span><div><b>{Math.round(Number(value))} <small>/ {Math.round(Number(target))}g</small></b><p>{label}</p><i><em style={{ width: `${percent}%` }} /></i></div></div>;
}
function MealIcon({ meal }: { meal: string }) {
  if (meal.includes("Kahvaltı")) return <span>🌅</span>;
  if (meal.includes("Öğle")) return <span>☀️</span>;
  if (meal.includes("Akşam")) return <span>🌙</span>;
  return <span>🍎</span>;
}

function AIRecipePanel({ hub, onClose }: { hub: DailyHub; onClose: () => void }) {
  const [form, setForm] = useState({ ingredients: "", meal_type: "Ara Öğün", max_minutes: "30", max_calories: "300" });
  const [result, setResult] = useState<RecipeResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  async function generate() {
    if (!form.ingredients.trim()) return setMessage("En az bir malzeme yazın.");
    setLoading(true); setMessage(""); setResult(null);
    const response = await fetch("/api/ai/recipe", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...form, max_minutes: Number(form.max_minutes), max_calories: Number(form.max_calories), allergies: hub.client.allergies, disliked_foods: hub.client.disliked_foods, diet_style: hub.client.diet_style, macro_targets: hub.plan }) });
    const json = await response.json();
    if (!response.ok) setMessage(json.error || "Tarif oluşturulamadı."); else setResult(json.recipe as RecipeResult);
    setLoading(false);
  }
  return <div className="v4-tool-overlay"><section className="v4-tool-panel"><header><button onClick={onClose}><ChevronLeft /></button><div><span className="section-kicker">NUTRICLINIC AI</span><h2>AI tarifi</h2></div><Sparkles /></header>{!result ? <><div className="v4-tool-illustration"><WandSparkles /><h3>Tarifini kişiselleştir</h3><p>Buzdolabında ne var? Malzemeleri girin; alerji ve plan hedefleri otomatik dikkate alınsın.</p></div><textarea rows={5} value={form.ingredients} onChange={(e) => setForm({ ...form, ingredients: e.target.value })} placeholder="Ör: tavuk, mantar, yoğurt, pirinç…" /><div className="v4-tool-settings"><select value={form.meal_type} onChange={(e) => setForm({ ...form, meal_type: e.target.value })}>{["Kahvaltı", "Ara Öğün", "Öğle Yemeği", "Akşam Yemeği"].map((value) => <option key={value}>{value}</option>)}</select><select value={form.max_minutes} onChange={(e) => setForm({ ...form, max_minutes: e.target.value })}>{[15, 30, 45, 60].map((value) => <option key={value} value={value}>{value} dk</option>)}</select><select value={form.max_calories} onChange={(e) => setForm({ ...form, max_calories: e.target.value })}>{[200, 300, 450, 600, 800].map((value) => <option key={value} value={value}>≤ {value} kcal</option>)}</select></div>{message && <div className="notice-bar"><AlertTriangle size={16} />{message}</div>}<button className="v4-primary" onClick={generate} disabled={loading}>{loading ? <LoaderCircle className="spin" /> : <Sparkles />}AI tarif oluştur</button></> : <RecipeCard result={result} onAgain={() => setResult(null)} />}</section></div>;
}

function RecipeCard({ result, onAgain }: { result: RecipeResult; onAgain: () => void }) {
  return <div className="v4-recipe-result"><div className="v4-recipe-cover"><Salad /><span>NutriClinic AI Tarifi</span></div><h2>{result.title}</h2><div className="v4-recipe-stats"><span><Flame />{result.calories} kcal</span><span><Clock3 />{result.prep_minutes} dk</span><span><UtensilsCrossed />{result.difficulty}</span></div><p>{result.summary}</p><div className="v4-tag-row">{result.tags?.map((tag) => <span key={tag}>{tag}</span>)}</div>{result.allergy_notes?.length > 0 && <div className="v4-allergy-note"><AlertTriangle /><div><b>Alerji kontrolü</b>{result.allergy_notes.map((note) => <p key={note}>{note}</p>)}</div></div>}<div className="v4-recipe-macros"><span><b>{result.protein_g}g</b> Protein</span><span><b>{result.carbs_g}g</b> Karbonhidrat</span><span><b>{result.fat_g}g</b> Yağ</span></div><div className="v4-recipe-columns"><section><h3>Malzemeler</h3><ul>{result.ingredients.map((item) => <li key={item}>{item}</li>)}</ul></section><section><h3>Hazırlanışı</h3><ol>{result.steps.map((item) => <li key={item}>{item}</li>)}</ol></section></div><div className="v4-suitability"><Sparkles /><div><p>{result.suitability_note}</p>{result.clinical_caution&&<small>{result.clinical_caution}</small>}</div></div>{result.substitutions?.length?<section className="v5-ai-detail"><h3>Güvenli alternatifler</h3>{result.substitutions.map(item=><article key={`${item.instead_of}-${item.use}`}><b>{item.instead_of} yerine {item.use}</b><p>{item.reason}</p></article>)}</section>:null}{result.shopping_list?.length?<section className="v5-ai-detail"><h3>Alışveriş listesi</h3><div className="v4-tag-row">{result.shopping_list.map(item=><span key={item}>{item}</span>)}</div></section>:null}<button className="v4-primary" onClick={onAgain}><RefreshCw />Başka tarif oluştur</button></div>;
}

function FoodScannerPanel({ hub, onClose }: { hub: DailyHub; onClose: () => void }) {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState("");
  const [result, setResult] = useState<ScanResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  function choose(next: File | null) {
    setFile(next); setResult(null); setMessage("");
    if (!next) return setPreview("");
    const reader = new FileReader(); reader.onload = () => setPreview(String(reader.result || "")); reader.readAsDataURL(next);
  }
  async function scan() {
    if (!file || !preview) return setMessage("Ürün etiketi veya içerik listesinin fotoğrafını seçin.");
    setLoading(true); setMessage("");
    const response = await fetch("/api/ai/food-scan", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ image_data_url: preview, filename: file.name, allergies: hub.client.allergies, disliked_foods: hub.client.disliked_foods, diet_style: hub.client.diet_style }) });
    const json = await response.json();
    if (!response.ok) setMessage(json.error || "Analiz yapılamadı."); else setResult(json.scan as ScanResult);
    setLoading(false);
  }
  return <div className="v4-tool-overlay"><section className="v4-tool-panel"><header><button onClick={onClose}><ChevronLeft /></button><div><span className="section-kicker">GIDA GÜVENLİĞİ</span><h2>Yiyecek tarayıcı</h2></div><ScanLine /></header><div className="v4-scan-upload">{preview ? <img src={preview} alt="Yüklenen ürün etiketi" /> : <Camera />}<label><ImagePlus />Fotoğraf seç<input type="file" accept="image/*" onChange={(e) => choose(e.target.files?.[0] || null)} /></label></div><p className="v4-tool-help">İçindekiler ve alerjen uyarısı net görünecek şekilde fotoğraf çekin. Sonuç kesin tıbbi güvence değildir; ambalaj etiketini ve diyetisyeninizi esas alın.</p>{message && <div className="notice-bar"><AlertTriangle size={16} />{message}</div>}{result && <div className={`v4-scan-result ${result.suitability}`}><div className="v4-scan-summary"><ShieldIcon status={result.suitability} /><div><b>{result.product_name || "Ürün analizi"}</b><p>{result.summary}</p></div></div><h3>Alerjen uyarıları</h3>{result.allergen_alerts.length ? result.allergen_alerts.map((item) => <article key={`${item.allergen}-${item.reason}`}><span className={`severity ${item.severity}`}>{item.severity}</span><div><b>{item.allergen}</b><p>{item.reason}</p></div></article>) : <p>Profilinizle eşleşen belirgin alerjen saptanmadı.</p>}<h3>Katkı maddeleri</h3>{result.additive_findings.length ? result.additive_findings.map((item) => <article key={item.code_or_name}><span>🧪</span><div><b>{item.code_or_name}</b><p>{item.note}</p></div></article>) : <p>Okunabilen etikette belirgin katkı maddesi saptanmadı.</p>}{result.recommended_actions?.length?<><h3>Önerilen adımlar</h3>{result.recommended_actions.map(action=><article key={action}><span>✓</span><div><p>{action}</p></div></article>)}</>:null}<small>{result.uncertainty_note}</small></div>}<button className="v4-primary" onClick={scan} disabled={loading}>{loading ? <LoaderCircle className="spin" /> : <ScanLine />}{result ? "Yeniden tara" : "Etiketi analiz et"}</button></section></div>;
}
function ShieldIcon({ status }: { status: ScanResult["suitability"] }) {
  if (status === "uygun") return <Check />;
  if (status === "uygun_degil") return <X />;
  return <AlertTriangle />;
}
