"use client";
/* eslint-disable @next/next/no-img-element */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Activity, AlertTriangle, ArrowDownRight, ArrowUpRight, BadgeCheck, Banknote, BrainCircuit, CalendarCheck2,
  CalendarClock, CalendarDays, Camera, Check, CheckCircle2, ChevronLeft, ChevronRight, CircleDollarSign,
  ClipboardList, Clock3, CreditCard, Download, Eye, FileText, Gift, ImagePlus, Mail, MessageCircle,
  Pencil, Phone, Plus, RefreshCw, Save, Search, Send, ShieldCheck, Sparkles, Trash2, TriangleAlert,
  Upload, UserCheck, UserRound, UsersRound, UtensilsCrossed, WalletCards, Weight, X, XCircle
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { Role } from "@/lib/types";

type ClientRow = {
  id: string;
  user_id: string | null;
  member_no: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  birth_date: string | null;
  gender: string | null;
  assigned_dietitian_id: string | null;
  assigned_dietitian_name: string | null;
  height_cm: number | null;
  target_text: string | null;
  allergies: string[];
  disliked_foods: string[];
  medical_notes: string | null;
  medications: string | null;
  latest_weight_kg: number | null;
  latest_body_fat_percent: number | null;
  latest_muscle_mass_kg: number | null;
  latest_measurement_at: string | null;
  loyalty_earned: number;
  loyalty_used: number;
  loyalty_balance: number;
  payment_total: number;
  payment_paid: number;
  payment_due: number;
  last_payment_status: string | null;
  last_payment_method: string | null;
  last_payment_service: string | null;
  last_payment_at: string | null;
  created_at: string;
  onboarding_completed: boolean;
  primary_goal: string | null;
  motivation_reasons: string[];
  target_weight_kg: number | null;
  activity_level: string | null;
  calorie_knowledge: string | null;
  diet_style: string | null;
  chronic_conditions: string[];
  additive_reactions: string[];
  water_goal_ml: number | null;
};

type DietitianRow = {
  id: string;
  user_id: string;
  title: string | null;
  appointment_duration_minutes: number;
  buffer_minutes: number;
  is_bookable: boolean;
  full_name: string;
};

type AppointmentRow = {
  id: string;
  client_id: string;
  dietitian_id: string;
  starts_at: string;
  ends_at: string;
  appointment_type: string;
  mode: string;
  status: string;
  public_note: string | null;
  cancellation_reason?: string | null;
  client_name?: string;
  client_email?: string | null;
  client_phone?: string | null;
  dietitian_name?: string;
};

type SlotRow = {
  starts_at: string;
  ends_at: string;
  is_available: boolean;
  appointment_id: string | null;
  appointment_status: string | null;
  appointment_type: string | null;
  client_id: string | null;
  client_name: string | null;
  client_email: string | null;
  client_phone: string | null;
};

type AvailabilityRuleRow = { id:string; dietitian_id:string; weekday:number; start_time:string; end_time:string; is_active:boolean };
type AvailabilityExceptionRow = { id:string; dietitian_id:string; starts_at:string; ends_at:string; is_available:boolean; reason:string|null };

type PaymentRow = {
  id:string;
  clinic_id:string;
  client_id:string;
  appointment_id:string|null;
  service_type:string;
  description:string|null;
  amount:number;
  currency:string;
  status:string;
  method:string|null;
  paid_at:string|null;
  created_at:string;
  updated_at:string;
  client_name?:string;
  member_no?:string;
};

type MealPlanRow = {
  id:string; client_id:string; dietitian_id?:string; title:string; starts_on:string; ends_on:string;
  target_calories:number|null; target_protein_g:number|null; target_carbs_g:number|null; target_fat_g:number|null;
  status:string; dietitian_note:string|null; client_name?:string;
};
type MealItemRow = { id:string; meal_plan_id:string; meal_name:string; food_name:string; portion_text:string|null; calories:number; protein_g:number; carbs_g:number; fat_g:number; sort_order:number; completed?:boolean };
type FoodCatalogRow = { id:string; clinic_id:string|null; name:string; name_key:string; calories_per_100g:number; protein_per_100g:number; carbs_per_100g:number; fat_per_100g:number; default_portion_g:number; source_label:string|null; is_active:boolean };
type MealDraftItem = { key:string; meal_name:string; food_name:string; catalog_id:string|null; quantity_g:string; portion_text:string; calories:string; protein:string; carbs:string; fat:string };
type MealPhotoRow = { id:string; clinic_id:string; client_id:string; meal_plan_id:string; meal_name:string; consumed_on:string; photo_path:string; caption:string|null; created_at:string; signed_url?:string };

type CommunityComment = { id:string; author_user_id:string; author_name:string; content:string; created_at:string };
type CommunityPost = { id:string; dietitian_id:string; author_user_id:string; author_name:string; author_role:string; content:string|null; media_path:string|null; created_at:string; comments:CommunityComment[]; signed_url?:string };

type LoyaltyHistoryRow = { id:string; points:number; reason:string; actor_name:string|null; actor_role:Role|null; balance_after:number|null; created_at:string };
type AIRecipeHistoryRow = { id:string; meal_type:string|null; ingredients:string; recipe:Record<string,unknown>; created_at:string };
type FoodScanHistoryRow = { id:string; filename:string|null; result:Record<string,unknown>; created_at:string };

type DashboardSummary = {
  role:Role;
  today:string;
  today_appointments?:number;
  pending_appointments?:number;
  active_clients?:number;
  active_plans?:number;
  daily_revenue?:number;
  pending_payments?:number;
  upcoming_appointments?:number;
  measurements?:number;
  loyalty_balance?:number;
  revenue_breakdown?:Array<{service_type:string;count:number;amount:number}>;
  agenda?:Array<Record<string,unknown>>;
};

const mealTypes=["Kahvaltı","Ara Öğün","Öğle Yemeği","İkindi Ara Öğünü","Akşam Yemeği","Gece Ara Öğünü","Diğer"];
const weekdayOptions=[{value:"1",label:"Pazartesi"},{value:"2",label:"Salı"},{value:"3",label:"Çarşamba"},{value:"4",label:"Perşembe"},{value:"5",label:"Cuma"},{value:"6",label:"Cumartesi"},{value:"0",label:"Pazar"}];

