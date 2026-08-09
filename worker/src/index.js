/**
 * AttendX push worker.
 *
 * Cloud Functions would be the obvious home for this, but deploying one
 * requires the Blaze plan and therefore a card on file. FCM itself is
 * free and unlimited on the free plan — the only thing Blaze was buying
 * was somewhere to run the sender. So the sender runs here instead, on
 * Cloudflare's free tier: no card, always on, 100,000 requests a day
 * against a workload that uses about 1,440.
 *
 * Design: a cron sweep, not a webhook.
 *
 * A webhook would be marginally faster but needs a public endpoint,
 * which needs authentication, which means shipping a shared secret in
 * the APK where anyone can extract it. The sweep has no attack surface
 * at all — nothing outside Cloudflare can invoke it — and it keeps
 * working when the device that wrote the notification goes offline a
 * second later, which a fire-and-forget webhook call would not. The
 * cost is up to 60 seconds of delay, which for "you were marked absent"
 * is not a meaningful difference.
 *
 * Everything already writes to the `notifications` collection, so
 * nothing in the app had to change except a `pushed: false` flag.
 *
 * Secrets (wrangler secret put):
 *   FIREBASE_PROJECT_ID     e.g. attendx-18717
 *   FIREBASE_CLIENT_EMAIL   from the service-account JSON
 *   FIREBASE_PRIVATE_KEY    from the service-account JSON, PEM, \n intact
 */

const OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPES = [
  "https://www.googleapis.com/auth/firebase.messaging",
  "https://www.googleapis.com/auth/datastore",
].join(" ");

/** How many notifications one sweep will handle. */
const BATCH_LIMIT = 50;

/** Collections that may hold an account, in the order they're checked. */
const ACCOUNT_COLLECTIONS = ["students", "faculty_accounts", "admin"];

// Access tokens last an hour. Cached at module scope so a warm isolate
// reuses one instead of doing an RSA signature and a round trip every
// single minute.
let cachedToken = null;
let cachedTokenExpiry = 0;

// ---------------------------------------------------------------- auth

function base64url(input) {
  const bytes =
    typeof input === "string" ? new TextEncoder().encode(input) : input;

  let binary = "";
  for (const b of new Uint8Array(bytes)) binary += String.fromCharCode(b);

  return btoa(binary)
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
}

/** PEM -> ArrayBuffer, for crypto.subtle.importKey. */
function pemToBinary(pem) {
  const body = pem
      .replace(/-----BEGIN PRIVATE KEY-----/, "")
      .replace(/-----END PRIVATE KEY-----/, "")
      .replace(/\s+/g, "");

  const raw = atob(body);
  const buffer = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buffer[i] = raw.charCodeAt(i);

  return buffer.buffer;
}

/**
 * Mints a Google OAuth access token from the service-account key.
 *
 * This is the whole reason a server is needed: the signature below
 * requires the private key, and a private key inside an APK is a
 * private key belonging to everyone who downloads it.
 *
 * @param {object} env Worker environment bindings.
 * @return {Promise<string>} Bearer token.
 */
async function getAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);

  // 60s of slack so a token can't expire mid-request.
  if (cachedToken && now < cachedTokenExpiry - 60) return cachedToken;

  const header = {alg: "RS256", typ: "JWT"};
  const claims = {
    iss: env.FIREBASE_CLIENT_EMAIL,
    scope: SCOPES,
    aud: OAUTH_TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };

  const unsigned =
    `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;

  // Wrangler stores the key with literal backslash-n when it's pasted
  // from JSON, so it has to be turned back into real newlines or the
  // PEM parse silently produces garbage.
  const pem = env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n");

  const key = await crypto.subtle.importKey(
      "pkcs8",
      pemToBinary(pem),
      {name: "RSASSA-PKCS1-v1_5", hash: "SHA-256"},
      false,
      ["sign"],
  );

  const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
  );

  const assertion = `${unsigned}.${base64url(signature)}`;

  const response = await fetch(OAUTH_TOKEN_URL, {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(`Token exchange failed: ${await response.text()}`);
  }

  const json = await response.json();
  cachedToken = json.access_token;
  cachedTokenExpiry = now + (json.expires_in || 3600);

  return cachedToken;
}

// ----------------------------------------------------------- firestore

function firestoreBase(projectId) {
  return `https://firestore.googleapis.com/v1/projects/${projectId}` +
    "/databases/(default)/documents";
}

/** Unwraps Firestore's typed value encoding into plain JS. */
function plain(value) {
  if (!value) return null;
  if ("stringValue" in value) return value.stringValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("arrayValue" in value) {
    return (value.arrayValue.values || []).map(plain);
  }
  if ("mapValue" in value) {
    const out = {};
    for (const [k, v] of Object.entries(value.mapValue.fields || {})) {
      out[k] = plain(v);
    }
    return out;
  }
  return null;
}

async function unsentNotifications(env, token) {
  const response = await fetch(`${firestoreBase(env.FIREBASE_PROJECT_ID)}:runQuery`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      structuredQuery: {
        from: [{collectionId: "notifications"}],
        where: {
          fieldFilter: {
            field: {fieldPath: "pushed"},
            op: "EQUAL",
            value: {booleanValue: false},
          },
        },
        limit: BATCH_LIMIT,
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`Query failed: ${await response.text()}`);
  }

  const rows = await response.json();

  return rows
      .filter((row) => row.document)
      .map((row) => ({
        name: row.document.name,
        fields: row.document.fields || {},
      }));
}

