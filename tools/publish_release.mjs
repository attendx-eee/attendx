// Publishes a release to Firestore from the terminal.
//
//   node tools/publish_release.mjs --url "https://…/attendx-v1.2.8.apk" \
//                                  --notes "What changed" [--force]
//
// Why this exists: `latestVersionCode` is the field the update check
// actually compares against, and it was typed by hand. It got typed as 9
// while the build was 11, which means `latestCode > installedCode` was
// false for every student on the previous release — the rollout reached
// nobody and nothing reported a problem. A number that must match the
// build should be read from the build, not remembered.
//
// Both figures come from pubspec.yaml. There is no flag to override
// them, on purpose.
//
// Credentials: the same service account the Cloudflare worker uses.
// Put them in a gitignored .env beside this repo:
//
//   FIREBASE_PROJECT_ID=attendx-18717
//   FIREBASE_CLIENT_EMAIL=…@….iam.gserviceaccount.com
//   FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----\n"
//
// Nothing here ships in the APK. It is a release tool run from a laptop.

import { readFileSync } from "node:fs";
import { webcrypto } from "node:crypto";

const { subtle } = webcrypto;

// ---------------------------------------------------------------- args

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}

const apkUrl = arg("url");
const notes = arg("notes", "");
const force = process.argv.includes("--force");
const dryRun = process.argv.includes("--dry-run");

if (!apkUrl) {
  console.error(
    'Usage: node tools/publish_release.mjs --url "<apk url>" ' +
      '--notes "<what changed>" [--force] [--dry-run]'
  );
  process.exit(1);
}

// ------------------------------------------------------------- version

// pubspec carries `version: 1.2.8+11` — name before the plus, build
// number after. Both are what the app itself compiles in, so reading
// them here is the only way the published figures cannot disagree with
// the binary.
function versionFromPubspec() {
  const line = readFileSync("pubspec.yaml", "utf8")
    .split("\n")
    .find((l) => l.startsWith("version:"));

  if (!line) throw new Error("No `version:` line in pubspec.yaml");

  const raw = line.replace("version:", "").trim();
  const [name, code] = raw.split("+");

  if (!name || !code || Number.isNaN(Number(code))) {
    throw new Error(`Could not read a version and build number from "${raw}"`);
  }

  return { name: name.trim(), code: Number(code) };
}

// ----------------------------------------------------------------- env

function loadEnv() {
  let text = "";
  try {
    text = readFileSync(".env", "utf8");
  } catch {
    // Fall through to the process environment, so CI can supply them.
  }

  for (const line of text.split("\n")) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/);
    if (!match) continue;

    let value = match[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    process.env[match[1]] ??= value;
  }

  const missing = [
    "FIREBASE_PROJECT_ID",
    "FIREBASE_CLIENT_EMAIL",
    "FIREBASE_PRIVATE_KEY",
  ].filter((k) => !process.env[k]);

  if (missing.length) {
    throw new Error(
      `Missing ${missing.join(", ")}. Put them in a .env file — the same ` +
        `values the Cloudflare worker uses.`
    );
  }
}

// ------------------------------------------------------------- auth

// RS256 JWT, exchanged for an access token. Same approach as
// worker/src/index.js, which has been signing these for months.
async function accessToken() {
  const now = Math.floor(Date.now() / 1000);

  const claim = {
    iss: process.env.FIREBASE_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/datastore",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const b64 = (obj) =>
    Buffer.from(JSON.stringify(obj))
      .toString("base64url");

  const unsigned = `${b64({ alg: "RS256", typ: "JWT" })}.${b64(claim)}`;

  const pem = process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n");
  const der = Buffer.from(
    pem
      .replace(/-----[A-Z ]+-----/g, "")
      .replace(/\s+/g, ""),
    "base64"
  );

  const key = await subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned)
  );

  const jwt = `${unsigned}.${Buffer.from(signature).toString("base64url")}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    throw new Error(`Token exchange failed: ${await response.text()}`);
  }

  return (await response.json()).access_token;
}

// -------------------------------------------------------------- checks

// The same guard the console's Release screen applies, for the same
// reason: announcing a version whose file is not live sends everybody to
// a 404, and nobody finds out until a student says so.
async function checkLink(url) {
  try {
    const response = await fetch(url, { method: "HEAD", redirect: "follow" });

    if (response.status === 404) {
      return "returns 404 — the APK is not published at that URL yet";
    }
    if (!response.ok) {
      return `returned ${response.status}`;
    }
    return null;
  } catch (e) {
    // Inconclusive, not broken. Treated as a warning so a flaky network
    // cannot block a good release.
    console.warn(`  ! could not check the link (${e.message})`);
    return null;
  }
}

// ---------------------------------------------------------------- main

const { name, code } = versionFromPubspec();

console.log(`\n  version      ${name}  (code ${code})  — from pubspec.yaml`);
console.log(`  apk          ${apkUrl}`);
console.log(`  notes        ${notes || "(none)"}`);
console.log(`  forceUpdate  ${force}\n`);

if (!notes.trim()) {
  console.error(
    "  Refusing: --notes is empty, and whatever is there becomes the push\n" +
      "  notification every student receives.\n"
  );
  process.exit(1);
}

const problem = await checkLink(apkUrl);
if (problem) {
  console.error(`  Refusing: that link ${problem}.\n`);
  process.exit(1);
}

if (dryRun) {
  console.log("  --dry-run, nothing written.\n");
  process.exit(0);
}

loadEnv();
const token = await accessToken();

const project = process.env.FIREBASE_PROJECT_ID;
const path =
  `https://firestore.googleapis.com/v1/projects/${project}` +
  `/databases/(default)/documents/app_meta/android`;

// updateMask so nothing else in the document is disturbed.
const mask = [
  "apkUrl",
  "latestVersion",
  "latestVersionCode",
  "forceUpdate",
  "notes",
]
  .map((f) => `updateMask.fieldPaths=${f}`)
  .join("&");

const response = await fetch(`${path}?${mask}`, {
  method: "PATCH",
  headers: {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    fields: {
      apkUrl: { stringValue: apkUrl },
      latestVersion: { stringValue: name },
      latestVersionCode: { integerValue: String(code) },
      forceUpdate: { booleanValue: force },
      notes: { stringValue: notes },
    },
  }),
});

if (!response.ok) {
  console.error(`  Write failed: ${await response.text()}\n`);
  process.exit(1);
}

console.log("  Published. Installed apps will offer the update.\n");