function PageHeader({title,description,action}:{title:string;description:string;action?:React.ReactNode}){
  return <div className="page-header v3-page-header"><div><span className="section-kicker">NUTRICLINIC AI</span><h1>{title}</h1><p>{description}</p></div>{action&&<div className="page-header-actions">{action}</div>}</div>;
}
function Loading(){return <div className="empty-state"><RefreshCw className="spin" size={24}/><p>Yükleniyor…</p></div>}
function Empty({text="Henüz kayıt bulunmuyor."}:{text?:string}){return <div className="empty-state"><ClipboardList size={28}/><p>{text}</p></div>}
function initials(name:string){return name.split(" ").filter(Boolean).slice(0,2).map(x=>x[0]).join("").toUpperCase()}
function statusText(status:string){return({pending:"Onay bekliyor",confirmed:"Onaylandı",completed:"Tamamlandı",cancelled:"İptal edildi",no_show:"Gelmedi"} as Record<string,string>)[status]||status}
function paymentStatusText(status:string|null){return({pending:"Bekliyor",partial:"Kısmi",paid:"Ödendi",refunded:"İade",cancelled:"İptal"} as Record<string,string>)[status||""]||"Kayıt yok"}
function paymentMethodText(method:string|null){return({cash:"Nakit",card:"Kart",iban:"IBAN",other:"Diğer"} as Record<string,string>)[method||""]||"—"}
function roleText(role:string){return({owner:"Klinik Sahibi",dietitian:"Diyetisyen",secretary:"Sekreter",client:"Danışan"} as Record<string,string>)[role]||role}
function goalText(value:string|null){return({lose_weight:"Kilo vermek",maintain_weight:"Kiloyu korumak",gain_muscle:"Kas yapmak",feel_fitter:"Daha formda olmak",improve_health:"Genel sağlığı iyileştirmek"} as Record<string,string>)[value||""]||value||"—"}
function activityText(value:string|null){return({sedentary:"Aktif değil",light:"Hafif aktif",moderate:"Orta aktif",active:"Aktif"} as Record<string,string>)[value||""]||value||"—"}
function money(value:number|string|null|undefined){return new Intl.NumberFormat("tr-TR",{style:"currency",currency:"TRY",maximumFractionDigits:2}).format(Number(value)||0)}
function localDateKey(date:Date){const y=date.getFullYear();const m=String(date.getMonth()+1).padStart(2,"0");const d=String(date.getDate()).padStart(2,"0");return `${y}-${m}-${d}`}
function shortDate(value:string){return new Date(value).toLocaleDateString("tr-TR",{day:"2-digit",month:"short",year:"numeric"})}
function dateTime(value:string){return new Date(value).toLocaleString("tr-TR",{day:"2-digit",month:"short",hour:"2-digit",minute:"2-digit"})}
function roundNutrition(value:number){return Math.round((Number(value)||0)*10)/10}
function num(value:string){const n=Number(value);return Number.isFinite(n)?n:null}
function foodNameKey(value:string){return value.trim().toLocaleLowerCase("tr-TR").replace(/ı/g,"i").replace(/ğ/g,"g").replace(/ü/g,"u").replace(/ş/g,"s").replace(/ö/g,"o").replace(/ç/g,"c").normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/[^a-z0-9]+/g," ").trim()}
function extractQuantity(portion:string|null){if(!portion)return "";const match=portion.match(/^([0-9]+(?:[.,][0-9]+)?)\s*g\/ml$/i);return match?match[1].replace(",","."):""}
function escapeHtml(value:string){return value.replace(/[&<>'"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]||c))}
function downloadBlob(content:string,name:string,type:string){const blob=new Blob([content],{type});const url=URL.createObjectURL(blob);const a=document.createElement("a");a.href=url;a.download=name;a.click();URL.revokeObjectURL(url)}
function createMealDraft(key:string):MealDraftItem{return{key,meal_name:"Kahvaltı",food_name:"",catalog_id:null,quantity_g:"",portion_text:"",calories:"",protein:"",carbs:"",fat:""}}
function foodWarnings(foodName:string,client:Pick<ClientRow,"allergies"|"disliked_foods">){
  const key=foodNameKey(foodName); if(!key)return{allergies:[] as string[],disliked:[] as string[]};
  const relation:Record<string,string[]>={laktoz:["sut","yogurt","peynir","ayran","krema","dondurma"],gluten:["bugday","ekmek","bulgur","makarna","un","yulaf"],findik:["findik"],fistik:["fistik"],yumurta:["yumurta"],balik:["balik","somon","ton baligi"],kabuklu:["karides","midye","kalamar"]};
  const matches=(values:string[]|undefined)=>Array.from(new Set((values||[]).filter(v=>{const vKey=foodNameKey(v);return key.includes(vKey)||vKey.includes(key)||(relation[vKey]||[]).some(x=>key.includes(x))}))); 
  return{allergies:matches(client.allergies),disliked:matches(client.disliked_foods)};
}

export function OverviewV3({role,clinicId,fullName,onClaimOwner}:{role:Role;clinicId:string;fullName:string;onClaimOwner:()=>void}){
  const supabase=useMemo(()=>createClient(),[]);
  const [summary,setSummary]=useState<DashboardSummary|null>(null);
  const [loading,setLoading]=useState(true);
  const [message,setMessage]=useState("");
  const [canClaim,setCanClaim]=useState(false);
  const load=useCallback(async()=>{
    setLoading(true);
    const [{data,error},{data:claim}]=await Promise.all([
      supabase.rpc("get_dashboard_summary_v3"),
      role==="client"?supabase.rpc("can_claim_first_owner"):Promise.resolve({data:false,error:null}),
    ]);
    if(error)setMessage(error.message);else setSummary(data as DashboardSummary);
    setCanClaim(Boolean(claim));
    setLoading(false);
  },[role,supabase]);
  useEffect(()=>{void load()},[load,clinicId]);

  const cards=role==="owner"?[
    {label:"Bugünkü ciro",value:money(summary?.daily_revenue),hint:"Yalnızca ödenmiş işlemler",Icon:CircleDollarSign,tone:"revenue"},
    {label:"Bugünkü randevu",value:String(summary?.today_appointments||0),hint:`${summary?.pending_appointments||0} onay bekliyor`,Icon:CalendarCheck2,tone:"green"},
    {label:"Aktif danışan",value:String(summary?.active_clients||0),hint:"Klinikte aktif kayıt",Icon:UsersRound,tone:"blue"},
    {label:"Bekleyen ödeme",value:String(summary?.pending_payments||0),hint:"Bekliyor veya kısmi",Icon:WalletCards,tone:"amber"},
  ]:role==="dietitian"?[
    {label:"Bugünkü randevu",value:String(summary?.today_appointments||0),hint:`${summary?.pending_appointments||0} onay bekliyor`,Icon:CalendarCheck2,tone:"green"},
    {label:"Danışanlarım",value:String(summary?.active_clients||0),hint:"Size atanmış aktif danışan",Icon:UserCheck,tone:"blue"},
    {label:"Aktif menüler",value:String(summary?.active_plans||0),hint:"Devam eden plan",Icon:UtensilsCrossed,tone:"amber"},
    {label:"Günlük ajanda",value:String((summary?.agenda||[]).length),hint:"Bugünkü planlı görüşme",Icon:Clock3,tone:"violet"},
  ]:role==="secretary"?[
    {label:"Bugünkü randevu",value:String(summary?.today_appointments||0),hint:`${summary?.pending_appointments||0} onay bekliyor`,Icon:CalendarCheck2,tone:"green"},
    {label:"Aktif danışan",value:String(summary?.active_clients||0),hint:"İletişim ve randevu kaydı",Icon:UsersRound,tone:"blue"},
    {label:"Bekleyen ödeme",value:String(summary?.pending_payments||0),hint:"Düzenleme gereken ödeme",Icon:CreditCard,tone:"amber"},
    {label:"Bugünkü ajanda",value:String((summary?.agenda||[]).length),hint:"Tüm diyetisyenler",Icon:Clock3,tone:"violet"},
  ]:[
    {label:"Yaklaşan randevu",value:String(summary?.upcoming_appointments||0),hint:"Onaylı veya bekleyen",Icon:CalendarCheck2,tone:"green"},
    {label:"Aktif menü",value:String(summary?.active_plans||0),hint:"Diyetisyen planı",Icon:UtensilsCrossed,tone:"amber"},
    {label:"Ölçüm kaydı",value:String(summary?.measurements||0),hint:"Gelişim geçmişi",Icon:Weight,tone:"blue"},
    {label:"Sadakat puanı",value:(summary?.loyalty_balance||0).toLocaleString("tr-TR"),hint:"Kullanılabilir bakiye",Icon:Gift,tone:"violet"},
  ];

  return <>
    <PageHeader title={`Hoş geldin, ${fullName}`} description={role==="owner"?"Kliniğin bugünkü operasyonunu, randevularını ve gelir dağılımını tek ekranda izleyin.":role==="dietitian"?"Danışanlarınızın güncel akışını ve bugünkü randevularınızı yönetin.":role==="secretary"?"Randevu, danışan ve ödeme operasyonlarını hızlıca takip edin.":"Randevularınızı, menünüzü, ölçümlerinizi ve ödüllerinizi takip edin."} action={<button className="secondary-button compact" onClick={load}><RefreshCw size={15}/>Yenile</button>}/>
    {message&&<div className="notice-bar"><AlertTriangle size={17}/>{message}</div>}
    {role==="client"&&canClaim&&<div className="owner-claim"><ShieldCheck size={23}/><div><b>İlk kurulumu siz yapıyorsanız</b><p>Sistemde henüz klinik sahibi yoksa bu hesap bir kez Klinik Sahibi yapılabilir.</p></div><button className="secondary-button" onClick={onClaimOwner}>İlk sahibi etkinleştir</button></div>}
    <div className="v3-metric-grid">{cards.map(({label,value,hint,Icon,tone})=><article className={`v3-metric-card ${tone}`} key={label}><div className="metric-icon"><Icon size={21}/></div><div><span>{label}</span><strong>{loading?"…":value}</strong><small>{hint}</small></div></article>)}</div>

    <div className={`overview-layout ${role==="owner"?"owner-layout":""}`}>
      <section className="surface-card agenda-card">
        <div className="surface-head"><div><span className="section-kicker">BUGÜN</span><h3>Randevu akışı</h3><p>Onay, iletişim ve görüşme türü bilgileriyle günlük ajanda.</p></div><CalendarDays size={21}/></div>
        {loading?<Loading/>:(summary?.agenda||[]).length===0?<Empty text="Bugün için randevu bulunmuyor."/>:<div className="agenda-list">{(summary?.agenda||[]).map((raw,index)=>{const row=raw as Record<string,string>;return <article key={row.id||index}><time>{new Date(row.starts_at).toLocaleTimeString("tr-TR",{hour:"2-digit",minute:"2-digit"})}</time><div className="agenda-avatar">{initials(row.client_name||row.dietitian_name||"NC")}</div><div className="grow"><b>{row.client_name||row.dietitian_name||"Randevu"}</b><p>{row.appointment_type||"Görüşme"} • {row.mode==="online"?"Online":"Klinik"}{row.dietitian_name?` • ${row.dietitian_name}`:""}</p>{(row.phone||row.email)&&<small>{row.phone||row.email}</small>}</div><span className={`status ${row.status}`}>{statusText(row.status)}</span></article>})}</div>}
      </section>

      {role==="owner"&&<section className="surface-card revenue-card">
        <div className="surface-head"><div><span className="section-kicker">FİNANS</span><h3>Günlük ciro dağılımı</h3><p>Bugün ödeme alınan hizmetler ve adetleri.</p></div><Banknote size={21}/></div>
        {(summary?.revenue_breakdown||[]).length===0?<Empty text="Bugün için ödenmiş işlem bulunmuyor."/>:<div className="revenue-breakdown">{summary?.revenue_breakdown?.map(item=><article key={item.service_type}><div><b>{item.service_type}</b><small>{item.count} işlem</small></div><strong>{money(item.amount)}</strong><div className="mini-bar"><span style={{width:`${Math.min(100,(item.amount/Math.max(1,summary.daily_revenue||1))*100)}%`}}/></div></article>)}</div>}
        <div className="owner-finance-note"><ShieldCheck size={17}/><span>Bu ciro alanı yalnızca Klinik Sahibi rolünde görünür.</span></div>
      </section>}

      {role!=="owner"&&<section className="surface-card insight-card">
        <div className="surface-head"><div><span className="section-kicker">HIZLI DURUM</span><h3>{role==="client"?"Takip özeti":"Operasyon özeti"}</h3><p>Günün öne çıkan durumları.</p></div><Sparkles size={21}/></div>
        <div className="insight-list">
          <div><CheckCircle2 size={18}/><span><b>{role==="client"?"Plan ve randevular tek yerde":"Randevu onayları görünür"}</b><small>{role==="client"?"Öğün fotoğrafları ve tamamlanan besinler diyetisyene ulaşır.":"Bekleyen randevuları Randevular ekranından onaylayabilirsiniz."}</small></span></div>
          <div><BadgeCheck size={18}/><span><b>{role==="dietitian"?"Danışan detayları hazır":role==="secretary"?"Ödeme yetkisi etkin":"Ödüller aktif"}</b><small>{role==="dietitian"?"Kilo, alerji, sevmediği besinler ve geçmiş kayıtlar detay panelinde.":role==="secretary"?"Ödeme yöntemi ve statüsünü Danışanlar veya Ödemeler ekranından güncelleyebilirsiniz.":"Puanınız yeterli olan ödülleri Sadakat ekranından kullanabilirsiniz."}</small></span></div>
        </div>
      </section>}
    </div>
  </>;
}

export function AppointmentsV3({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);
  const [effectiveRole,setEffectiveRole]=useState<Role>(role);
  const [dietitians,setDietitians]=useState<DietitianRow[]>([]);
  const [clients,setClients]=useState<ClientRow[]>([]);
  const [appointments,setAppointments]=useState<AppointmentRow[]>([]);
  const [slots,setSlots]=useState<SlotRow[]>([]);
  const [loading,setLoading]=useState(true);
  const [slotLoading,setSlotLoading]=useState(false);
  const [message,setMessage]=useState("");
  const [date,setDate]=useState(()=>localDateKey(new Date()));
  const [dietitianId,setDietitianId]=useState("");
  const [selectedSlot,setSelectedSlot]=useState("");
  const [showBooking,setShowBooking]=useState(false);
  const [form,setForm]=useState({client_id:"",appointment_type:"Kontrol",mode:"in_clinic",note:""});
  const [showAvailability,setShowAvailability]=useState(false);
  const [rules,setRules]=useState<AvailabilityRuleRow[]>([]);
  const [exceptions,setExceptions]=useState<AvailabilityExceptionRow[]>([]);
  const [weeklyForm,setWeeklyForm]=useState({weekday:"1",start_time:"09:00",end_time:"17:00"});
  const [dailyForm,setDailyForm]=useState({date:"",start_time:"09:00",end_time:"12:00",is_available:"true",reason:""});
  const staff=effectiveRole!=="client";
  const clinical=effectiveRole==="owner"||effectiveRole==="dietitian";

  const load=useCallback(async()=>{
    setLoading(true);
    const {data:userData}=await supabase.auth.getUser();
    const userId=userData.user?.id||"";
    const {data:membership}=await supabase.from("clinic_memberships").select("role").eq("clinic_id",clinicId).eq("user_id",userId).eq("is_active",true).maybeSingle();
    const resolved=(membership?.role||role) as Role; setEffectiveRole(resolved);
    const [{data:d},{data:a}]=await Promise.all([
      supabase.from("dietitian_profiles").select("id,user_id,title,appointment_duration_minutes,buffer_minutes,is_bookable").eq("clinic_id",clinicId).eq("is_bookable",true),
      supabase.from("appointments").select("id,client_id,dietitian_id,starts_at,ends_at,appointment_type,mode,status,public_note,cancellation_reason").order("starts_at",{ascending:false}).limit(250),
    ]);
    let ds=(d||[]) as Omit<DietitianRow,"full_name">[];
    const ids=ds.map(x=>x.user_id);
    const {data:profiles}=ids.length?await supabase.from("profiles").select("id,full_name").in("id",ids):{data:[]};
    const pMap=new Map((profiles||[]).map((x:any)=>[x.id,x.full_name]));
    let full=ds.map(x=>({...x,full_name:pMap.get(x.user_id)||"Diyetisyen"})) as DietitianRow[];
    if(resolved==="dietitian")full=full.filter(x=>x.user_id===userId);
    setDietitians(full);
    setDietitianId(current=>full.some(x=>x.id===current)?current:(full[0]?.id||""));

    let clientRows:ClientRow[]=[];
    if(resolved!=="client"){
      const {data:c,error}=await supabase.rpc("get_client_directory_v4");
      if(error)setMessage(error.message); else clientRows=(c||[]) as ClientRow[];
    }
    setClients(clientRows);
    setForm(current=>({...current,client_id:clientRows.some(x=>x.id===current.client_id)?current.client_id:(clientRows[0]?.id||"")}));
    const cMap=new Map(clientRows.map(x=>[x.id,x])); const dMap=new Map(full.map(x=>[x.id,x.full_name]));
    setAppointments(((a||[]) as AppointmentRow[]).map(row=>{const c=cMap.get(row.client_id);return{...row,client_name:resolved==="client"?"Randevunuz":c?.full_name||"Danışan",client_email:c?.email,client_phone:c?.phone,dietitian_name:dMap.get(row.dietitian_id)||"Diyetisyen"}}));
    setLoading(false);
  },[clinicId,role,supabase]);

  const loadSlots=useCallback(async()=>{
    if(!dietitianId||!date){setSlots([]);return;}
    setSlotLoading(true); setMessage("");
    const {data,error}=await supabase.rpc("get_dietitian_day_slots_v3",{p_dietitian_id:dietitianId,p_day:date});
    if(error){setMessage(error.message);setSlots([]);}else{
      const next=(data||[]) as SlotRow[];setSlots(next);
      if(selectedSlot&&!next.some(x=>x.starts_at===selectedSlot&&x.is_available))setSelectedSlot("");
    }
    setSlotLoading(false);
  },[date,dietitianId,selectedSlot,supabase]);

  useEffect(()=>{void load()},[load]);
  useEffect(()=>{void loadSlots()},[loadSlots]);

  const loadAvailability=useCallback(async()=>{
    if(!dietitianId)return;
    const today=new Date();today.setHours(0,0,0,0);
    const [{data:r},{data:e}]=await Promise.all([
      supabase.from("availability_rules").select("id,dietitian_id,weekday,start_time,end_time,is_active").eq("dietitian_id",dietitianId).order("weekday").order("start_time"),
      supabase.from("availability_exceptions").select("id,dietitian_id,starts_at,ends_at,is_available,reason").eq("dietitian_id",dietitianId).gte("ends_at",today.toISOString()).order("starts_at").limit(100),
    ]);
    setRules((r||[]) as AvailabilityRuleRow[]);setExceptions((e||[]) as AvailabilityExceptionRow[]);
  },[dietitianId,supabase]);
  useEffect(()=>{if(showAvailability)void loadAvailability()},[showAvailability,loadAvailability]);

  function moveDay(delta:number){const current=new Date(`${date}T12:00:00`);current.setDate(current.getDate()+delta);setDate(localDateKey(current));setSelectedSlot("")}
  function chooseSlot(slot:SlotRow){if(!slot.is_available)return;setSelectedSlot(slot.starts_at);setShowBooking(true)}

  async function book(){
    setMessage("");
    if(!selectedSlot||!dietitianId)return setMessage("Müsait bir saat seçin.");
    if(staff&&!form.client_id)return setMessage("Danışan seçin.");
    const {error}=await supabase.rpc("create_appointment_v2",{p_dietitian_id:dietitianId,p_client_id:staff?form.client_id:null,p_starts_at:selectedSlot,p_appointment_type:form.appointment_type,p_mode:form.mode,p_note:form.note||null});
    if(error)return setMessage(error.message);
    setMessage(staff?"Randevu oluşturuldu.":"Randevu talebiniz oluşturuldu ve onay bekliyor.");setShowBooking(false);setSelectedSlot("");setForm(current=>({...current,note:""}));await Promise.all([load(),loadSlots()]);
  }

  async function changeStatus(id:string,status:string){
    const reason=status==="cancelled"?window.prompt("İptal açıklaması (isteğe bağlı)")||null:null;
    const {error}=await supabase.rpc("update_appointment_status_v3",{p_appointment_id:id,p_status:status,p_reason:reason});
    if(error)setMessage(error.message);else{setMessage(status==="confirmed"?"Randevu onaylandı.":status==="cancelled"?"Randevu iptal edildi.":"Randevu durumu güncellendi.");await Promise.all([load(),loadSlots()]);}
  }

  async function addWeeklyRule(){
    if(!dietitianId)return; if(weeklyForm.end_time<=weeklyForm.start_time)return setMessage("Bitiş saati başlangıçtan sonra olmalıdır.");
    const {error}=await supabase.from("availability_rules").insert({dietitian_id:dietitianId,weekday:Number(weeklyForm.weekday),start_time:weeklyForm.start_time,end_time:weeklyForm.end_time,is_active:true});
    if(error)setMessage(error.message);else{setMessage("Haftalık çalışma saati eklendi.");await loadAvailability();await loadSlots();}
  }
  async function toggleRule(row:AvailabilityRuleRow){const {error}=await supabase.from("availability_rules").update({is_active:!row.is_active}).eq("id",row.id);if(error)setMessage(error.message);else{await loadAvailability();await loadSlots()}}
  async function deleteRule(id:string){if(!window.confirm("Bu çalışma aralığı silinsin mi?"))return;const {error}=await supabase.from("availability_rules").delete().eq("id",id);if(error)setMessage(error.message);else{await loadAvailability();await loadSlots()}}
  async function addException(){
    if(!dietitianId||!dailyForm.date)return setMessage("Tarih ve diyetisyen seçin.");
    if(dailyForm.end_time<=dailyForm.start_time)return setMessage("Bitiş saati başlangıçtan sonra olmalıdır.");
    const {error}=await supabase.from("availability_exceptions").insert({dietitian_id:dietitianId,starts_at:new Date(`${dailyForm.date}T${dailyForm.start_time}:00`).toISOString(),ends_at:new Date(`${dailyForm.date}T${dailyForm.end_time}:00`).toISOString(),is_available:dailyForm.is_available==="true",reason:dailyForm.reason||null});
    if(error)setMessage(error.message);else{setMessage("Güne özel saat kaydedildi.");await loadAvailability();await loadSlots()}
  }
  async function deleteException(id:string){if(!window.confirm("Bu güne özel kayıt silinsin mi?"))return;const {error}=await supabase.from("availability_exceptions").delete().eq("id",id);if(error)setMessage(error.message);else{await loadAvailability();await loadSlots()}}

  const upcoming=appointments.filter(a=>new Date(a.starts_at)>=new Date()||a.status==="pending").sort((a,b)=>new Date(a.starts_at).getTime()-new Date(b.starts_at).getTime());

  return <>
    <PageHeader title="Randevular" description={staff?"Müsait saatleri tek satırda yönetin; dolu saatlerde danışan iletişim bilgilerini görün ve randevuları onaylayın.":"Diyetisyeninizin müsait saatlerini seçin, talebinizin onay durumunu takip edin veya süresi uygunsa iptal edin."} action={<div className="header-button-row">{clinical&&<button className="secondary-button compact" onClick={()=>setShowAvailability(v=>!v)}><CalendarClock size={16}/>Çalışma saatleri</button>}<button className="secondary-button compact" onClick={()=>{void load();void loadSlots()}}><RefreshCw size={15}/>Yenile</button></div>}/>
    {message&&<div className="notice-bar"><AlertTriangle size={17}/>{message}<button onClick={()=>setMessage("")}><X size={15}/></button></div>}

    <section className="surface-card appointment-scheduler-v3">
      <div className="scheduler-toolbar">
        <label>Diyetisyen<select value={dietitianId} onChange={e=>{setDietitianId(e.target.value);setSelectedSlot("")}}>{dietitians.map(d=><option key={d.id} value={d.id}>{d.full_name}</option>)}</select></label>
        <div className="date-stepper"><button onClick={()=>moveDay(-1)} aria-label="Önceki gün"><ChevronLeft size={17}/></button><label><CalendarDays size={16}/><input type="date" min={localDateKey(new Date())} value={date} onChange={e=>{setDate(e.target.value);setSelectedSlot("")}}/></label><button onClick={()=>moveDay(1)} aria-label="Sonraki gün"><ChevronRight size={17}/></button></div>
        <div className="slot-legend"><span className="available">Müsait</span><span className="occupied">Dolu</span><span className="selected">Seçilen</span></div>
      </div>
      <div className="selected-day-title"><div><span>{new Date(`${date}T12:00:00`).toLocaleDateString("tr-TR",{weekday:"long"})}</span><h3>{new Date(`${date}T12:00:00`).toLocaleDateString("tr-TR",{day:"2-digit",month:"long",year:"numeric"})}</h3></div><small>{slots.filter(x=>x.is_available).length} müsait saat</small></div>
      {slotLoading?<Loading/>:<div className="slot-strip" role="list">{slots.length===0?<div className="slot-empty"><CalendarClock size={25}/><span>Bu gün için çalışma saati tanımlanmamış.</span></div>:slots.map(slot=>{
        const selected=slot.starts_at===selectedSlot;return <button type="button" role="listitem" key={slot.starts_at} className={`slot-card-v3 ${slot.is_available?"available":"occupied"} ${selected?"selected":""}`} disabled={!slot.is_available} onClick={()=>chooseSlot(slot)}>
          <strong>{new Date(slot.starts_at).toLocaleTimeString("tr-TR",{hour:"2-digit",minute:"2-digit"})}</strong><span>{slot.is_available?"Müsait":statusText(slot.appointment_status||"pending")}</span>{staff&&!slot.is_available&&<small>{slot.client_name}<br/>{slot.client_phone||slot.client_email||"İletişim yok"}</small>}{!staff&&!slot.is_available&&<small>Başka bir randevu</small>}
        </button>})}</div>}
    </section>

    {showBooking&&selectedSlot&&<section className="surface-card booking-inline-card">
      <div className="booking-selection"><div className="booking-time-icon"><CalendarCheck2 size={21}/></div><div><span>Seçilen randevu</span><b>{dateTime(selectedSlot)}</b></div></div>
      <div className="booking-inline-fields">
        {staff&&<label>Danışan<select value={form.client_id} onChange={e=>setForm({...form,client_id:e.target.value})}><option value="">Danışan seçin</option>{clients.map(c=><option key={c.id} value={c.id}>{c.full_name} • {c.member_no}</option>)}</select></label>}
        <label>Görüşme türü<select value={form.appointment_type} onChange={e=>setForm({...form,appointment_type:e.target.value})}><option>İlk görüşme</option><option>Kontrol</option><option>Ölçüm</option><option>Vücut analizi</option><option>Haftalık menü</option></select></label>
        <label>Yöntem<select value={form.mode} onChange={e=>setForm({...form,mode:e.target.value})}><option value="in_clinic">Klinik</option><option value="online">Online</option></select></label>
        <label className="wide">Not<input value={form.note} onChange={e=>setForm({...form,note:e.target.value})} placeholder="Randevu notu"/></label>
      </div><div className="form-actions"><button className="secondary-button" onClick={()=>{setShowBooking(false);setSelectedSlot("")}}>Vazgeç</button><button className="primary-button compact" onClick={book}><CalendarCheck2 size={16}/>{staff?"Randevuyu kaydet":"Randevu talebi gönder"}</button></div>
    </section>}

    {showAvailability&&clinical&&<section className="availability-v3-grid">
      <div className="surface-card"><div className="surface-head"><div><span className="section-kicker">TEKRARLAYAN</span><h3>Haftalık çalışma saatleri</h3><p>Her hafta otomatik oluşan müsaitlik aralıkları.</p></div><Clock3 size={20}/></div>
        <div className="compact-form-grid three-cols"><label>Gün<select value={weeklyForm.weekday} onChange={e=>setWeeklyForm({...weeklyForm,weekday:e.target.value})}>{weekdayOptions.map(x=><option key={x.value} value={x.value}>{x.label}</option>)}</select></label><label>Başlangıç<input type="time" value={weeklyForm.start_time} onChange={e=>setWeeklyForm({...weeklyForm,start_time:e.target.value})}/></label><label>Bitiş<input type="time" value={weeklyForm.end_time} onChange={e=>setWeeklyForm({...weeklyForm,end_time:e.target.value})}/></label></div>
        <button className="primary-button compact" onClick={addWeeklyRule}><Plus size={15}/>Saat ekle</button>
        <div className="schedule-list-v3">{rules.map(row=><article key={row.id} className={!row.is_active?"inactive":""}><div><b>{weekdayOptions.find(x=>Number(x.value)===row.weekday)?.label}</b><span>{row.start_time.slice(0,5)} — {row.end_time.slice(0,5)}</span></div><div><button onClick={()=>toggleRule(row)}>{row.is_active?"Pasif yap":"Aktif yap"}</button><button className="icon-danger" onClick={()=>deleteRule(row.id)}><Trash2 size={15}/></button></div></article>)}</div>
      </div>
      <div className="surface-card"><div className="surface-head"><div><span className="section-kicker">ÖZEL GÜN</span><h3>Güne özel müsaitlik</h3><p>Ek çalışma, izin veya kapalı saat tanımlayın.</p></div><CalendarDays size={20}/></div>
        <div className="compact-form-grid"><label>Tarih<input type="date" min={localDateKey(new Date())} value={dailyForm.date} onChange={e=>setDailyForm({...dailyForm,date:e.target.value})}/></label><label>Başlangıç<input type="time" value={dailyForm.start_time} onChange={e=>setDailyForm({...dailyForm,start_time:e.target.value})}/></label><label>Bitiş<input type="time" value={dailyForm.end_time} onChange={e=>setDailyForm({...dailyForm,end_time:e.target.value})}/></label><label>Tür<select value={dailyForm.is_available} onChange={e=>setDailyForm({...dailyForm,is_available:e.target.value})}><option value="true">Ek müsait</option><option value="false">Kapalı / izin</option></select></label><label className="wide">Açıklama<input value={dailyForm.reason} onChange={e=>setDailyForm({...dailyForm,reason:e.target.value})}/></label></div>
        <button className="primary-button compact" onClick={addException}><Plus size={15}/>Özel günü kaydet</button>
        <div className="schedule-list-v3">{exceptions.map(row=><article key={row.id}><div><b>{shortDate(row.starts_at)}</b><span>{new Date(row.starts_at).toLocaleTimeString("tr-TR",{hour:"2-digit",minute:"2-digit"})} — {new Date(row.ends_at).toLocaleTimeString("tr-TR",{hour:"2-digit",minute:"2-digit"})} • {row.is_available?"Ek müsait":"Kapalı"}</span>{row.reason&&<small>{row.reason}</small>}</div><button className="icon-danger" onClick={()=>deleteException(row.id)}><Trash2 size={15}/></button></article>)}</div>
      </div>
    </section>}

    <section className="surface-card appointments-table-card">
      <div className="surface-head"><div><span className="section-kicker">KAYITLAR</span><h3>{staff?"Randevu yönetimi":"Randevularım"}</h3><p>Onay, iptal ve görüşme durumlarını yönetin.</p></div><span className="count-pill">{upcoming.length} kayıt</span></div>
      {loading?<Loading/>:upcoming.length===0?<Empty text="Randevu kaydı bulunmuyor."/>:<div className="table-wrap modern-table-wrap"><table className="modern-table"><thead><tr><th>Tarih / Saat</th>{staff&&<th>Danışan</th>}<th>Diyetisyen</th><th>Görüşme</th><th>Durum</th><th>İşlem</th></tr></thead><tbody>{upcoming.map(row=><tr key={row.id}><td><b>{shortDate(row.starts_at)}</b><small>{new Date(row.starts_at).toLocaleTimeString("tr-TR",{hour:"2-digit",minute:"2-digit"})}</small></td>{staff&&<td><b>{row.client_name}</b><small>{row.client_phone||row.client_email||"—"}</small></td>}<td>{row.dietitian_name}</td><td><b>{row.appointment_type}</b><small>{row.mode==="online"?"Online":"Klinik"}</small></td><td><span className={`status ${row.status}`}>{statusText(row.status)}</span>{row.cancellation_reason&&<small>{row.cancellation_reason}</small>}</td><td><div className="table-actions">{staff&&row.status==="pending"&&<button className="action-success" onClick={()=>changeStatus(row.id,"confirmed")}><Check size={14}/>Onayla</button>}{staff&&row.status==="confirmed"&&<button className="action-success" onClick={()=>changeStatus(row.id,"completed")}><CheckCircle2 size={14}/>Tamamla</button>}{staff&&["pending","confirmed"].includes(row.status)&&<button className="action-danger" onClick={()=>changeStatus(row.id,"cancelled")}><XCircle size={14}/>İptal</button>}{staff&&row.status==="confirmed"&&<button className="action-muted" onClick={()=>changeStatus(row.id,"no_show")}>Gelmedi</button>}{!staff&&["pending","confirmed"].includes(row.status)&&<button className="action-danger" onClick={()=>changeStatus(row.id,"cancelled")}><XCircle size={14}/>İptal et</button>}{!["pending","confirmed"].includes(row.status)&&<span className="muted-line">İşlem yok</span>}</div></td></tr>)}</tbody></table></div>}
    </section>
  </>;
}

export function ClientsV3({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);
  const clinical=role==="owner"||role==="dietitian";
  const paymentEditor=role==="owner"||role==="secretary";
  const [rows,setRows]=useState<ClientRow[]>([]);
  const [dietitians,setDietitians]=useState<DietitianRow[]>([]);
  const [query,setQuery]=useState("");
  const [loading,setLoading]=useState(true);
  const [message,setMessage]=useState("");
  const [selected,setSelected]=useState<ClientRow|null>(null);
  const [payments,setPayments]=useState<PaymentRow[]>([]);
  const [appointments,setAppointments]=useState<AppointmentRow[]>([]);
  const [history,setHistory]=useState<LoyaltyHistoryRow[]>([]);
  const [recipeHistory,setRecipeHistory]=useState<AIRecipeHistoryRow[]>([]);
  const [scanHistory,setScanHistory]=useState<FoodScanHistoryRow[]>([]);
  const [detailLoading,setDetailLoading]=useState(false);
  const [showPaymentForm,setShowPaymentForm]=useState(false);
  const [editingPaymentId,setEditingPaymentId]=useState<string|null>(null);
  const [paymentForm,setPaymentForm]=useState({service_type:"Kontrol görüşmesi",description:"",amount:"",status:"paid",method:"cash",paid_at:localDateKey(new Date())});
  const [pointForm,setPointForm]=useState({points:"",reason:""});

  const load=useCallback(async()=>{
    setLoading(true);setMessage("");
    const [{data,error},{data:d}]=await Promise.all([
      supabase.rpc("get_client_directory_v4"),
      supabase.from("dietitian_profiles").select("id,user_id,title,appointment_duration_minutes,buffer_minutes,is_bookable").eq("clinic_id",clinicId),
    ]);
    if(error)setMessage(error.message);else setRows((data||[]) as ClientRow[]);
    const ds=(d||[]) as Omit<DietitianRow,"full_name">[]; const ids=ds.map(x=>x.user_id);
    const {data:p}=ids.length?await supabase.from("profiles").select("id,full_name").in("id",ids):{data:[]};const map=new Map((p||[]).map((x:any)=>[x.id,x.full_name]));
    setDietitians(ds.map(x=>({...x,full_name:map.get(x.user_id)||"Diyetisyen"})) as DietitianRow[]);
    setLoading(false);
  },[clinicId,supabase]);
  useEffect(()=>{void load()},[load]);

  async function openDetail(client:ClientRow){
    setSelected(client);setDetailLoading(true);setShowPaymentForm(false);setEditingPaymentId(null);
    const [paymentResult,appointmentResult,historyResult,recipeResult,scanResult]=await Promise.all([
      supabase.from("payments").select("id,clinic_id,client_id,appointment_id,service_type,description,amount,currency,status,method,paid_at,created_at,updated_at").eq("client_id",client.id).order("created_at",{ascending:false}),
      supabase.from("appointments").select("id,client_id,dietitian_id,starts_at,ends_at,appointment_type,mode,status,public_note,cancellation_reason").eq("client_id",client.id).order("starts_at",{ascending:false}).limit(30),
      clinical?supabase.rpc("get_client_loyalty_history",{p_client_id:client.id}):Promise.resolve({data:[],error:null}),
      clinical?supabase.from("ai_generated_recipes").select("id,meal_type,ingredients,recipe,created_at").eq("client_id",client.id).order("created_at",{ascending:false}).limit(5):Promise.resolve({data:[],error:null}),
      clinical?supabase.from("food_label_scans").select("id,filename,result,created_at").eq("client_id",client.id).order("created_at",{ascending:false}).limit(5):Promise.resolve({data:[],error:null}),
    ]);
    if(paymentResult.error)setMessage(paymentResult.error.message);setPayments((paymentResult.data||[]) as PaymentRow[]);
    const dMap=new Map(dietitians.map(x=>[x.id,x.full_name]));setAppointments(((appointmentResult.data||[]) as AppointmentRow[]).map(x=>({...x,dietitian_name:dMap.get(x.dietitian_id)||"Diyetisyen"})));
    setHistory((historyResult.data||[]) as LoyaltyHistoryRow[]);
    setRecipeHistory((recipeResult.data||[]) as AIRecipeHistoryRow[]);
    setScanHistory((scanResult.data||[]) as FoodScanHistoryRow[]);
    setDetailLoading(false);
  }

  function startPayment(payment?:PaymentRow){
    if(payment){setEditingPaymentId(payment.id);setPaymentForm({service_type:payment.service_type,description:payment.description||"",amount:String(payment.amount),status:payment.status,method:payment.method||"cash",paid_at:payment.paid_at?localDateKey(new Date(payment.paid_at)):localDateKey(new Date())});}
    else{setEditingPaymentId(null);setPaymentForm({service_type:"Kontrol görüşmesi",description:"",amount:"",status:"paid",method:"cash",paid_at:localDateKey(new Date())});}
    setShowPaymentForm(true);
  }

  async function savePayment(){
    if(!selected)return;setMessage("");
    if(!paymentForm.service_type.trim()||Number(paymentForm.amount)<0)return setMessage("Hizmet ve geçerli tutar zorunludur.");
    const {error}=await supabase.rpc("save_payment_v3",{p_payment_id:editingPaymentId,p_client_id:selected.id,p_appointment_id:null,p_service_type:paymentForm.service_type,p_description:paymentForm.description||null,p_amount:Number(paymentForm.amount),p_status:paymentForm.status,p_method:paymentForm.method||null,p_paid_at:paymentForm.paid_at?new Date(`${paymentForm.paid_at}T12:00:00`).toISOString():null});
    if(error)return setMessage(error.message);
    setMessage(editingPaymentId?"Ödeme kaydı güncellendi.":"Ödeme kaydı eklendi.");setShowPaymentForm(false);setEditingPaymentId(null);await load();const fresh=(await supabase.rpc("get_client_directory_v4")).data as ClientRow[]|null;const updated=fresh?.find(x=>x.id===selected.id);if(updated)await openDetail(updated);
  }

  async function assignDietitian(value:string){
    if(!selected||!value)return;const {error}=await supabase.rpc("assign_client_dietitian_v3",{p_client_id:selected.id,p_dietitian_id:value});if(error)setMessage(error.message);else{setMessage("Danışmanın sorumlu diyetisyeni güncellendi.");await load();const fresh=(await supabase.rpc("get_client_directory_v4")).data as ClientRow[]|null;const updated=fresh?.find(x=>x.id===selected.id);if(updated)setSelected(updated)}
  }

  async function addPoints(){
    if(!selected)return;const points=Number(pointForm.points);if(!Number.isInteger(points)||points<=0)return setMessage("Puan pozitif tam sayı olmalıdır.");if(!pointForm.reason.trim())return setMessage("Puan nedeni zorunludur.");
    const {error}=await supabase.rpc("add_client_loyalty_points",{p_client_id:selected.id,p_points:points,p_reason:pointForm.reason.trim()});if(error)return setMessage(error.message);setPointForm({points:"",reason:""});setMessage("Sadakat puanı eklendi ve loglandı.");await load();const fresh=(await supabase.rpc("get_client_directory_v4")).data as ClientRow[]|null;const updated=fresh?.find(x=>x.id===selected.id);if(updated)await openDetail(updated);
  }

  const filtered=rows.filter(x=>`${x.full_name} ${x.member_no} ${x.email||""} ${x.phone||""} ${x.assigned_dietitian_name||""}`.toLocaleLowerCase("tr").includes(query.toLocaleLowerCase("tr")));
  return <>
    <PageHeader title="Danışanlar" description={role==="secretary"?"Danışan iletişim bilgilerini, randevuları ve ödeme kayıtlarını yönetin.":"Üye numarası, ölçümler, hedefler, alerjiler, menü tercihleri, sadakat ve ödeme durumunu ayrıntılı görüntüleyin."} action={<button className="secondary-button compact" onClick={load}><RefreshCw size={15}/>Yenile</button>}/>
    {message&&<div className="notice-bar"><AlertTriangle size={17}/>{message}<button onClick={()=>setMessage("")}><X size={15}/></button></div>}
    <div className="client-toolbar-v3"><div className="search-box modern-search"><Search size={18}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="İsim, telefon, e-posta, üye no veya diyetisyen ara"/></div><span className="count-pill">{filtered.length} danışan</span></div>
    <section className="surface-card client-table-card">{loading?<Loading/>:filtered.length===0?<Empty text="Danışan bulunamadı."/>:<div className="table-wrap modern-table-wrap"><table className="modern-table client-directory-table"><thead><tr><th>Danışan</th><th>Üye No</th><th>Sorumlu diyetisyen</th>{clinical&&<><th>Son ölçüm</th><th>Beslenme uyarıları</th></>}<th>Ödeme</th>{clinical&&<th>Sadakat</th>}<th>Detay</th></tr></thead><tbody>{filtered.map(c=><tr key={c.id}><td><div className="person-cell"><span className="avatar">{initials(c.full_name)}</span><div><b>{c.full_name}</b><small>{c.phone||c.email||"İletişim yok"}</small></div></div></td><td><code className="member-code">{c.member_no}</code></td><td>{c.assigned_dietitian_name||<span className="warning-text">Atanmadı</span>}</td>{clinical&&<><td><b>{c.latest_weight_kg?`${c.latest_weight_kg} kg`:"—"}</b><small>{c.latest_measurement_at?shortDate(c.latest_measurement_at):"Ölçüm yok"}</small></td><td><div className="warning-badges">{c.allergies?.length>0&&<span className="danger-chip">{c.allergies.length} alerji</span>}{c.disliked_foods?.length>0&&<span className="amber-chip">{c.disliked_foods.length} tercih dışı</span>}{!c.allergies?.length&&!c.disliked_foods?.length&&<span className="neutral-chip">Bildirim yok</span>}</div></td></>}<td><div className="payment-summary-cell"><span className={`payment-badge ${c.last_payment_status||"none"}`}>{paymentStatusText(c.last_payment_status)}</span><b>{c.payment_due>0?`${money(c.payment_due)} bekliyor`:c.payment_paid>0?`${money(c.payment_paid)} ödendi`:"Kayıt yok"}</b><small>{c.last_payment_method?paymentMethodText(c.last_payment_method):c.last_payment_service||"—"}</small></div></td>{clinical&&<td><b>{c.loyalty_balance.toLocaleString("tr-TR")}</b><small>{c.loyalty_used.toLocaleString("tr-TR")} kullanıldı</small></td>}<td><button className="detail-button" onClick={()=>openDetail(c)}><Eye size={15}/>Detaylı göster</button></td></tr>)}</tbody></table></div>}</section>

    {selected&&<div className="drawer-backdrop" onMouseDown={e=>{if(e.target===e.currentTarget)setSelected(null)}}><aside className="detail-drawer">
      <header className="detail-drawer-head"><div className="person-cell"><span className="avatar large">{initials(selected.full_name)}</span><div><span className="section-kicker">DANIŞAN DETAYI</span><h2>{selected.full_name}</h2><p>{selected.member_no}</p></div></div><button className="drawer-close" onClick={()=>setSelected(null)}><X size={20}/></button></header>
      {detailLoading?<Loading/>:<div className="drawer-content">
        <section className="detail-section"><div className="detail-section-head"><UserRound size={18}/><h3>Üyelik ve iletişim</h3></div><div className="detail-info-grid"><div><small>Üye numarası</small><b>{selected.member_no}</b></div><div><small>Kayıt tarihi</small><b>{shortDate(selected.created_at)}</b></div><div><small>Telefon</small><b>{selected.phone||"—"}</b></div><div><small>E-posta</small><b>{selected.email||"—"}</b></div><div><small>Doğum tarihi</small><b>{selected.birth_date?shortDate(selected.birth_date):"—"}</b></div><div><small>Cinsiyet</small><b>{selected.gender||"—"}</b></div></div></section>

        <section className="detail-section"><div className="detail-section-head"><UserCheck size={18}/><h3>Sorumlu diyetisyen</h3></div>{clinical?<label className="drawer-select">Diyetisyen<select value={selected.assigned_dietitian_id||""} onChange={e=>assignDietitian(e.target.value)}><option value="">Diyetisyen atayın</option>{dietitians.map(d=><option key={d.id} value={d.id}>{d.full_name}</option>)}</select></label>:<p>{selected.assigned_dietitian_name||"Henüz atanmadı"}</p>}</section>

        {clinical&&<><section className="detail-section"><div className="detail-section-head"><Activity size={18}/><h3>Vücut ve hedef bilgileri</h3></div><div className="clinical-stat-grid"><div><Weight size={17}/><span><small>Son kilo</small><b>{selected.latest_weight_kg?`${selected.latest_weight_kg} kg`:"—"}</b></span></div><div><Activity size={17}/><span><small>Yağ oranı</small><b>{selected.latest_body_fat_percent?`%${selected.latest_body_fat_percent}`:"—"}</b></span></div><div><UserRound size={17}/><span><small>Boy</small><b>{selected.height_cm?`${selected.height_cm} cm`:"—"}</b></span></div><div><Sparkles size={17}/><span><small>Hedef kilo</small><b>{selected.target_weight_kg?`${selected.target_weight_kg} kg`:(selected.target_text||"—")}</b></span></div></div></section>
        <section className="detail-section onboarding-detail"><div className="detail-section-head"><Sparkles size={18}/><h3>Kişiselleştirme ve ön görüşme</h3><span className={`status ${selected.onboarding_completed?"confirmed":"pending"}`}>{selected.onboarding_completed?"Tamamlandı":"Eksik"}</span></div><div className="detail-info-grid"><div><small>Ana hedef</small><b>{goalText(selected.primary_goal)}</b></div><div><small>Aktivite</small><b>{activityText(selected.activity_level)}</b></div><div><small>Beslenme tarzı</small><b>{selected.diet_style||"—"}</b></div><div><small>Su hedefi</small><b>{selected.water_goal_ml?`${selected.water_goal_ml} ml`:"—"}</b></div><div className="wide"><small>Motivasyonlar</small><div className="warning-badges">{selected.motivation_reasons?.length?selected.motivation_reasons.map(x=><span className="neutral-chip" key={x}>{x}</span>):<span>Bildirilmedi</span>}</div></div><div className="wide"><small>Kronik durumlar</small><div className="warning-badges">{selected.chronic_conditions?.length?selected.chronic_conditions.map(x=><span className="amber-chip" key={x}>{x}</span>):<span>Bildirilmedi</span>}</div></div><div className="wide"><small>Katkı reaksiyonları</small><div className="warning-badges">{selected.additive_reactions?.length?selected.additive_reactions.map(x=><span className="danger-chip" key={x}>{x}</span>):<span>Bildirilmedi</span>}</div></div></div></section>
        <section className="detail-section"><div className="detail-section-head"><BrainCircuit size={18}/><h3>AI kullanım geçmişi</h3></div><div className="ai-history-grid"><div><small>Son tarifler</small>{recipeHistory.length?recipeHistory.map(row=><article key={row.id}><b>{String(row.recipe?.title||row.meal_type||"AI tarifi")}</b><p>{shortDate(row.created_at)} • {row.ingredients}</p></article>):<p>Henüz AI tarifi oluşturulmadı.</p>}</div><div><small>Son yiyecek taramaları</small>{scanHistory.length?scanHistory.map(row=><article key={row.id}><b>{String(row.result?.product_name||row.filename||"Etiket analizi")}</b><p>{shortDate(row.created_at)} • {String(row.result?.summary||"")}</p></article>):<p>Henüz etiket taraması yapılmadı.</p>}</div></div></section>
        <section className="detail-section warning-detail"><div className="detail-section-head"><TriangleAlert size={18}/><h3>Beslenme ve sağlık uyarıları</h3></div><div className="warning-detail-grid"><div><small>Alerjiler</small><div>{selected.allergies?.length?selected.allergies.map(x=><span className="danger-chip" key={x}>{x}</span>):<span>Bildirilmedi</span>}</div></div><div><small>Sevmediği / kullanmadığı besinler</small><div>{selected.disliked_foods?.length?selected.disliked_foods.map(x=><span className="amber-chip" key={x}>{x}</span>):<span>Bildirilmedi</span>}</div></div><div><small>Sağlık notları</small><p>{selected.medical_notes||"—"}</p></div><div><small>İlaçlar</small><p>{selected.medications||"—"}</p></div></div></section></>}

        <section className="detail-section"><div className="detail-section-head"><CreditCard size={18}/><h3>Ödemeler</h3>{paymentEditor&&<button className="detail-head-action" onClick={()=>startPayment()}><Plus size={14}/>Ödeme ekle</button>}</div>
          <div className="payment-totals"><div><small>Toplam</small><b>{money(selected.payment_total)}</b></div><div><small>Alınan</small><b className="success-text">{money(selected.payment_paid)}</b></div><div><small>Kalan</small><b className={selected.payment_due>0?"danger-text":"success-text"}>{money(selected.payment_due)}</b></div></div>
          {showPaymentForm&&paymentEditor&&<div className="inline-editor"><div className="compact-form-grid"><label>Hizmet<input value={paymentForm.service_type} onChange={e=>setPaymentForm({...paymentForm,service_type:e.target.value})} placeholder="Vücut analizi, haftalık menü..."/></label><label>Tutar<input type="number" min="0" step="0.01" value={paymentForm.amount} onChange={e=>setPaymentForm({...paymentForm,amount:e.target.value})}/></label><label>Durum<select value={paymentForm.status} onChange={e=>setPaymentForm({...paymentForm,status:e.target.value})}><option value="paid">Ödendi</option><option value="pending">Bekliyor</option><option value="partial">Kısmi</option><option value="refunded">İade</option><option value="cancelled">İptal</option></select></label><label>Yöntem<select value={paymentForm.method} onChange={e=>setPaymentForm({...paymentForm,method:e.target.value})}><option value="cash">Nakit</option><option value="card">Kart</option><option value="iban">IBAN</option><option value="other">Diğer</option></select></label><label>Ödeme tarihi<input type="date" value={paymentForm.paid_at} onChange={e=>setPaymentForm({...paymentForm,paid_at:e.target.value})}/></label><label className="wide">Açıklama<input value={paymentForm.description} onChange={e=>setPaymentForm({...paymentForm,description:e.target.value})}/></label></div><div className="form-actions"><button className="secondary-button compact" onClick={()=>setShowPaymentForm(false)}>Vazgeç</button><button className="primary-button compact" onClick={savePayment}><Save size={14}/>{editingPaymentId?"Güncelle":"Kaydet"}</button></div></div>}
          {payments.length===0?<p className="muted-line">Ödeme kaydı bulunmuyor.</p>:<div className="drawer-list">{payments.map(p=><article key={p.id}><div className="drawer-list-icon"><WalletCards size={17}/></div><div className="grow"><b>{p.service_type}</b><p>{money(p.amount)} • {paymentMethodText(p.method)} • {shortDate(p.paid_at||p.created_at)}</p>{p.description&&<small>{p.description}</small>}</div><span className={`payment-badge ${p.status}`}>{paymentStatusText(p.status)}</span>{paymentEditor&&<button className="icon-action" onClick={()=>startPayment(p)}><Pencil size={14}/></button>}</article>)}</div>}
        </section>

        {clinical&&<section className="detail-section"><div className="detail-section-head"><Gift size={18}/><h3>Sadakat hesabı</h3></div><div className="loyalty-detail-summary"><div><small>Kazanılan</small><b>{selected.loyalty_earned.toLocaleString("tr-TR")}</b></div><div><small>Kullanılan</small><b>{selected.loyalty_used.toLocaleString("tr-TR")}</b></div><div><small>Kalan</small><b>{selected.loyalty_balance.toLocaleString("tr-TR")}</b></div></div><div className="compact-form-grid loyalty-add-inline"><label>Puan<input type="number" min="1" value={pointForm.points} onChange={e=>setPointForm({...pointForm,points:e.target.value})}/></label><label>Neden<input value={pointForm.reason} onChange={e=>setPointForm({...pointForm,reason:e.target.value})} placeholder="Örn. programa uyum"/></label><button className="primary-button compact" onClick={addPoints}><Plus size={14}/>Ekle</button></div>{history.length>0&&<details className="history-details"><summary>Puan hareketlerini göster ({history.length})</summary><div className="drawer-list">{history.map(h=><article key={h.id}><div className={`point-direction ${h.points>=0?"up":"down"}`}>{h.points>=0?<ArrowUpRight size={15}/>:<ArrowDownRight size={15}/>}</div><div className="grow"><b>{h.reason}</b><p>{h.actor_name||"Sistem"} • {dateTime(h.created_at)}</p></div><strong>{h.points>0?"+":""}{h.points}</strong></article>)}</div></details>}</section>}

        <section className="detail-section"><div className="detail-section-head"><CalendarDays size={18}/><h3>Randevu geçmişi</h3></div>{appointments.length===0?<p className="muted-line">Randevu kaydı bulunmuyor.</p>:<div className="drawer-list">{appointments.map(a=><article key={a.id}><div className="drawer-list-icon"><CalendarCheck2 size={17}/></div><div className="grow"><b>{a.appointment_type}</b><p>{dateTime(a.starts_at)} • {a.dietitian_name} • {a.mode==="online"?"Online":"Klinik"}</p></div><span className={`status ${a.status}`}>{statusText(a.status)}</span></article>)}</div>}</section>
      </div>}
    </aside></div>}
  </>;
}

export function PaymentsV3({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);
  const canEdit=role==="owner"||role==="secretary";
  const [rows,setRows]=useState<PaymentRow[]>([]);const [clients,setClients]=useState<ClientRow[]>([]);const [loading,setLoading]=useState(true);const [message,setMessage]=useState("");
  const [filters,setFilters]=useState({status:"all",method:"all",query:""});const [showForm,setShowForm]=useState(false);const [editingId,setEditingId]=useState<string|null>(null);
  const [form,setForm]=useState({client_id:"",service_type:"Kontrol görüşmesi",description:"",amount:"",status:"paid",method:"cash",paid_at:localDateKey(new Date())});
  const load=useCallback(async()=>{setLoading(true);const [{data:p,error},{data:c}]=await Promise.all([supabase.from("payments").select("id,clinic_id,client_id,appointment_id,service_type,description,amount,currency,status,method,paid_at,created_at,updated_at").eq("clinic_id",clinicId).order("created_at",{ascending:false}),supabase.rpc("get_client_directory_v4")]);if(error)setMessage(error.message);const cs=(c||[]) as ClientRow[];setClients(cs);const map=new Map(cs.map(x=>[x.id,x]));setRows(((p||[]) as PaymentRow[]).map(x=>({...x,client_name:map.get(x.client_id)?.full_name||"Danışan",member_no:map.get(x.client_id)?.member_no||""})));setForm(current=>({...current,client_id:cs.some(x=>x.id===current.client_id)?current.client_id:(cs[0]?.id||"")}));setLoading(false)},[clinicId,supabase]);useEffect(()=>{void load()},[load]);
  function start(row?:PaymentRow){if(row){setEditingId(row.id);setForm({client_id:row.client_id,service_type:row.service_type,description:row.description||"",amount:String(row.amount),status:row.status,method:row.method||"cash",paid_at:row.paid_at?localDateKey(new Date(row.paid_at)):localDateKey(new Date())});}else{setEditingId(null);setForm({client_id:clients[0]?.id||"",service_type:"Kontrol görüşmesi",description:"",amount:"",status:"paid",method:"cash",paid_at:localDateKey(new Date())});}setShowForm(true)}
  async function save(){if(!form.client_id||!form.service_type.trim())return setMessage("Danışan ve hizmet zorunludur.");const {error}=await supabase.rpc("save_payment_v3",{p_payment_id:editingId,p_client_id:form.client_id,p_appointment_id:null,p_service_type:form.service_type,p_description:form.description||null,p_amount:Number(form.amount)||0,p_status:form.status,p_method:form.method||null,p_paid_at:form.paid_at?new Date(`${form.paid_at}T12:00:00`).toISOString():null});if(error)setMessage(error.message);else{setMessage(editingId?"Ödeme güncellendi.":"Ödeme eklendi.");setShowForm(false);await load()}}
  const filtered=rows.filter(x=>(filters.status==="all"||x.status===filters.status)&&(filters.method==="all"||x.method===filters.method)&&`${x.client_name} ${x.member_no} ${x.service_type}`.toLocaleLowerCase("tr").includes(filters.query.toLocaleLowerCase("tr")));
  const paidTotal=filtered.filter(x=>x.status==="paid").reduce((s,x)=>s+Number(x.amount),0);const pendingTotal=filtered.filter(x=>["pending","partial"].includes(x.status)).reduce((s,x)=>s+Number(x.amount),0);
  return <><PageHeader title="Ödemeler" description="Danışan hizmetlerini, ödeme durumlarını ve Nakit / Kart / IBAN yöntemlerini yönetin." action={canEdit?<button className="primary-button compact" onClick={()=>start()}><Plus size={15}/>Ödeme ekle</button>:undefined}/>{message&&<div className="notice-bar"><AlertTriangle size={17}/>{message}</div>}
    <div className="payment-metric-row"><article><WalletCards size={19}/><span><small>Gösterilen kayıt</small><b>{filtered.length}</b></span></article><article><CheckCircle2 size={19}/><span><small>Ödenen toplam</small><b>{money(paidTotal)}</b></span></article><article><Clock3 size={19}/><span><small>Bekleyen toplam</small><b>{money(pendingTotal)}</b></span></article></div>
    <div className="filter-bar"><div className="search-box modern-search"><Search size={17}/><input value={filters.query} onChange={e=>setFilters({...filters,query:e.target.value})} placeholder="Danışan, üye no veya hizmet ara"/></div><select value={filters.status} onChange={e=>setFilters({...filters,status:e.target.value})}><option value="all">Tüm durumlar</option><option value="paid">Ödendi</option><option value="pending">Bekliyor</option><option value="partial">Kısmi</option><option value="refunded">İade</option><option value="cancelled">İptal</option></select><select value={filters.method} onChange={e=>setFilters({...filters,method:e.target.value})}><option value="all">Tüm yöntemler</option><option value="cash">Nakit</option><option value="card">Kart</option><option value="iban">IBAN</option><option value="other">Diğer</option></select></div>
    {showForm&&canEdit&&<section className="surface-card payment-form-card"><div className="surface-head"><div><span className="section-kicker">{editingId?"DÜZENLE":"YENİ KAYIT"}</span><h3>Ödeme bilgisi</h3></div><button className="drawer-close" onClick={()=>setShowForm(false)}><X size={18}/></button></div><div className="form-grid"><label>Danışan<select value={form.client_id} onChange={e=>setForm({...form,client_id:e.target.value})}>{clients.map(c=><option key={c.id} value={c.id}>{c.full_name} • {c.member_no}</option>)}</select></label><label>Hizmet<input value={form.service_type} onChange={e=>setForm({...form,service_type:e.target.value})} placeholder="Vücut analizi, haftalık menü..."/></label><label>Tutar<input type="number" min="0" step="0.01" value={form.amount} onChange={e=>setForm({...form,amount:e.target.value})}/></label><label>Durum<select value={form.status} onChange={e=>setForm({...form,status:e.target.value})}><option value="paid">Ödendi</option><option value="pending">Bekliyor</option><option value="partial">Kısmi</option><option value="refunded">İade</option><option value="cancelled">İptal</option></select></label><label>Yöntem<select value={form.method} onChange={e=>setForm({...form,method:e.target.value})}><option value="cash">Nakit</option><option value="card">Kart</option><option value="iban">IBAN</option><option value="other">Diğer</option></select></label><label>Ödeme tarihi<input type="date" value={form.paid_at} onChange={e=>setForm({...form,paid_at:e.target.value})}/></label><label className="wide">Açıklama<input value={form.description} onChange={e=>setForm({...form,description:e.target.value})}/></label></div><div className="form-actions"><button className="secondary-button" onClick={()=>setShowForm(false)}>Vazgeç</button><button className="primary-button compact" onClick={save}><Save size={15}/>Kaydet</button></div></section>}
    <section className="surface-card">{loading?<Loading/>:filtered.length===0?<Empty text="Ödeme kaydı bulunmuyor."/>:<div className="table-wrap modern-table-wrap"><table className="modern-table"><thead><tr><th>Danışan</th><th>Hizmet</th><th>Tutar</th><th>Durum</th><th>Yöntem</th><th>Tarih</th><th>İşlem</th></tr></thead><tbody>{filtered.map(row=><tr key={row.id}><td><b>{row.client_name}</b><small>{row.member_no}</small></td><td><b>{row.service_type}</b><small>{row.description||"—"}</small></td><td><b>{money(row.amount)}</b></td><td><span className={`payment-badge ${row.status}`}>{paymentStatusText(row.status)}</span></td><td>{paymentMethodText(row.method)}</td><td>{shortDate(row.paid_at||row.created_at)}</td><td>{canEdit?<button className="detail-button" onClick={()=>start(row)}><Pencil size={14}/>Düzenle</button>:"—"}</td></tr>)}</tbody></table></div>}</section>
  </>;
}

export function MealPlansV3({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);const staff=role==="owner"||role==="dietitian";
  const [plans,setPlans]=useState<MealPlanRow[]>([]);const [items,setItems]=useState<Record<string,MealItemRow[]>>({});const [photos,setPhotos]=useState<MealPhotoRow[]>([]);const [clients,setClients]=useState<ClientRow[]>([]);const [catalog,setCatalog]=useState<FoodCatalogRow[]>([]);const [message,setMessage]=useState("");const [loading,setLoading]=useState(true);const [showForm,setShowForm]=useState(false);const [editingId,setEditingId]=useState<string|null>(null);const [uploadingKey,setUploadingKey]=useState("");
  const [draft,setDraft]=useState<MealDraftItem[]>(()=>[createMealDraft("initial-meal")]);const [form,setForm]=useState({client_id:"",title:"Beslenme Planı",starts_on:"",ends_on:"",calories:"",protein:"",carbs:"",fat:"",note:""});
  const effectiveCatalog=useMemo(()=>{const map=new Map<string,FoodCatalogRow>();catalog.filter(x=>x.clinic_id===null).forEach(x=>map.set(x.name_key,x));catalog.filter(x=>x.clinic_id===clinicId).forEach(x=>map.set(x.name_key,x));return [...map.values()].sort((a,b)=>a.name.localeCompare(b.name,"tr"))},[catalog,clinicId]);
  const totals=useMemo(()=>draft.reduce((s,x)=>({calories:s.calories+(Number(x.calories)||0),protein:s.protein+(Number(x.protein)||0),carbs:s.carbs+(Number(x.carbs)||0),fat:s.fat+(Number(x.fat)||0)}),{calories:0,protein:0,carbs:0,fat:0}),[draft]);
  const selectedClient=clients.find(x=>x.id===form.client_id)||null;

  const load=useCallback(async()=>{
    setLoading(true);
    const [{data:p,error:planError},{data:c},{data:f}]=await Promise.all([
      supabase.from("meal_plans").select("id,client_id,dietitian_id,title,starts_on,ends_on,target_calories,target_protein_g,target_carbs_g,target_fat_g,status,dietitian_note").order("created_at",{ascending:false}),
      staff?supabase.rpc("get_client_directory_v4"):Promise.resolve({data:[],error:null}),
      staff?supabase.from("food_catalog").select("id,clinic_id,name,name_key,calories_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g,default_portion_g,source_label,is_active").eq("is_active",true).order("name"):Promise.resolve({data:[],error:null}),
    ]);
    if(planError)setMessage(planError.message);
    const cs=(c||[]) as ClientRow[];setClients(cs);setCatalog((f||[]) as FoodCatalogRow[]);
    const cMap=new Map(cs.map(x=>[x.id,x.full_name]));const ps=((p||[]) as MealPlanRow[]).map(x=>({...x,client_name:staff?(cMap.get(x.client_id)||"Danışan"):"Beslenme planınız"}));setPlans(ps);
    setForm(current=>({...current,client_id:cs.some(x=>x.id===current.client_id)?current.client_id:(cs[0]?.id||"")}));
    const ids=ps.map(x=>x.id);
    if(ids.length){
      const [{data:it},{data:comp},{data:photoRows}]=await Promise.all([
        supabase.from("meal_plan_items").select("id,meal_plan_id,meal_name,food_name,portion_text,calories,protein_g,carbs_g,fat_g,sort_order").in("meal_plan_id",ids).order("sort_order"),
        staff?Promise.resolve({data:[]}):supabase.from("meal_completions").select("item_id").eq("consumed_on",localDateKey(new Date())),
        supabase.from("meal_photos").select("id,clinic_id,client_id,meal_plan_id,meal_name,consumed_on,photo_path,caption,created_at").in("meal_plan_id",ids).order("created_at",{ascending:false}),
      ]);
      const done=new Set((comp||[]).map((x:any)=>x.item_id));const grouped:Record<string,MealItemRow[]>={};((it||[]) as MealItemRow[]).forEach(x=>(grouped[x.meal_plan_id]??=[]).push({...x,completed:done.has(x.id)}));setItems(grouped);
      const signed=await Promise.all(((photoRows||[]) as MealPhotoRow[]).map(async row=>{const {data:url}=await supabase.storage.from("meal-photos").createSignedUrl(row.photo_path,3600);return{...row,signed_url:url?.signedUrl}}));setPhotos(signed);
    }else{setItems({});setPhotos([])}
    setLoading(false);
  },[staff,supabase]);
  useEffect(()=>{void load()},[load]);

  function calculate(food:FoodCatalogRow,qValue:string){const q=Number(qValue)||food.default_portion_g||100;const factor=q/100;return{quantity_g:String(q),calories:String(roundNutrition(food.calories_per_100g*factor)),protein:String(roundNutrition(food.protein_per_100g*factor)),carbs:String(roundNutrition(food.carbs_per_100g*factor)),fat:String(roundNutrition(food.fat_per_100g*factor))}}
  function updateItem(key:string,patch:Partial<MealDraftItem>){setDraft(current=>current.map(x=>x.key===key?{...x,...patch}:x))}
  function selectCatalog(key:string,id:string){const food=effectiveCatalog.find(x=>x.id===id);if(!food)return updateItem(key,{catalog_id:null});const current=draft.find(x=>x.key===key);updateItem(key,{catalog_id:food.id,food_name:food.name,...calculate(food,current?.quantity_g||String(food.default_portion_g))})}
  function changeName(key:string,name:string){const food=effectiveCatalog.find(x=>foodNameKey(x.name)===foodNameKey(name));if(food){const current=draft.find(x=>x.key===key);updateItem(key,{catalog_id:food.id,food_name:food.name,...calculate(food,current?.quantity_g||String(food.default_portion_g))})}else updateItem(key,{food_name:name,catalog_id:null})}
  function changeQuantity(key:string,value:string){const current=draft.find(x=>x.key===key);const food=effectiveCatalog.find(x=>x.id===current?.catalog_id);if(food)updateItem(key,{...calculate(food,value)});else updateItem(key,{quantity_g:value})}
  function reset(clientId?:string){setEditingId(null);setDraft([createMealDraft(globalThis.crypto.randomUUID())]);setForm({client_id:clientId||clients[0]?.id||"",title:"Beslenme Planı",starts_on:"",ends_on:"",calories:"",protein:"",carbs:"",fat:"",note:""})}
  function startEdit(plan:MealPlanRow){setEditingId(plan.id);setForm({client_id:plan.client_id,title:plan.title,starts_on:plan.starts_on,ends_on:plan.ends_on,calories:plan.target_calories==null?"":String(plan.target_calories),protein:plan.target_protein_g==null?"":String(plan.target_protein_g),carbs:plan.target_carbs_g==null?"":String(plan.target_carbs_g),fat:plan.target_fat_g==null?"":String(plan.target_fat_g),note:plan.dietitian_note||""});const existing=items[plan.id]||[];setDraft(existing.length?existing.map(x=>({key:x.id,meal_name:x.meal_name,food_name:x.food_name,catalog_id:effectiveCatalog.find(f=>foodNameKey(f.name)===foodNameKey(x.food_name))?.id||null,quantity_g:extractQuantity(x.portion_text),portion_text:x.portion_text||"",calories:String(x.calories),protein:String(x.protein_g),carbs:String(x.carbs_g),fat:String(x.fat_g)})):[createMealDraft(globalThis.crypto.randomUUID())]);setShowForm(true);window.scrollTo({top:0,behavior:"smooth"})}
  async function saveCatalog(item:MealDraftItem){const q=Number(item.quantity_g);if(!item.food_name.trim()||!Number.isFinite(q)||q<=0)return setMessage("Kataloğa kaydetmek için besin adı ve miktar zorunludur.");const factor=100/q;const {data:user}=await supabase.auth.getUser();const {error}=await supabase.from("food_catalog").upsert({clinic_id:clinicId,name:item.food_name.trim(),name_key:foodNameKey(item.food_name),calories_per_100g:roundNutrition((Number(item.calories)||0)*factor),protein_per_100g:roundNutrition((Number(item.protein)||0)*factor),carbs_per_100g:roundNutrition((Number(item.carbs)||0)*factor),fat_per_100g:roundNutrition((Number(item.fat)||0)*factor),default_portion_g:q,source_label:"Klinik tarafından doğrulandı",is_active:true,created_by:user.user?.id,updated_at:new Date().toISOString()},{onConflict:"clinic_id,name_key"});if(error)setMessage(error.message);else{setMessage("Besin klinik kataloğuna kaydedildi.");await load()}}
  async function savePlan(){if(!form.client_id||!form.starts_on||!form.ends_on)return setMessage("Danışan ve tarihler zorunludur.");const valid=draft.filter(x=>x.food_name.trim());if(!valid.length)return setMessage("En az bir besin ekleyin.");const conflicts=selectedClient?valid.flatMap(x=>foodWarnings(x.food_name,selectedClient).allergies.map(a=>`${x.food_name} → ${a}`)):[];if(conflicts.length&&!window.confirm(`Alerji uyarısı var:\n\n${conflicts.join("\n")}\n\nYine de kaydedilsin mi?`))return;const {error}=await supabase.rpc("save_meal_plan_v2",{p_plan_id:editingId,p_client_id:form.client_id,p_title:form.title||"Beslenme Planı",p_starts_on:form.starts_on,p_ends_on:form.ends_on,p_target_calories:form.calories?Number(form.calories):roundNutrition(totals.calories),p_target_protein_g:form.protein?Number(form.protein):roundNutrition(totals.protein),p_target_carbs_g:form.carbs?Number(form.carbs):roundNutrition(totals.carbs),p_target_fat_g:form.fat?Number(form.fat):roundNutrition(totals.fat),p_note:form.note||null,p_items:valid.map((x,index)=>({meal_name:x.meal_name,food_name:x.food_name.trim(),portion_text:x.portion_text||(x.quantity_g?`${x.quantity_g} g/ml`:null),calories:Number(x.calories)||0,protein_g:Number(x.protein)||0,carbs_g:Number(x.carbs)||0,fat_g:Number(x.fat)||0,sort_order:index}))});if(error)setMessage(error.message);else{setMessage(editingId?"Menü planı güncellendi.":"Menü planı oluşturuldu.");setShowForm(false);reset(form.client_id);await load()}}
  async function deletePlan(plan:MealPlanRow){if(!window.confirm(`“${plan.title}” kalıcı olarak silinsin mi?`))return;const {error}=await supabase.from("meal_plans").delete().eq("id",plan.id);if(error)setMessage(error.message);else{setMessage("Plan silindi.");await load()}}
  async function toggle(item:MealItemRow){if(staff)return;const today=localDateKey(new Date());if(item.completed)await supabase.from("meal_completions").delete().eq("item_id",item.id).eq("consumed_on",today);else{const {data:user}=await supabase.auth.getUser();const {data:cp}=await supabase.from("client_profiles").select("id").eq("user_id",user.user?.id||"").eq("is_active",true).single();await supabase.from("meal_completions").insert({item_id:item.id,client_id:cp?.id,consumed_on:today})}await load()}
  async function uploadMealPhoto(plan:MealPlanRow,mealName:string,file:File|null){if(staff||!file)return;if(!["image/jpeg","image/png","image/webp"].includes(file.type))return setMessage("Yalnızca JPG, PNG veya WEBP yükleyebilirsiniz.");if(file.size>5*1024*1024)return setMessage("Öğün fotoğrafı en fazla 5 MB olabilir.");const key=`${plan.id}:${mealName}`;setUploadingKey(key);const {data:user}=await supabase.auth.getUser();if(!user.user){setUploadingKey("");return}const {data:client}=await supabase.from("client_profiles").select("id").eq("user_id",user.user.id).eq("is_active",true).single();if(!client){setMessage("Danışan profili bulunamadı.");setUploadingKey("");return}const ext=file.name.split(".").pop()?.toLowerCase()||"jpg";const safeMeal=foodNameKey(mealName).replace(/\s+/g,"-")||"meal";const path=`${user.user.id}/${plan.id}/${localDateKey(new Date())}-${safeMeal}-${globalThis.crypto.randomUUID()}.${ext}`;const {error:uploadError}=await supabase.storage.from("meal-photos").upload(path,file,{contentType:file.type,upsert:false});if(uploadError){setMessage(uploadError.message);setUploadingKey("");return}const existing=photos.find(x=>x.meal_plan_id===plan.id&&x.meal_name===mealName&&x.consumed_on===localDateKey(new Date()));const payload={clinic_id:clinicId,client_id:client.id,meal_plan_id:plan.id,meal_name:mealName,consumed_on:localDateKey(new Date()),photo_path:path,caption:null,updated_at:new Date().toISOString()};const result=existing?await supabase.from("meal_photos").update(payload).eq("id",existing.id):await supabase.from("meal_photos").insert(payload);if(result.error)setMessage(result.error.message);else{if(existing?.photo_path)await supabase.storage.from("meal-photos").remove([existing.photo_path]);setMessage(`${mealName} fotoğrafı yüklendi.`);await load()}setUploadingKey("")}
  function wordExport(plan:MealPlanRow){const its=items[plan.id]||[];const html=`<html><body><h1>${escapeHtml(plan.title)}</h1><p>${plan.starts_on} - ${plan.ends_on}</p><table border="1" cellpadding="8"><tr><th>Öğün</th><th>Besin</th><th>Porsiyon</th><th>kcal</th><th>Protein</th><th>Karb.</th><th>Yağ</th></tr>${its.map(i=>`<tr><td>${escapeHtml(i.meal_name)}</td><td>${escapeHtml(i.food_name)}</td><td>${escapeHtml(i.portion_text||"")}</td><td>${i.calories}</td><td>${i.protein_g}</td><td>${i.carbs_g}</td><td>${i.fat_g}</td></tr>`).join("")}</table><p>${escapeHtml(plan.dietitian_note||"")}</p></body></html>`;downloadBlob(html,`${plan.title}.doc`,`application/msword`)}

  return <><PageHeader title="Menü Planları" description={staff?"Kişiye özel menüleri oluşturun, düzenleyin; serbest besin yazın ve danışanın alerji/tercih uyarılarını anında görün.":"Öğünlerinizi tamamlayın ve Kahvaltı, Ara Öğün veya Akşam Yemeği bölümüne fotoğraf ekleyin."} action={staff?<button className="primary-button compact" onClick={()=>{reset();setShowForm(true)}}><Plus size={15}/>Yeni plan</button>:undefined}/>{message&&<div className="notice-bar"><AlertTriangle size={17}/>{message}<button onClick={()=>setMessage("")}><X size={15}/></button></div>}
    {showForm&&staff&&<section className="surface-card menu-editor-v3"><div className="surface-head"><div><span className="section-kicker">{editingId?"PLANI DÜZENLE":"YENİ MENÜ"}</span><h3>{editingId?"Mevcut menü planını güncelle":"Danışana özel menü oluştur"}</h3><p>Öğün türü, besin, porsiyon ve makro değerleri tek ekranda.</p></div><button className="drawer-close" onClick={()=>{setShowForm(false);reset()}}><X size={18}/></button></div>
      <div className="form-grid"><label>Danışan<select value={form.client_id} onChange={e=>setForm({...form,client_id:e.target.value})}><option value="">Danışan seçin</option>{clients.map(c=><option key={c.id} value={c.id}>{c.full_name} • {c.member_no}</option>)}</select></label><label>Plan adı<input value={form.title} onChange={e=>setForm({...form,title:e.target.value})}/></label><label>Başlangıç<input type="date" value={form.starts_on} onChange={e=>setForm({...form,starts_on:e.target.value})}/></label><label>Bitiş<input type="date" value={form.ends_on} onChange={e=>setForm({...form,ends_on:e.target.value})}/></label><label className="wide">Diyetisyen notu<textarea rows={3} value={form.note} onChange={e=>setForm({...form,note:e.target.value})}/></label></div>
      {selectedClient&&<div className="client-warning-banner"><TriangleAlert size={20}/><div><b>{selectedClient.full_name} için uyarılar</b><p><strong>Alerjiler:</strong> {selectedClient.allergies?.length?selectedClient.allergies.join(", "):"Bildirilmedi"}</p><p><strong>Kullanmadığı besinler:</strong> {selectedClient.disliked_foods?.length?selectedClient.disliked_foods.join(", "):"Bildirilmedi"}</p></div></div>}
      <div className="menu-total-v3"><span>Menü toplamı</span><b>{roundNutrition(totals.calories)} kcal</b><b>P {roundNutrition(totals.protein)} g</b><b>K {roundNutrition(totals.carbs)} g</b><b>Y {roundNutrition(totals.fat)} g</b><button className="secondary-button compact" onClick={()=>setForm({...form,calories:String(roundNutrition(totals.calories)),protein:String(roundNutrition(totals.protein)),carbs:String(roundNutrition(totals.carbs)),fat:String(roundNutrition(totals.fat))})}><RefreshCw size={14}/>Hedefe uygula</button></div>
      <details className="optional-targets"><summary>Kalori ve makro hedeflerini elle düzenle</summary><div className="compact-form-grid four-cols"><label>Kalori<input type="number" value={form.calories} onChange={e=>setForm({...form,calories:e.target.value})}/></label><label>Protein<input type="number" value={form.protein} onChange={e=>setForm({...form,protein:e.target.value})}/></label><label>Karbonhidrat<input type="number" value={form.carbs} onChange={e=>setForm({...form,carbs:e.target.value})}/></label><label>Yağ<input type="number" value={form.fat} onChange={e=>setForm({...form,fat:e.target.value})}/></label></div></details>
      <div className="menu-builder-head"><div><h3>Öğün satırları</h3><p>Katalog isteğe bağlıdır; istediğiniz yemeği serbestçe yazabilirsiniz.</p></div><button className="secondary-button compact" onClick={()=>setDraft(x=>[...x,createMealDraft(globalThis.crypto.randomUUID())])}><Plus size={14}/>Besin ekle</button></div>
      <div className="menu-builder-v3">{draft.map((item,index)=>{const warning=selectedClient?foodWarnings(item.food_name,selectedClient):{allergies:[],disliked:[]};return <article key={item.key}><div className="menu-row-index">{index+1}</div><div className="menu-row-grid"><label>Öğün<select value={item.meal_name} onChange={e=>updateItem(item.key,{meal_name:e.target.value})}>{mealTypes.map(x=><option key={x}>{x}</option>)}</select></label><label>Katalog <span>isteğe bağlı</span><select value={item.catalog_id||""} onChange={e=>selectCatalog(item.key,e.target.value)}><option value="">Serbest yazacağım</option>{effectiveCatalog.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select></label><label className="wide">Besin / yemek adı<input value={item.food_name} onChange={e=>changeName(item.key,e.target.value)} placeholder="Örn. Ev yapımı tavuklu bowl"/></label><label>Miktar (g/ml)<input type="number" value={item.quantity_g} onChange={e=>changeQuantity(item.key,e.target.value)}/></label><label>Porsiyon<input value={item.portion_text} onChange={e=>updateItem(item.key,{portion_text:e.target.value})} placeholder="1 kase, 2 adet..."/></label>{warning.allergies.length>0&&<div className="food-conflict allergy"><TriangleAlert size={15}/><b>Alerji:</b> {warning.allergies.join(", ")}</div>}{warning.disliked.length>0&&<div className="food-conflict disliked"><TriangleAlert size={15}/><b>Danışan kullanmıyor:</b> {warning.disliked.join(", ")}</div>}<div className="macro-editor-row"><label>kcal<input type="number" value={item.calories} onChange={e=>updateItem(item.key,{calories:e.target.value})}/></label><label>Protein<input type="number" value={item.protein} onChange={e=>updateItem(item.key,{protein:e.target.value})}/></label><label>Karb.<input type="number" value={item.carbs} onChange={e=>updateItem(item.key,{carbs:e.target.value})}/></label><label>Yağ<input type="number" value={item.fat} onChange={e=>updateItem(item.key,{fat:e.target.value})}/></label><button onClick={()=>saveCatalog(item)}><Save size={13}/>Kataloğa kaydet</button></div></div><button className="icon-danger" onClick={()=>setDraft(current=>current.length===1?[createMealDraft(globalThis.crypto.randomUUID())]:current.filter(x=>x.key!==item.key))}><Trash2 size={16}/></button></article>})}</div>
      <div className="form-actions"><button className="secondary-button" onClick={()=>{setShowForm(false);reset()}}>Vazgeç</button><button className="primary-button compact" onClick={savePlan}><Save size={15}/>{editingId?"Değişiklikleri kaydet":"Planı oluştur"}</button></div>
    </section>}
    {loading ? (
      <Loading />
    ) : (
      <div className="plan-list-v3">
        {plans.length === 0 ? (
          <Empty text="Menü planı bulunmuyor." />
        ) : (
          plans.map((plan) => {
            const planItems = items[plan.id] || [];
            const grouped = mealTypes.reduce<Array<[string, MealItemRow[]]>>((acc, meal) => {
              const rows = planItems.filter((item) => item.meal_name === meal);
              if (rows.length) acc.push([meal, rows]);
              return acc;
            }, []);

            planItems
              .filter((item) => !mealTypes.includes(item.meal_name))
              .forEach((item) => {
                const existing = grouped.find(([meal]) => meal === item.meal_name);
                if (existing) existing[1].push(item);
                else grouped.push([item.meal_name, [item]]);
              });

            return (
              <article className="plan-card-v3" key={plan.id}>
                <header>
                  <div>
                    <span>{plan.client_name}</span>
                    <h3>{plan.title}</h3>
                    <p>{shortDate(plan.starts_on)} — {shortDate(plan.ends_on)}</p>
                  </div>
                  <div className="plan-actions">
                    <button type="button" onClick={() => window.print()}>
                      <Download size={14} />PDF
                    </button>
                    <button type="button" onClick={() => wordExport(plan)}>
                      <FileText size={14} />Word
                    </button>
                    {staff && (
                      <button type="button" onClick={() => startEdit(plan)}>
                        <Pencil size={14} />Edit
                      </button>
                    )}
                    {staff && (
                      <button type="button" className="danger-action" onClick={() => deletePlan(plan)}>
                        <Trash2 size={14} />Sil
                      </button>
                    )}
                  </div>
                </header>

                <div className="macro-row-v3">
                  <span><b>{plan.target_calories || 0}</b> kcal</span>
                  <span><b>{plan.target_protein_g || 0} g</b> protein</span>
                  <span><b>{plan.target_carbs_g || 0} g</b> karb.</span>
                  <span><b>{plan.target_fat_g || 0} g</b> yağ</span>
                </div>

                <div className="meal-groups-v3">
                  {grouped.map(([meal, rows]) => {
                    const photo = photos.find(
                      (entry) => entry.meal_plan_id === plan.id && entry.meal_name === meal,
                    );
                    const uploadKey = `${plan.id}:${meal}`;

                    return (
                      <section key={meal} className="meal-group-card">
                        <div className="meal-group-head">
                          <div>
                            <span>{meal}</span>
                            <small>{rows.filter((item) => item.completed).length}/{rows.length} tamamlandı</small>
                          </div>
                          {!staff && (
                            <label className="photo-upload-button">
                              <input
                                type="file"
                                accept="image/jpeg,image/png,image/webp"
                                onChange={(event) => {
                                  void uploadMealPhoto(plan, meal, event.target.files?.[0] || null);
                                  event.currentTarget.value = "";
                                }}
                              />
                              <Camera size={15} />
                              {uploadingKey === uploadKey
                                ? "Yükleniyor..."
                                : photo
                                  ? "Fotoğrafı değiştir"
                                  : "Fotoğraf ekle"}
                            </label>
                          )}
                        </div>

                        {photo?.signed_url && (
                          <div className="meal-photo-preview">
                            
                            <img src={photo.signed_url} alt={`${meal} öğün fotoğrafı`} />
                            <span>{shortDate(photo.consumed_on)}</span>
                          </div>
                        )}

                        <div className="meal-item-list-v3">
                          {rows.map((item) => (
                            <button
                              type="button"
                              key={item.id}
                              disabled={staff}
                              className={item.completed ? "done" : ""}
                              onClick={() => toggle(item)}
                            >
                              <span className="check-box">{item.completed && <Check size={13} />}</span>
                              <div>
                                <b>{item.food_name}</b>
                                <p>
                                  {item.portion_text || "Porsiyon belirtilmedi"} • {item.calories} kcal • P {item.protein_g}g • K {item.carbs_g}g • Y {item.fat_g}g
                                </p>
                              </div>
                            </button>
                          ))}
                        </div>
                      </section>
                    );
                  })}
                </div>

                {plan.dietitian_note && (
                  <div className="plan-note-v3">
                    <ClipboardList size={16} />
                    <span>{plan.dietitian_note}</span>
                  </div>
                )}
              </article>
            );
          })
        )}
      </div>
    )}
  </>;
}

export function CommunityV3({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);const [posts,setPosts]=useState<CommunityPost[]>([]);const [dietitians,setDietitians]=useState<DietitianRow[]>([]);const [groupId,setGroupId]=useState("");const [content,setContent]=useState("");const [file,setFile]=useState<File|null>(null);const [preview,setPreview]=useState("");const [loading,setLoading]=useState(true);const [posting,setPosting]=useState(false);const [message,setMessage]=useState("");const [comments,setComments]=useState<Record<string,string>>({});const fileRef=useRef<HTMLInputElement|null>(null);
  const loadDietitians=useCallback(async()=>{if(role!=="owner")return;const {data:d}=await supabase.from("dietitian_profiles").select("id,user_id,title,appointment_duration_minutes,buffer_minutes,is_bookable").eq("clinic_id",clinicId);const ds=(d||[]) as Omit<DietitianRow,"full_name">[];const ids=ds.map(x=>x.user_id);const {data:p}=ids.length?await supabase.from("profiles").select("id,full_name").in("id",ids):{data:[]};const map=new Map((p||[]).map((x:any)=>[x.id,x.full_name]));const full=ds.map(x=>({...x,full_name:map.get(x.user_id)||"Diyetisyen"})) as DietitianRow[];setDietitians(full);setGroupId(current=>full.some(x=>x.id===current)?current:(full[0]?.id||""))},[clinicId,role,supabase]);
  const load=useCallback(async()=>{setLoading(true);const {data,error}=await supabase.rpc("get_community_feed_v3",{p_dietitian_id:role==="owner"?(groupId||null):null});if(error){setMessage(error.message);setPosts([]);}else{const raw=(data||[]) as CommunityPost[];const signed=await Promise.all(raw.map(async post=>{if(!post.media_path)return post;const {data:url}=await supabase.storage.from("community-media").createSignedUrl(post.media_path,3600);return{...post,signed_url:url?.signedUrl}}));setPosts(signed)}setLoading(false)},[groupId,role,supabase]);
  useEffect(()=>{void loadDietitians()},[loadDietitians]);useEffect(()=>{if(role!=="owner"||groupId)void load()},[groupId,load,role]);
  useEffect(()=>()=>{if(preview)URL.revokeObjectURL(preview)},[preview]);
  function chooseFile(next:File|null){if(preview)URL.revokeObjectURL(preview);if(!next){setFile(null);setPreview("");return}if(!["image/jpeg","image/png","image/webp"].includes(next.type)){setMessage("Yalnızca JPG, PNG veya WEBP yükleyebilirsiniz.");return}if(next.size>8*1024*1024){setMessage("Topluluk görseli en fazla 8 MB olabilir.");return}setFile(next);setPreview(URL.createObjectURL(next))}
  async function createPost(){if(!content.trim()&&!file)return setMessage("Metin veya görsel ekleyin.");setPosting(true);setMessage("");let mediaPath:string|null=null;if(file){const {data:user}=await supabase.auth.getUser();if(!user.user){setPosting(false);return}const ext=file.name.split(".").pop()?.toLowerCase()||"jpg";mediaPath=`${user.user.id}/${globalThis.crypto.randomUUID()}.${ext}`;const {error:uploadError}=await supabase.storage.from("community-media").upload(mediaPath,file,{contentType:file.type});if(uploadError){setMessage(uploadError.message);setPosting(false);return}}const {error}=await supabase.rpc("create_community_post_v3",{p_content:content.trim()||null,p_media_path:mediaPath,p_dietitian_id:role==="owner"?(groupId||null):null});if(error){if(mediaPath)await supabase.storage.from("community-media").remove([mediaPath]);setMessage(error.message)}else{setContent("");chooseFile(null);setMessage("Paylaşım yayınlandı.");await load()}setPosting(false)}
  async function addComment(postId:string){const value=(comments[postId]||"").trim();if(!value)return;const {error}=await supabase.rpc("create_community_comment_v3",{p_post_id:postId,p_content:value});if(error)setMessage(error.message);else{setComments(current=>({...current,[postId]:""}));await load()}}
  return <><PageHeader title="Topluluk" description="Aynı diyetisyene bağlı danışanların yalnızca kendi gruplarında paylaşım ve öğün fotoğrafı görebildiği mini topluluk alanı." action={role==="owner"?<label className="community-group-picker">Grup<select value={groupId} onChange={e=>setGroupId(e.target.value)}>{dietitians.map(d=><option key={d.id} value={d.id}>{d.full_name}</option>)}</select></label>:undefined}/>{message&&<div className="notice-bar"><AlertTriangle size={17}/>{message}</div>}
    <div className="community-layout"><section className="surface-card composer-card"><div className="composer-head"><span className="avatar">NC</span><div><b>Grubunla paylaş</b><p>Motivasyon, öğün fotoğrafı veya kısa mesaj.</p></div></div><textarea rows={4} value={content} onChange={e=>setContent(e.target.value)} placeholder="Bugün nasıl gidiyor? Grubunuzla paylaşın..."/>{preview&&<div className="composer-preview"><img src={preview} alt="Paylaşılacak görsel önizlemesi"/><button onClick={()=>chooseFile(null)}><X size={16}/></button></div>}<div className="composer-actions"><input ref={fileRef} hidden type="file" accept="image/jpeg,image/png,image/webp" onChange={e=>chooseFile(e.target.files?.[0]||null)}/><button className="secondary-button compact" onClick={()=>fileRef.current?.click()}><ImagePlus size={15}/>Fotoğraf</button><button className="primary-button compact" disabled={posting} onClick={createPost}><Send size={15}/>{posting?"Yayınlanıyor...":"Paylaş"}</button></div><div className="privacy-note"><ShieldCheck size={15}/><span>Paylaşımlar yalnızca aynı sorumlu diyetisyene bağlı danışanlar ve ilgili diyetisyen tarafından görülür.</span></div></section>
      <section className="community-feed">{loading?<Loading/>:posts.length===0?<div className="surface-card"><Empty text="Bu grupta henüz paylaşım yok."/></div>:posts.map(post=><article className="community-post" key={post.id}><header><span className="avatar">{initials(post.author_name)}</span><div><b>{post.author_name}</b><small>{roleText(post.author_role)} • {dateTime(post.created_at)}</small></div></header>{post.content&&<p className="post-content">{post.content}</p>}{post.signed_url&&<><img className="post-image" src={post.signed_url} alt="Topluluk paylaşım görseli"/></>}<div className="post-meta"><span><MessageCircle size={14}/>{post.comments?.length||0} yorum</span></div>{post.comments?.length>0&&<div className="comment-list">{post.comments.map(comment=><div key={comment.id}><span className="avatar tiny">{initials(comment.author_name)}</span><p><b>{comment.author_name}</b> {comment.content}<small>{dateTime(comment.created_at)}</small></p></div>)}</div>}<div className="comment-box"><input value={comments[post.id]||""} onChange={e=>setComments(current=>({...current,[post.id]:e.target.value}))} onKeyDown={e=>{if(e.key==="Enter")void addComment(post.id)}} placeholder="Yorum yaz..."/><button onClick={()=>addComment(post.id)}><Send size={15}/></button></div></article>)}</section>
    </div>
  </>;
}