async function accountTokens(env, token, uid) {
  for (const collection of ACCOUNT_COLLECTIONS) {
    const url = `${firestoreBase(env.FIREBASE_PROJECT_ID)}/${collection}/${uid}`;
    const response = await fetch(url, {
      headers: {Authorization: `Bearer ${token}`},
    });

    if (response.status === 404) continue;
    if (!response.ok) continue;

    const doc = await response.json();
    const tokens = plain((doc.fields || {}).fcmTokens) || [];

    return {url, tokens: tokens.filter(Boolean)};
  }

  return null;
}

/** Marks a notification handled so the next sweep skips it. */
async function markPushed(token, documentName) {
  await fetch(
      `https://firestore.googleapis.com/v1/${documentName}` +
      "?updateMask.fieldPaths=pushed",
      {
        method: "PATCH",
        headers: {
          "Authorization": `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({fields: {pushed: {booleanValue: true}}}),
      },
  );
}

/**
 * Rewrites an account's token array without the dead entries.
 *
 * Tokens die on every uninstall, data wipe and restore-to-new-phone.
 * Left in place they make every later send report failure and the array
 * grows without limit.
 *
 * @param {string} token Bearer token.
 * @param {string} url Account document URL.
 * @param {string[]} keep Surviving tokens.
 */
async function pruneTokens(token, url, keep) {
  await fetch(`${url}?updateMask.fieldPaths=fcmTokens`, {
    method: "PATCH",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      fields: {
        fcmTokens: {
          arrayValue: {values: keep.map((t) => ({stringValue: t}))},
        },
      },
    }),
  });
}

// ------------------------------------------------------------------ fcm

async function sendToToken(env, accessToken, deviceToken, title, body, data) {
  const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: deviceToken,

            // Both blocks on purpose. `notification` is what Android
            // draws when the app is dead — the Dart isolate isn't
            // guaranteed to run in time to draw it itself. `data` is
            // what the app reads when it is running, so a foreground
            // message is styled by us rather than by the system.
            notification: {title, body},
            data: {
              title,
              body,
              category: String(data.category || "general"),
              action: String(data.action || ""),
            },

            android: {
              priority: "HIGH",
              notification: {
                // Must match the channel created in
                // LocalNotificationService.init and declared in the
                // manifest, or API 26+ discards it in silence.
                channel_id: "realtime_alerts",
                tag: String(data.category || "general"),
              },
            },

            apns: {payload: {aps: {sound: "default"}}},
          },
        }),
      },
  );

  if (response.ok) return {ok: true};

  const text = await response.text();

  // 404 UNREGISTERED and 400 INVALID_ARGUMENT both mean this token will
  // never work again.
  const dead =
    response.status === 404 ||
    (response.status === 400 && text.includes("INVALID_ARGUMENT"));

  return {ok: false, dead, error: text};
}

// ------------------------------------------------------------- the job

async function sweep(env) {
  const token = await getAccessToken(env);
  const pending = await unsentNotifications(env, token);

  if (pending.length === 0) return "nothing pending";

  let sent = 0;
  let skipped = 0;

  for (const doc of pending) {
    const uid = plain(doc.fields.studentUid);

    // Marked handled even with no recipient, or a malformed document
    // would be retried every minute forever.
    if (!uid) {
      await markPushed(token, doc.name);
      skipped++;
      continue;
    }

    const account = await accountTokens(env, token, uid);

    if (!account || account.tokens.length === 0) {
      await markPushed(token, doc.name);
      skipped++;
      continue;
    }

    const title = plain(doc.fields.title) || "AttendX";
    const body = plain(doc.fields.body) || "";
    const meta = {
      category: plain(doc.fields.category),
      action: plain(doc.fields.action),
    };

    const alive = [];
    for (const deviceToken of account.tokens) {
      const result = await sendToToken(env, token, deviceToken, title, body, meta);

      if (result.ok) {
        alive.push(deviceToken);
        sent++;
      } else if (!result.dead) {
        // A transient failure keeps the token; only permanent
        // rejections drop it.
        alive.push(deviceToken);
        console.warn(`Send failed for ${uid}: ${result.error}`);
      }
    }

    if (alive.length !== account.tokens.length) {
      await pruneTokens(token, account.url, alive);
    }

    await markPushed(token, doc.name);
  }

  return `sent ${sent}, skipped ${skipped}, scanned ${pending.length}`;
}

export default {
  /** Cloudflare cron entry point. */
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
        sweep(env)
            .then((summary) => console.log(`Sweep: ${summary}`))
            .catch((e) => console.error(`Sweep failed: ${e.message}`)),
    );
  },

  /**
   * Manual trigger, for checking the thing works without waiting for
   * the next minute. Read-only in the sense that it does exactly what
   * the cron does — there is nothing here a scheduled run wouldn't also
   * do, so leaving it open costs nothing beyond a wasted sweep.
   *
   * @param {Request} request Incoming request.
   * @param {object} env Worker environment bindings.
   * @return {Promise<Response>} Plain-text summary.
   */
  async fetch(request, env) {
    try {
      const summary = await sweep(env);
      return new Response(`OK — ${summary}\n`);
    } catch (e) {
      return new Response(`Failed: ${e.message}\n`, {status: 500});
    }
  },
};
