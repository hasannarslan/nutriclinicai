import { randomBytes } from "node:crypto";

console.log(`CRON_SECRET=${randomBytes(32).toString("hex")}`);
console.log(`PLATFORM_SETUP_TOKEN=${randomBytes(32).toString("hex")}`);
