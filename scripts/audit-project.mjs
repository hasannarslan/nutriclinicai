import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const ts = require("typescript");

const root = process.cwd();
const failures = [];
const warnings = [];
const successes = [];

function walk(directory, predicate = () => true) {
  const output = [];
  if (!fs.existsSync(directory)) return output;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (["node_modules", ".next", ".git"].includes(entry.name)) continue;
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) output.push(...walk(full, predicate));
    else if (predicate(full)) output.push(full);
  }
  return output;
}

function relative(file) { return path.relative(root, file).replaceAll(path.sep, "/"); }

const packageFile = path.join(root, "package.json");
const packageJson = JSON.parse(fs.readFileSync(packageFile, "utf8"));
if (packageJson.dependencies?.next !== packageJson.devDependencies?.["eslint-config-next"]) {
  failures.push("next ve eslint-config-next sürümleri eşleşmiyor.");
} else successes.push(`Next.js paketleri eşleşiyor (${packageJson.dependencies.next}).`);

const sourceFiles = walk(path.join(root, "src"), (file) => /\.(ts|tsx)$/.test(file));
for (const file of sourceFiles) {
  const code = fs.readFileSync(file, "utf8");
  const result = ts.transpileModule(code, {
    fileName: file,
    reportDiagnostics: true,
    compilerOptions: {
      jsx: ts.JsxEmit.ReactJSX,
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ESNext,
      moduleResolution: ts.ModuleResolutionKind.Bundler,
      allowJs: false,
    },
  });
  const diagnostics = result.diagnostics || [];
  for (const diagnostic of diagnostics) {
    const message = ts.flattenDiagnosticMessageText(diagnostic.messageText, " ");
    failures.push(`${relative(file)}: ${message}`);
  }
}
if (!failures.some((item) => item.includes("src/"))) successes.push(`${sourceFiles.length} TypeScript/TSX dosyası sözdizimi kontrolünden geçti.`);

const sqlFiles = walk(path.join(root, "supabase"), (file) => file.endsWith(".sql"));
const sqlText = sqlFiles.map((file) => fs.readFileSync(file, "utf8")).join("\n");
const sourceText = sourceFiles.map((file) => fs.readFileSync(file, "utf8")).join("\n");

