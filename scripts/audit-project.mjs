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

const requiredMigrations = ["019_saas_pilot_multi_tenant.sql", "020_public_registration_and_pilot_applications.sql", "021_platform_clinic_details_and_paid_conversion.sql", "022_stabilization_and_lifecycle_fix.sql"];
for (const migration of requiredMigrations) {
  if (!fs.existsSync(path.join(root, "supabase", "migrations", migration))) failures.push(`Eksik migration: ${migration}`);
}

const baseline = path.join(root, "supabase", "baseline", "production_baseline_v8.sql");
if (!fs.existsSync(baseline)) failures.push("Fresh kurulum baseline dosyası eksik: production_baseline_v8.sql");
else {
  const baselineText = fs.readFileSync(baseline, "utf8");
  if (!baselineText.includes("normalize_subscription_lifecycle_v8")) failures.push("v8 baseline yaşam döngüsü düzeltmesini içermiyor.");
  else successes.push("v8 fresh production baseline mevcut ve 022 düzeltmesini içeriyor.");
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
