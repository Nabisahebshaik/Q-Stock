// Vercel build: live mode when an R API URL is configured (Vercel env var VITE_API_URL or
// web/.env.production), otherwise the static snapshot. Both include public/data, which the
// live build uses as a fallback while the API is unreachable.
import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

const fromFile = existsSync(".env.production")
  ? (readFileSync(".env.production", "utf8").match(/^VITE_API_URL=(.+)$/m)?.[1] ?? "").trim()
  : "";
const api = (process.env.VITE_API_URL ?? "").trim() || fromFile;
const cmd = api ? "vite build --outDir dist-vercel" : "vite build --mode snapshot --outDir dist-vercel";
console.log(api ? `Live build against ${api}` : "No VITE_API_URL: static snapshot build");
execSync(cmd, { stdio: "inherit" });