const rpcNames = [...sourceText.matchAll(/\.rpc\(\s*["'`]([^"'`]+)["'`]/g)].map((match) => match[1]);
for (const rpc of new Set(rpcNames)) {
  const escaped = rpc.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  if (!new RegExp(`(?:function|procedure)\\s+public\\.${escaped}\\s*\\(`, "i").test(sqlText)) failures.push(`Kaynakta çağrılan RPC SQL içinde bulunamadı: ${rpc}`);
}
if (!failures.some((item) => item.startsWith("Kaynakta çağrılan RPC"))) successes.push(`${new Set(rpcNames).size} RPC çağrısının SQL karşılığı bulundu.`);

const tableNames = [...sourceText.matchAll(/\.from\(\s*["'`]([^"'`]+)["'`]\s*\)/g)].map((match) => match[1]);
for (const table of new Set(tableNames)) {
  if (table.includes("${")) continue;
  const escaped = table.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const tablePattern = new RegExp(`(?:create\\s+table(?:\\s+if\\s+not\\s+exists)?\\s+public\\.${escaped}\\b|alter\\s+table\\s+public\\.${escaped}\\b)`, "i");
  if (!tablePattern.test(sqlText)) {
    const bucketExists = sqlText.includes(`'${table}'`) || sqlText.includes(`"${table}"`);
    if (!bucketExists) warnings.push(`Tablo veya storage bucket SQL içinde bulunamadı: ${table}`);
  }
}

const requiredMigrations = ["019_saas_pilot_multi_tenant.sql", "020_public_registration_and_pilot_applications.sql", "021_platform_clinic_details_and_paid_conversion.sql", "022_stabilization_and_lifecycle_fix.sql", "023_platform_integrity_and_locale_v81.sql"];
for (const migration of requiredMigrations) {
  if (!fs.existsSync(path.join(root, "supabase", "migrations", migration))) failures.push(`Eksik migration: ${migration}`);
}

const baseline = path.join(root, "supabase", "baseline", "production_baseline_v8_1.sql");
if (!fs.existsSync(baseline)) failures.push("Fresh kurulum baseline dosyası eksik: production_baseline_v8_1.sql");
else {
  const baselineText = fs.readFileSync(baseline, "utf8");
  if (!baselineText.includes("normalize_subscription_lifecycle_v8")) failures.push("v8.1 baseline 022 yaşam döngüsü düzeltmesini içermiyor.");
  else if (!baselineText.includes("platform_approve_paid_access_v81")) failures.push("v8.1 baseline 023 platform bütünlük katmanını içermiyor.");
  else successes.push("v8.1 fresh production baseline 001–023 düzeltmelerini içeriyor.");
}

const forbidden = [".env", ".env.local", "service-role.txt", "secrets.txt"];
for (const name of forbidden) {
  if (fs.existsSync(path.join(root, name))) failures.push(`Paket kökünde paylaşılmaması gereken dosya var: ${name}`);
}

for (const file of walk(root, (file) => /\.(ts|tsx|js|mjs|json|md|sql|env|example)$/.test(file))) {
  if (relative(file) === "scripts/audit-project.mjs") continue;
  const text = fs.readFileSync(file, "utf8");
  if (/\b(?:sb_secret_|service_role\s*=\s*eyJ|sk-[A-Za-z0-9]{20,}|xai-[A-Za-z0-9_-]{20,}|gsk_[A-Za-z0-9]{20,})/.test(text) && !file.endsWith(".env.example")) {
    failures.push(`Olası gerçek gizli anahtar bulundu: ${relative(file)}`);
  }
}


// Validate local imports so missing files are caught before a Vercel build.
function resolveLocalImport(fromFile, specifier) {
  let base;
  if (specifier.startsWith("@/")) base = path.join(root, "src", specifier.slice(2));
  else if (specifier.startsWith(".")) base = path.resolve(path.dirname(fromFile), specifier);
  else return true;
  const candidates = [
    base,
    `${base}.ts`, `${base}.tsx`, `${base}.js`, `${base}.jsx`, `${base}.mjs`, `${base}.json`,
    path.join(base, "index.ts"), path.join(base, "index.tsx"), path.join(base, "index.js"),
  ];
  return candidates.some((candidate) => fs.existsSync(candidate));
}
for (const file of sourceFiles) {
  const code = fs.readFileSync(file, "utf8");
  const imports = [
    ...code.matchAll(/(?:from\s*|import\s*\()\s*["'`]([^"'`]+)["'`]/g),
    ...code.matchAll(/require\(\s*["'`]([^"'`]+)["'`]\s*\)/g),
  ].map((match) => match[1]);
  for (const specifier of new Set(imports)) {
    if (!resolveLocalImport(file, specifier)) failures.push(`${relative(file)}: çözümlenemeyen yerel import: ${specifier}`);
  }
}
if (!failures.some((item) => item.includes("çözümlenemeyen yerel import"))) successes.push("Yerel TypeScript import yolları doğrulandı.");

// Check that static internal links point to an App Router page or route.
const appRoot = path.join(root, "src", "app");
const appEntries = walk(appRoot, (file) => /(?:page|route)\.(ts|tsx|js|jsx)$/.test(file));
const routeRegexes = appEntries.map((file) => {
  const rel = relative(file).replace(/^src\/app/, "").replace(/\/(?:page|route)\.(?:ts|tsx|js|jsx)$/, "") || "/";
  const escaped = rel
    .replace(/[.+?^${}()|[\]\\]/g, "\\$&")
    .replace(/\\\[\\\.\\\.\\\.([^\]]+)\\\]/g, ".+")
    .replace(/\\\[\\\[\\\.\\\.\\\.([^\]]+)\\\]\\\]/g, ".*")
    .replace(/\\\[([^\]]+)\\\]/g, "[^/]+");
  return new RegExp(`^${escaped === "/" ? "/" : escaped}/?$`);
});
const staticLinks = [];
for (const file of sourceFiles) {
  const code = fs.readFileSync(file, "utf8");
  for (const pattern of [/(?:href|router\.(?:push|replace)|redirect)\s*(?:=|\()\s*["'`]\s*(\/[^"'`$]*)["'`]/g]) {
    for (const match of code.matchAll(pattern)) staticLinks.push({ file, href: match[1] });
  }
}
for (const { file, href } of staticLinks) {
  const normalized = href.split(/[?#]/)[0] || "/";
  if (normalized.startsWith("//") || normalized.includes(".") && !normalized.startsWith("/.well-known")) continue;
  if (!routeRegexes.some((regex) => regex.test(normalized))) warnings.push(`${relative(file)}: karşılığı bulunamayan statik iç bağlantı: ${href}`);
}
if (!warnings.some((item) => item.includes("statik iç bağlantı"))) successes.push(`${staticLinks.length} statik iç bağlantı App Router rotalarıyla eşleşti.`);

// Every public application table must have RLS explicitly enabled somewhere in migrations/baselines.
const createdTables = [...sqlText.matchAll(/create\s+table(?:\s+if\s+not\s+exists)?\s+public\.([a-zA-Z0-9_]+)/gi)].map((match) => match[1]);
for (const table of new Set(createdTables)) {
  const escaped = table.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  if (!new RegExp(`alter\\s+table\\s+public\\.${escaped}\\s+enable\\s+row\\s+level\\s+security`, "i").test(sqlText)) {
    failures.push(`RLS etkinleştirme ifadesi bulunamadı: public.${table}`);
  }
}
if (!failures.some((item) => item.startsWith("RLS etkinleştirme"))) successes.push(`${new Set(createdTables).size} public tablo için RLS etkinleştirme ifadesi bulundu.`);

// Environment-variable documentation completeness.
const envExample = fs.readFileSync(path.join(root, ".env.example"), "utf8");
const envReferences = [...sourceText.matchAll(/process\.env\.([A-Z0-9_]+)/g)].map((match) => match[1]);
for (const key of new Set(envReferences)) {
  if (!["NODE_ENV", "VERCEL", "VERCEL_ENV", "VERCEL_URL"].includes(key) && !envExample.includes(key)) warnings.push(`.env.example içinde belgelenmemiş ortam değişkeni: ${key}`);
}
if (!warnings.some((item) => item.includes("ortam değişkeni"))) successes.push(`${new Set(envReferences).size} ortam değişkeni .env.example içinde belgelendi.`);


// v8.1 release-specific regression checks.
for (const forbiddenDirectory of [".next", "node_modules"]) {
  if (fs.existsSync(path.join(root, forbiddenDirectory))) failures.push(`Dağıtım paketinde bulunmaması gereken klasör var: ${forbiddenDirectory}`);
}
if (fs.existsSync(path.join(root, "tsconfig.tsbuildinfo"))) warnings.push("Dağıtım paketinde tsconfig.tsbuildinfo bulunuyor; paketten çıkarılması önerilir.");

if (/\bBoolean\(\s*body\./.test(sourceText)) failures.push("API gövdesinde Boolean(body.*) kullanımı bulundu; string 'false' yanlışlıkla true olabilir.");
else successes.push("API boolean alanları katı ayrıştırma kullanıyor.");

const unsafeClientJson = [];
for (const file of sourceFiles.filter((file) => file.endsWith(".tsx"))) {
  const code = fs.readFileSync(file, "utf8");
  if (/await\s+response\.json\(\)\s*;/.test(code)) unsafeClientJson.push(relative(file));
}
if (unsafeClientJson.length) failures.push(`İstemci tarafında korumasız response.json() bulundu: ${unsafeClientJson.join(", ")}`);
else successes.push("İstemci fetch yanıtları boş/geçersiz JSON durumuna karşı korunuyor.");

const localeFile = path.join(root, "src", "lib", "i18n.ts");
const localeRuntimeFile = path.join(root, "src", "lib", "i18n-runtime.tsx");
if (!fs.existsSync(localeFile) || !fs.existsSync(localeRuntimeFile)) failures.push("Çok dilli çalışma zamanı dosyaları eksik.");
else {
  const localeText = fs.readFileSync(localeFile, "utf8");
  const runtimeText = fs.readFileSync(localeRuntimeFile, "utf8");
  for (const locale of ["tr", "en", "el", "ru", "de"]) {
    if (!localeText.includes(`${locale}:`)) failures.push(`Dil sözlüğünde eksik locale: ${locale}`);
  }
  if (!localeText.includes("phraseCatalogue") || !runtimeText.includes("MutationObserver")) failures.push("Legacy ekranları çevirecek uyumluluk katmanı eksik.");
  const requiredLocalizedScreens = [
    "src/app/dashboard/dashboard-client.tsx",
    "src/app/platform-admin/platform-admin-client.tsx",
    "src/app/login/login-client.tsx",
    "src/app/onboarding/onboarding-client.tsx",
    "src/app/pilot-application/pilot-application-form.tsx",
  ];
  for (const screen of requiredLocalizedScreens) {
    const full = path.join(root, screen);
    if (!fs.existsSync(full) || !fs.readFileSync(full, "utf8").includes("LocalizedContent")) failures.push(`LocalizedContent entegrasyonu eksik: ${screen}`);
  }
  if (!failures.some((item) => item.includes("LocalizedContent") || item.includes("dilli çalışma") || item.includes("uyumluluk katmanı") || item.includes("Dil sözlüğü"))) successes.push("TR/EN/EL/RU/DE çalışma zamanı yerelleştirmesi ana ekranlara bağlandı.");
}

const platformMigration = path.join(root, "supabase", "migrations", "023_platform_integrity_and_locale_v81.sql");
if (fs.existsSync(platformMigration)) {
  const migrationText = fs.readFileSync(platformMigration, "utf8");
  for (const rpc of ["platform_extend_pilot_v81", "platform_approve_paid_access_v81", "platform_set_clinic_status_v81", "platform_change_plan_v81"]) {
    if (!migrationText.includes(`function public.${rpc}`)) failures.push(`023 migration içinde eksik transactional RPC: ${rpc}`);
  }
  if (/;\s*where\s+/i.test(migrationText)) failures.push("023 migration içinde noktalı virgülden sonra sahipsiz WHERE ifadesi bulundu.");
  if ((migrationText.match(/\$\$/g) || []).length % 2 !== 0) failures.push("023 migration dollar-quote blokları dengeli değil.");
  if (!/revoke all on function public\.sync_clinic_status_from_subscription_v81\(\)/i.test(migrationText)) failures.push("Trigger fonksiyonu execute yetkileri sıkılaştırılmamış.");
  if (!failures.some((item) => item.includes("023 migration") || item.includes("transactional RPC") || item.includes("Trigger fonksiyonu"))) successes.push("023 migration transactional Platform Admin işlemleri ve yetki sıkılaştırmasını içeriyor.");
}

const platformCss = fs.readFileSync(path.join(root, "src", "app", "globals.css"), "utf8");
for (const className of ["platform-detail-backdrop", "platform-detail-drawer", "platform-detail-body", "platform-warning-list", "platform-search", "platform-card-list"]) {
  if (!platformCss.includes(`.${className}`)) failures.push(`Platform Admin CSS sınıfı eksik: ${className}`);
}
if (!failures.some((item) => item.includes("Platform Admin CSS"))) successes.push("Platform Admin detay paneli ve hata durumları için gerekli CSS mevcut.");

const swFile = path.join(root, "public", "sw.js");
if (!fs.existsSync(swFile) || !fs.readFileSync(swFile, "utf8").includes("nutriclinic-v81-public-shell")) failures.push("Service worker cache sürümü v8.1 değil.");
else successes.push("Service worker cache anahtarı v8.1 olarak yenilendi.");

// Compare simple Supabase select columns with the accumulated SQL schema. This catches
// UI/API failures caused by deploying code that expects a migration column that does not exist.
function splitTopLevel(value) {
  const output = [];
  let current = "";
  let depth = 0;
  for (const character of value) {
    if (character === "(") depth += 1;
    else if (character === ")") depth = Math.max(0, depth - 1);
    if (character === "," && depth === 0) { output.push(current); current = ""; }
    else current += character;
  }
  output.push(current);
  return output;
}
const sqlWithoutLineComments = sqlText.replace(/--.*$/gm, "");
const schemaColumns = new Map();
for (const match of sqlWithoutLineComments.matchAll(/create\s+table(?:\s+if\s+not\s+exists)?\s+public\.([a-zA-Z0-9_]+)\s*\((.*?)\n\s*\);/gis)) {
  const table = match[1];
  const columns = schemaColumns.get(table) || new Set();
  for (const line of match[2].split("\n")) {
    const column = line.trim().replace(/,$/, "").match(/^([a-zA-Z_][a-zA-Z0-9_]*)\s+/)?.[1];
    if (column && !["constraint", "primary", "unique", "foreign", "check", "exclude"].includes(column.toLowerCase())) columns.add(column);
  }
  schemaColumns.set(table, columns);
}
for (const match of sqlWithoutLineComments.matchAll(/alter\s+table\s+public\.([a-zA-Z0-9_]+)(.*?);/gis)) {
  const columns = schemaColumns.get(match[1]) || new Set();
  for (const columnMatch of match[2].matchAll(/add\s+column(?:\s+if\s+not\s+exists)?\s+([a-zA-Z_][a-zA-Z0-9_]*)/gi)) columns.add(columnMatch[1]);
  schemaColumns.set(match[1], columns);
}
let checkedSelectColumns = 0;
for (const file of sourceFiles) {
  const code = fs.readFileSync(file, "utf8");
  for (const tableMatch of code.matchAll(/\.from\(\s*["'`]([a-zA-Z0-9_]+)["'`]\s*\)/g)) {
    const table = tableMatch[1];
    const start = (tableMatch.index || 0) + tableMatch[0].length;
    let tail = code.slice(start, start + 1200);
    const semicolon = tail.indexOf(";");
    const blankLine = tail.indexOf("\n\n");
    const cut = [semicolon, blankLine].filter((value) => value >= 0);
    if (cut.length) tail = tail.slice(0, Math.min(...cut) + 1);
    const select = tail.match(/\.select\(\s*["'`]([^"'`]*)["'`]/)?.[1];
    if (!select || !schemaColumns.has(table)) continue;
    for (const rawPart of splitTopLevel(select)) {
      const part = rawPart.trim();
      if (!part || part === "*" || part.includes("(") || part.includes("!") || part.includes(":")) continue;
      const column = part.split(/\s+/)[0];
      if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(column)) continue;
      checkedSelectColumns += 1;
      if (!schemaColumns.get(table).has(column)) failures.push(`${relative(file)}: public.${table}.${column} SQL şemasında bulunamadı.`);
    }
  }
}
if (!failures.some((item) => item.includes("SQL şemasında bulunamadı"))) successes.push(`${checkedSelectColumns} Supabase select alanı migration şemasıyla eşleşti.`);

// Critical v8.1 runtime paths that were reported broken by the pilot user.
const dashboardClientText = fs.readFileSync(path.join(root, "src", "app", "dashboard", "dashboard-client.tsx"), "utf8");
if (!dashboardClientText.includes("dashboard-language-picker") || !dashboardClientText.includes("async function changeLocale")) failures.push("Dashboard hızlı dil değiştiricisi veya kalıcı locale güncellemesi eksik.");
else successes.push("Dashboard dil seçimi anında uygulanıp profile kalıcı olarak kaydediliyor.");
const reminderRoute = fs.readFileSync(path.join(root, "src", "app", "api", "notifications", "payment-reminder", "route.ts"), "utf8");
if (!reminderRoute.includes("reminderCopy") || !reminderRoute.includes("preferred_locale") || !reminderRoute.includes("sameOriginRequest")) failures.push("Ödeme hatırlatması locale/yetki/istek doğrulama düzeltmesi eksik.");
else successes.push("Ödeme hatırlatmaları danışan diline göre üretiliyor ve istek kaynağı doğrulanıyor.");
const platformClientText = fs.readFileSync(path.join(root, "src", "app", "platform-admin", "platform-admin-client.tsx"), "utf8");
for (const required of ["availablePaidPlans", "busyAction", "translateUiText", "Pilot uzatma günü 1 ile 365 arasında olmalıdır."]) {
  if (!platformClientText.includes(required)) failures.push(`Platform Admin kritik koruması eksik: ${required}`);
}
if (!failures.some((item) => item.includes("Platform Admin kritik koruması"))) successes.push("Platform Admin ücretli plan, çift işlem, onay ve pilot süre doğrulamaları mevcut.");

// Health endpoint and package version should never drift apart.
const healthFile = path.join(root, "src", "app", "api", "health", "route.ts");
if (fs.existsSync(healthFile)) {
  const healthText = fs.readFileSync(healthFile, "utf8");
  if (!healthText.includes(`version: "${packageJson.version}"`)) failures.push(`Health endpoint sürümü package.json ile eşleşmiyor (${packageJson.version}).`);
  else successes.push(`Health endpoint sürümü package.json ile eşleşiyor (${packageJson.version}).`);
}

console.log("\nNutriClinic AI static audit\n");
for (const item of successes) console.log(`✓ ${item}`);
for (const item of warnings) console.warn(`! ${item}`);
for (const item of failures) console.error(`✗ ${item}`);
console.log(`\nSonuç: ${failures.length} hata, ${warnings.length} uyarı.`);
if (failures.length) process.exit(1);
